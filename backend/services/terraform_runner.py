import os
import subprocess
import asyncio
from pathlib import Path
from typing import Iterator, AsyncIterator

WORKSPACES_ROOT = os.getenv("TERRAFORM_WORKSPACES", "/app/terraform-workspaces")


def workspace_path(workspace: str) -> Path:
    base = Path(WORKSPACES_ROOT).resolve()
    target = (base / workspace).resolve()
    if not str(target).startswith(str(base)):
        raise ValueError("Invalid workspace name")
    return target


def list_workspaces() -> list:
    base = Path(WORKSPACES_ROOT)
    base.mkdir(parents=True, exist_ok=True)
    return [d.name for d in sorted(base.iterdir()) if d.is_dir()]


def _run(args: list, cwd: Path) -> tuple[int, str, str]:
    result = subprocess.run(
        args, cwd=str(cwd),
        capture_output=True, text=True, timeout=600,
        env={**os.environ, "TF_IN_AUTOMATION": "true"},
    )
    return result.returncode, result.stdout, result.stderr


async def terraform_init(workspace: str) -> dict:
    def _init():
        cwd = workspace_path(workspace)
        rc, out, err = _run(["terraform", "init", "-no-color"], cwd)
        return {"returncode": rc, "stdout": out, "stderr": err}
    return await asyncio.to_thread(_init)


async def terraform_plan_stream(workspace: str) -> AsyncIterator[str]:
    cwd = workspace_path(workspace)

    async def _stream():
        proc = await asyncio.create_subprocess_exec(
            "terraform", "plan", "-no-color",
            cwd=str(cwd),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            env={**os.environ, "TF_IN_AUTOMATION": "true"},
        )
        async for line in proc.stdout:
            yield line.decode("utf-8", errors="replace")
        await proc.wait()

    return _stream()


async def terraform_apply(workspace: str) -> dict:
    def _apply():
        cwd = workspace_path(workspace)
        rc, out, err = _run(["terraform", "apply", "-auto-approve", "-no-color"], cwd)
        return {"returncode": rc, "stdout": out[-5000:], "stderr": err[-2000:]}
    return await asyncio.to_thread(_apply)


async def terraform_destroy(workspace: str) -> dict:
    def _destroy():
        cwd = workspace_path(workspace)
        rc, out, err = _run(["terraform", "destroy", "-auto-approve", "-no-color"], cwd)
        return {"returncode": rc, "stdout": out[-5000:], "stderr": err[-2000:]}
    return await asyncio.to_thread(_destroy)
