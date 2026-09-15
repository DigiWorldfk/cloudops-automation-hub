from fastapi import APIRouter, Depends, HTTPException
from auth.dependencies import get_current_user, require_role
from db.database import log_activity
from models.schemas import (
    AzureVMCreateRequest, AzureVMResizeRequest, AzureDiskExpandRequest,
)
from services.azure_client import (
    azure_list_vms, azure_create_vm, azure_delete_vm,
    azure_start_vm, azure_stop_vm, azure_resize_vm,
    azure_snapshot_vm, azure_expand_disk,
)
from errors import audit_error, operation_error
import logging

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get("/vms")
async def list_vms(user: dict = Depends(get_current_user)):
    try:
        return await azure_list_vms()
    except Exception as e:
        raise operation_error(logger, "list Azure VMs", e)


@router.post("/vms")
async def create_vm(body: AzureVMCreateRequest, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await azure_create_vm(
            body.resource_group, body.name, body.location,
            body.vm_size, body.image, body.admin_username, body.admin_password,
        )
        await log_activity(user["username"], "CREATE_VM", f"azure:{body.resource_group}/{body.name}", "OK", str(result))
        return result
    except Exception as e:
        await log_activity(user["username"], "CREATE_VM", f"azure:{body.resource_group}/{body.name}", "FAIL", audit_error(e))
        raise operation_error(logger, "create Azure VM", e)


@router.delete("/vms/{resource_group}/{name}")
async def delete_vm(resource_group: str, name: str, user: dict = Depends(require_role("admin"))):
    try:
        result = await azure_delete_vm(resource_group, name)
        await log_activity(user["username"], "DELETE_VM", f"azure:{resource_group}/{name}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "DELETE_VM", f"azure:{resource_group}/{name}", "FAIL", audit_error(e))
        raise operation_error(logger, "delete Azure VM", e)


@router.post("/vms/{resource_group}/{name}/start")
async def start_vm(resource_group: str, name: str, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await azure_start_vm(resource_group, name)
        await log_activity(user["username"], "START_VM", f"azure:{resource_group}/{name}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "START_VM", f"azure:{resource_group}/{name}", "FAIL", audit_error(e))
        raise operation_error(logger, "start Azure VM", e)


@router.post("/vms/{resource_group}/{name}/stop")
async def stop_vm(resource_group: str, name: str, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await azure_stop_vm(resource_group, name)
        await log_activity(user["username"], "STOP_VM", f"azure:{resource_group}/{name}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "STOP_VM", f"azure:{resource_group}/{name}", "FAIL", audit_error(e))
        raise operation_error(logger, "stop Azure VM", e)


@router.post("/vms/{resource_group}/{name}/resize")
async def resize_vm(resource_group: str, name: str, body: AzureVMResizeRequest,
                    user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await azure_resize_vm(resource_group, name, body.vm_size)
        await log_activity(user["username"], "RESIZE_VM", f"azure:{resource_group}/{name}", "OK", body.vm_size)
        return result
    except Exception as e:
        await log_activity(user["username"], "RESIZE_VM", f"azure:{resource_group}/{name}", "FAIL", audit_error(e))
        raise operation_error(logger, "resize Azure VM", e)


@router.post("/vms/{resource_group}/{name}/snapshot")
async def snapshot_vm(resource_group: str, name: str, user: dict = Depends(require_role("admin", "engineer"))):
    snap_name = f"{name}-snapshot-auto"
    try:
        result = await azure_snapshot_vm(resource_group, name, snap_name)
        await log_activity(user["username"], "SNAPSHOT_VM", f"azure:{resource_group}/{name}", "OK", snap_name)
        return result
    except Exception as e:
        await log_activity(user["username"], "SNAPSHOT_VM", f"azure:{resource_group}/{name}", "FAIL", audit_error(e))
        raise operation_error(logger, "snapshot Azure VM", e)


@router.post("/disks/{resource_group}/{disk_name}/expand")
async def expand_disk(resource_group: str, disk_name: str, body: AzureDiskExpandRequest,
                       user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await azure_expand_disk(resource_group, disk_name, body.size_gb)
        await log_activity(user["username"], "EXPAND_DISK", f"azure:{resource_group}/{disk_name}", "OK", f"{body.size_gb}GB")
        return result
    except Exception as e:
        await log_activity(user["username"], "EXPAND_DISK", f"azure:{resource_group}/{disk_name}", "FAIL", audit_error(e))
        raise operation_error(logger, "expand Azure disk", e)
