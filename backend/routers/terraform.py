from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from auth.dependencies import get_current_user, require_role
from db.database import log_activity
from models.schemas import TerraformWorkspaceRequest, TerraformApplyRequest, TerraformDestroyRequest
from services.terraform_runner import (
    list_workspaces, terraform_init, terraform_plan_stream,
    terraform_apply, terraform_destroy,
)

router = APIRouter()


@router.get("/workspaces")
async def get_workspaces(user: dict = Depends(get_current_user)):
    return {"workspaces": list_workspaces()}


@router.post("/init")
async def init_workspace(body: TerraformWorkspaceRequest, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await terraform_init(body.workspace)
        status = "OK" if result["returncode"] == 0 else "FAIL"
        await log_activity(user["username"], "TF_INIT", f"tf:{body.workspace}", status)
        if result["returncode"] != 0:
            raise HTTPException(status_code=500, detail=result["stderr"])
        return result
    except HTTPException:
        raise
    except Exception as e:
        await log_activity(user["username"], "TF_INIT", f"tf:{body.workspace}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/plan")
async def plan_workspace(body: TerraformWorkspaceRequest, user: dict = Depends(require_role("admin", "engineer"))):
    await log_activity(user["username"], "TF_PLAN", f"tf:{body.workspace}", "STARTED")

    async def _generate():
        async for line in await terraform_plan_stream(body.workspace):
            yield f"data: {line}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(_generate(), media_type="text/event-stream")


@router.post("/apply")
async def apply_workspace(body: TerraformApplyRequest, user: dict = Depends(require_role("admin"))):
    if not body.confirm:
        raise HTTPException(status_code=400, detail="confirm must be true to apply")
    try:
        result = await terraform_apply(body.workspace)
        status = "OK" if result["returncode"] == 0 else "FAIL"
        await log_activity(user["username"], "TF_APPLY", f"tf:{body.workspace}", status)
        if result["returncode"] != 0:
            raise HTTPException(status_code=500, detail=result["stderr"])
        return result
    except HTTPException:
        raise
    except Exception as e:
        await log_activity(user["username"], "TF_APPLY", f"tf:{body.workspace}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/destroy")
async def destroy_workspace(body: TerraformDestroyRequest, user: dict = Depends(require_role("admin"))):
    if not body.confirm or not body.destroy:
        raise HTTPException(status_code=400, detail="confirm and destroy must both be true")
    try:
        result = await terraform_destroy(body.workspace)
        status = "OK" if result["returncode"] == 0 else "FAIL"
        await log_activity(user["username"], "TF_DESTROY", f"tf:{body.workspace}", status)
        if result["returncode"] != 0:
            raise HTTPException(status_code=500, detail=result["stderr"])
        return result
    except HTTPException:
        raise
    except Exception as e:
        await log_activity(user["username"], "TF_DESTROY", f"tf:{body.workspace}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))
