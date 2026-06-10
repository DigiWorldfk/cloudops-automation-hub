from fastapi import APIRouter, Depends
from auth.dependencies import get_current_user
from services.azure_client import azure_list_vms
from services.aws_client import aws_list_instances
from services.docker_client import docker_list_containers
from db.database import get_activity
import logging

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get("/summary")
async def summary(_user: dict = Depends(get_current_user)):
    results = {
        "azure_vms":          {"count": 0, "error": None},
        "aws_instances":      {"count": 0, "error": None},
        "docker_containers":  {"count": 0, "running": 0, "error": None},
        "recent_activity":    [],
    }

    try:
        vms = await azure_list_vms()
        results["azure_vms"]["count"] = len(vms)
    except Exception as e:
        results["azure_vms"]["error"] = str(e)

    try:
        instances = await aws_list_instances()
        results["aws_instances"]["count"] = len(instances)
    except Exception as e:
        results["aws_instances"]["error"] = str(e)

    try:
        containers = docker_list_containers(all_containers=True)
        results["docker_containers"]["count"]  = len(containers)
        results["docker_containers"]["running"] = sum(1 for c in containers if c.get("status") == "running")
    except Exception as e:
        results["docker_containers"]["error"] = str(e)

    try:
        results["recent_activity"] = await get_activity(limit=5, offset=0)
    except Exception as e:
        logger.warning("Could not fetch recent activity: %s", e)

    return results
