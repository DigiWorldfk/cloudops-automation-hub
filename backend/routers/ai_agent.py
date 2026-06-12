"""
CloudOps AI Agent Router
========================
Endpoints:
  POST /api/ai/chat          — streaming SSE chat with function calling
  GET  /api/ai/approvals     — list pending approval requests
  POST /api/ai/approvals/{id}/approve — execute an approved action
  POST /api/ai/approvals/{id}/deny    — deny a queued action
"""

import os
import json
import logging
from typing import AsyncGenerator

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import List, Optional

from auth.dependencies import get_current_user, require_role
from db.database import log_activity, get_approvals, create_approval, update_approval
from services.ai_tools import OPENAI_TOOLS, execute_tool, tool_risk_tier, TOOL_REGISTRY, GREEN

logger = logging.getLogger(__name__)
router = APIRouter()

# ── OpenAI client factory ──────────────────────────────────────────────────────

def _get_openai_client():
    """Return an OpenAI or AzureOpenAI client depending on env vars. Raises if not configured."""
    azure_endpoint = os.getenv("AZURE_OPENAI_ENDPOINT", "").strip()
    azure_key      = os.getenv("AZURE_OPENAI_KEY", "").strip()
    openai_key     = os.getenv("OPENAI_API_KEY", "").strip()

    if azure_endpoint and azure_key:
        try:
            from openai import AzureOpenAI
            return AzureOpenAI(
                azure_endpoint=azure_endpoint,
                api_key=azure_key,
                api_version=os.getenv("AZURE_OPENAI_API_VERSION", "2024-10-21"),
            ), os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4o")
        except ImportError:
            raise HTTPException(status_code=500, detail="openai package not installed")
    elif openai_key:
        try:
            from openai import OpenAI
            return OpenAI(api_key=openai_key), os.getenv("OPENAI_MODEL", "gpt-4o")
        except ImportError:
            raise HTTPException(status_code=500, detail="openai package not installed")
    else:
        raise HTTPException(
            status_code=503,
            detail="AI agent not configured. Set AZURE_OPENAI_ENDPOINT+AZURE_OPENAI_KEY or OPENAI_API_KEY in .env",
        )


SYSTEM_PROMPT = """You are CloudOps Assistant, an AI-powered Platform Engineering agent.
You help engineers manage AWS, Azure, Kubernetes, Docker, and Terraform environments.

You have access to tools that let you query and control infrastructure.
Tools are classified by risk:
- GREEN: read-only or safe operations — you execute these immediately
- AMBER: mutations that can be reversed (start/stop/scale/cordon) — these go to an approval queue
- RED: destructive or hard-to-reverse actions (drain node) — these go to an approval queue

When you call a GREEN tool, report the result clearly and concisely.
When an AMBER or RED tool is queued for approval, tell the user it is pending admin approval.
Always be concise, accurate, and professional. Format lists as short tables when helpful.
Never fabricate infrastructure data — only report what the tools return.
If a tool fails, report the error clearly and suggest next steps."""


# ── Schemas ───────────────────────────────────────────────────────────────────

class ChatMessage(BaseModel):
    role: str   # "user" | "assistant"
    content: str

class AIChatRequest(BaseModel):
    message: str
    history: List[ChatMessage] = []


# ── SSE helpers ───────────────────────────────────────────────────────────────

def _sse(event: dict) -> str:
    return f"data: {json.dumps(event)}\n\n"


# ── Chat endpoint ─────────────────────────────────────────────────────────────

