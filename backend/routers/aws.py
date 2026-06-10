from fastapi import APIRouter, Depends, HTTPException, Query
from auth.dependencies import get_current_user, require_role
from db.database import log_activity
from models.schemas import AWSInstanceCreateRequest, AWSInstanceResizeRequest, AWSVolumeCreateRequest
from services.aws_client import (
    aws_list_instances, aws_create_instance, aws_terminate_instance,
    aws_start_instance, aws_stop_instance, aws_resize_instance,
    aws_snapshot_instance, aws_create_volume,
    aws_run_patch_baseline, aws_patch_status, aws_get_costs,
)

router = APIRouter()


@router.get("/instances")
async def list_instances(user: dict = Depends(get_current_user)):
    try:
        return await aws_list_instances()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/instances")
async def create_instance(body: AWSInstanceCreateRequest, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await aws_create_instance(
            body.ami_id, body.instance_type, body.subnet_id,
            body.security_group_ids, body.key_name, body.name_tag,
        )
        await log_activity(user["username"], "CREATE_EC2", f"aws:{body.name_tag}", "OK", str(result))
        return result
    except Exception as e:
        await log_activity(user["username"], "CREATE_EC2", f"aws:{body.name_tag}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/instances/{instance_id}")
async def terminate_instance(instance_id: str, user: dict = Depends(require_role("admin"))):
    try:
        result = await aws_terminate_instance(instance_id)
        await log_activity(user["username"], "TERMINATE_EC2", f"aws:{instance_id}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "TERMINATE_EC2", f"aws:{instance_id}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/instances/{instance_id}/start")
async def start_instance(instance_id: str, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await aws_start_instance(instance_id)
        await log_activity(user["username"], "START_EC2", f"aws:{instance_id}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "START_EC2", f"aws:{instance_id}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/instances/{instance_id}/stop")
async def stop_instance(instance_id: str, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await aws_stop_instance(instance_id)
        await log_activity(user["username"], "STOP_EC2", f"aws:{instance_id}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "STOP_EC2", f"aws:{instance_id}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/instances/{instance_id}/resize")
async def resize_instance(instance_id: str, body: AWSInstanceResizeRequest,
                           user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await aws_resize_instance(instance_id, body.instance_type)
        await log_activity(user["username"], "RESIZE_EC2", f"aws:{instance_id}", "OK", body.instance_type)
        return result
    except Exception as e:
        await log_activity(user["username"], "RESIZE_EC2", f"aws:{instance_id}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/instances/{instance_id}/snapshot")
async def snapshot_instance(instance_id: str, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await aws_snapshot_instance(instance_id, f"cloudops-snapshot-{instance_id}")
        await log_activity(user["username"], "SNAPSHOT_EC2", f"aws:{instance_id}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "SNAPSHOT_EC2", f"aws:{instance_id}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/volumes")
async def create_volume(body: AWSVolumeCreateRequest, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await aws_create_volume(body.instance_id, body.size_gb, body.volume_type, body.availability_zone)
        await log_activity(user["username"], "CREATE_VOLUME", f"aws:{body.instance_id}", "OK", f"{body.size_gb}GB")
        return result
    except Exception as e:
        await log_activity(user["username"], "CREATE_VOLUME", f"aws:{body.instance_id}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/instances/{instance_id}/patch")
async def patch_instance(instance_id: str, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await aws_run_patch_baseline(instance_id)
        await log_activity(user["username"], "PATCH_EC2", f"aws:{instance_id}", "OK", result.get("command_id"))
        return result
    except Exception as e:
        await log_activity(user["username"], "PATCH_EC2", f"aws:{instance_id}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/instances/{instance_id}/patch-status")
async def get_patch_status(instance_id: str, command_id: str = Query(...),
                            user: dict = Depends(get_current_user)):
    try:
        return await aws_patch_status(instance_id, command_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/costs")
async def get_costs(period_days: int = Query(30, ge=1, le=365), user: dict = Depends(get_current_user)):
    try:
        return await aws_get_costs(period_days)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
