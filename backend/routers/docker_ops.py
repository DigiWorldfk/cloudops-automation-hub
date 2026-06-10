from fastapi import APIRouter, Depends, HTTPException, Query
from auth.dependencies import get_current_user, require_role
from db.database import log_activity
from models.schemas import DockerPullRequest
from services.docker_client import (
    docker_list_containers, docker_start_container, docker_stop_container,
    docker_restart_container, docker_remove_container, docker_get_logs,
    docker_list_images, docker_pull_image,
)

router = APIRouter()


@router.get("/containers")
async def list_containers(all: bool = Query(True), user: dict = Depends(get_current_user)):
    try:
        return docker_list_containers(all_containers=all)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/containers/{container_id}/start")
async def start_container(container_id: str, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = docker_start_container(container_id)
        await log_activity(user["username"], "START_CONTAINER", f"docker:{container_id}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "START_CONTAINER", f"docker:{container_id}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/containers/{container_id}/stop")
async def stop_container(container_id: str, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = docker_stop_container(container_id)
        await log_activity(user["username"], "STOP_CONTAINER", f"docker:{container_id}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "STOP_CONTAINER", f"docker:{container_id}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/containers/{container_id}/restart")
async def restart_container(container_id: str, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = docker_restart_container(container_id)
        await log_activity(user["username"], "RESTART_CONTAINER", f"docker:{container_id}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "RESTART_CONTAINER", f"docker:{container_id}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/containers/{container_id}/logs")
async def get_logs(container_id: str, tail: int = Query(100, ge=1, le=5000),
                   user: dict = Depends(get_current_user)):
    try:
        logs = docker_get_logs(container_id, tail=tail)
        return {"logs": logs}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/containers/{container_id}")
async def remove_container(container_id: str, user: dict = Depends(require_role("admin"))):
    try:
        result = docker_remove_container(container_id)
        await log_activity(user["username"], "REMOVE_CONTAINER", f"docker:{container_id}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "REMOVE_CONTAINER", f"docker:{container_id}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/images")
async def list_images(user: dict = Depends(get_current_user)):
    try:
        return docker_list_images()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/images/pull")
async def pull_image(body: DockerPullRequest, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = docker_pull_image(body.image)
        await log_activity(user["username"], "PULL_IMAGE", f"docker:{body.image}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "PULL_IMAGE", f"docker:{body.image}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))