@router.post("/chat")
async def ai_chat(
    req: AIChatRequest,
    user: dict = Depends(get_current_user),
):
    """Streaming SSE endpoint. Yields `data: {json}` events."""

    async def _generate() -> AsyncGenerator[str, None]:
        try:
            client, model = _get_openai_client()
        except HTTPException as exc:
            yield _sse({"type": "error", "content": exc.detail})
            yield _sse({"type": "done"})
            return

        # Build message list
        messages = [{"role": "system", "content": SYSTEM_PROMPT}]
        for h in req.history:
            messages.append({"role": h.role, "content": h.content})
        messages.append({"role": "user", "content": req.message})

        # We may loop for multi-turn tool calls (green tools can chain)
        MAX_TOOL_ROUNDS = 5
        for _round in range(MAX_TOOL_ROUNDS):
            # Call OpenAI with streaming
            try:
                stream = client.chat.completions.create(
                    model=model,
                    messages=messages,
                    tools=OPENAI_TOOLS,
                    tool_choice="auto",
                    stream=True,
                )
            except Exception as exc:
                yield _sse({"type": "error", "content": f"OpenAI error: {exc}"})
                yield _sse({"type": "done"})
                return

            # Accumulate the streamed response
            full_text      = ""
            tool_calls_acc = {}   # index -> {id, name, arguments_str}
            finish_reason  = None

            for chunk in stream:
                choice = chunk.choices[0] if chunk.choices else None
                if not choice:
                    continue

                delta = choice.delta

                # Stream text tokens
                if delta.content:
                    full_text += delta.content
                    yield _sse({"type": "token", "content": delta.content})

                # Accumulate tool call arguments (arrive in fragments)
                if delta.tool_calls:
                    for tc in delta.tool_calls:
                        idx = tc.index
                        if idx not in tool_calls_acc:
                            tool_calls_acc[idx] = {"id": "", "name": "", "arguments": ""}
                        if tc.id:
                            tool_calls_acc[idx]["id"] = tc.id
                        if tc.function:
                            if tc.function.name:
                                tool_calls_acc[idx]["name"] = tc.function.name
                            if tc.function.arguments:
                                tool_calls_acc[idx]["arguments"] += tc.function.arguments

                if choice.finish_reason:
                    finish_reason = choice.finish_reason

            # ── Process tool calls ───────────────────────────────────────────
            if finish_reason == "tool_calls" and tool_calls_acc:
                # Build the assistant message with tool_calls for the next round
                assistant_msg = {
                    "role": "assistant",
                    "content": full_text or None,
                    "tool_calls": [
                        {
                            "id":       tc["id"],
                            "type":     "function",
                            "function": {"name": tc["name"], "arguments": tc["arguments"]},
                        }
                        for tc in tool_calls_acc.values()
                    ],
                }
                messages.append(assistant_msg)

                has_pending_approval = False

                for tc in tool_calls_acc.values():
                    tool_name = tc["name"]
                    try:
                        tool_args = json.loads(tc["arguments"]) if tc["arguments"] else {}
                    except json.JSONDecodeError:
                        tool_args = {}

                    tier = tool_risk_tier(tool_name)

                    # Notify frontend a tool is being called
                    yield _sse({"type": "tool_call", "name": tool_name, "args": tool_args, "tier": tier})

                    if tier == GREEN:
                        # Execute immediately
                        try:
                            result = await execute_tool(tool_name, tool_args)
                            result_str = json.dumps(result, default=str)
                            yield _sse({"type": "tool_result", "name": tool_name, "result": result, "tier": tier})
                            # Feed result back so the model can describe it
                            messages.append({
                                "role": "tool",
                                "tool_call_id": tc["id"],
                                "content": result_str,
                            })
                            await log_activity(
                                user["username"], f"AI:{tool_name.upper()}",
                                json.dumps(tool_args), "success",
                                detail=f"executed by ai_agent"
                            )
                        except Exception as exc:
                            err = str(exc)
                            yield _sse({"type": "tool_result", "name": tool_name, "result": {"error": err}, "tier": tier})
                            messages.append({
                                "role": "tool",
                                "tool_call_id": tc["id"],
                                "content": f"Error: {err}",
                            })
                    else:
                        # Queue for approval
                        approval_id = await create_approval(
                            requested_by=user["username"],
                            tool_name=tool_name,
                            tool_args=tool_args,
                            risk_tier=tier,
                        )
                        yield _sse({
                            "type":    "approval_queued",
                            "id":      approval_id,
                            "tool":    tool_name,
                            "args":    tool_args,
                            "tier":    tier,
                        })
                        # Feed a synthetic tool result so the model can respond
                        messages.append({
                            "role": "tool",
                            "tool_call_id": tc["id"],
                            "content": f"Action '{tool_name}' has been queued for admin approval (id={approval_id}). It will execute once approved.",
                        })
                        has_pending_approval = True
                        await log_activity(
                            user["username"], f"AI:{tool_name.upper()}",
                            json.dumps(tool_args), "pending_approval",
                            detail=f"approval_id={approval_id}"
                        )

                # Continue to next round (model will now generate a natural-language summary)
                continue

            # finish_reason == "stop" — we're done
            break

        yield _sse({"type": "done"})

    return StreamingResponse(_generate(), media_type="text/event-stream")


# ── Approvals endpoints ────────────────────────────────────────────────────────

@router.get("/approvals")
async def list_approvals(
    status: Optional[str] = "pending",
    user: dict = Depends(get_current_user),
):
    """List approval requests. Defaults to pending only."""
    return await get_approvals(status=status)


@router.post("/approvals/{approval_id}/approve")
async def approve_action(
    approval_id: int,
    user: dict = Depends(require_role("admin")),
):
    """Approve and immediately execute a queued action."""
    approvals = await get_approvals(status="pending")
    record = next((a for a in approvals if a["id"] == approval_id), None)
    if not record:
        raise HTTPException(status_code=404, detail="Approval not found or not pending")

    tool_name = record["tool_name"]
    tool_args = json.loads(record["tool_args"])

    await update_approval(approval_id, status="approved", reviewed_by=user["username"])

    try:
        result = await execute_tool(tool_name, tool_args)
        result_str = json.dumps(result, default=str)
        await update_approval(approval_id, status="executed", result=result_str)
        await log_activity(
            user["username"], f"APPROVE:{tool_name.upper()}",
            json.dumps(tool_args), "success",
            detail=f"approval_id={approval_id}"
        )
        return {"status": "executed", "result": result}
    except Exception as exc:
        err = str(exc)
        await update_approval(approval_id, status="failed", result=err)
        await log_activity(
            user["username"], f"APPROVE:{tool_name.upper()}",
            json.dumps(tool_args), "failed",
            detail=err
        )
        raise HTTPException(status_code=500, detail=f"Execution failed: {err}")


@router.post("/approvals/{approval_id}/deny")
async def deny_action(
    approval_id: int,
    user: dict = Depends(require_role("admin")),
):
    """Deny a queued action."""
    approvals = await get_approvals(status="pending")
    record = next((a for a in approvals if a["id"] == approval_id), None)
    if not record:
        raise HTTPException(status_code=404, detail="Approval not found or not pending")

    await update_approval(approval_id, status="denied", reviewed_by=user["username"])
    await log_activity(
        user["username"], f"DENY:{record['tool_name'].upper()}",
        record["tool_args"], "denied",
        detail=f"approval_id={approval_id}"
    )
    return {"status": "denied"}
