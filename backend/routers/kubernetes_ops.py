from fastapi import APIRouter, Depends, HTTPException, Query
from auth.dependencies import get_current_user, require_role
from db.database import log_activity
from models.schemas import (
    K8sScaleRequest, K8sResourcePatchRequest, K8sNamespaceCreateRequest,
    HelmInstallRequest, HelmUpgradeRequest, HelmRollbackRequest,
)
from services.k8s_client import (
    k8s_list_namespaces, k8s_create_namespace, k8s_delete_namespace,
    k8s_list_pods, k8s_pod_logs, k8s_list_deployments, k8s_scale_deployment,
    k8s_patch_deployment_resources,
    helm_list_releases, helm_install, helm_upgrade, helm_rollback,
)

router = APIRouter()


@router.get("/namespaces")
async def list_namespaces(user: dict = Depends(get_current_user)):
    try:
        return await k8s_list_namespaces()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/namespaces")
async def create_namespace(body: K8sNamespaceCreateRequest, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await k8s_create_namespace(body.name)
        await log_activity(user["username"], "CREATE_NAMESPACE", f"k8s:{body.name}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "CREATE_NAMESPACE", f"k8s:{body.name}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/namespaces/{name}")
async def delete_namespace(name: str, user: dict = Depends(require_role("admin"))):
    try:
        result = await k8s_delete_namespace(name)
        await log_activity(user["username"], "DELETE_NAMESPACE", f"k8s:{name}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "DELETE_NAMESPACE", f"k8s:{name}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/pods")
async def list_pods(namespace: str = Query("default"), user: dict = Depends(get_current_user)):
    try:
        return await k8s_list_pods(namespace)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/pods/{namespace}/{pod_name}/logs")
async def pod_logs(namespace: str, pod_name: str,
                   tail: int = Query(100, ge=1, le=5000),
                   user: dict = Depends(get_current_user)):
    try:
        logs = await k8s_pod_logs(namespace, pod_name, tail)
        return {"logs": logs}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/deployments")
async def list_deployments(namespace: str = Query("default"), user: dict = Depends(get_current_user)):
    try:
        return await k8s_list_deployments(namespace)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/deployments/{namespace}/{name}/scale")
async def scale_deployment(namespace: str, name: str, body: K8sScaleRequest,
                            user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await k8s_scale_deployment(namespace, name, body.replicas)
        await log_activity(user["username"], "SCALE_DEPLOYMENT", f"k8s:{namespace}/{name}", "OK", f"replicas={body.replicas}")
        return result
    except Exception as e:
        await log_activity(user["username"], "SCALE_DEPLOYMENT", f"k8s:{namespace}/{name}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.patch("/deployments/{namespace}/{name}/resources")
async def patch_deployment_resources(namespace: str, name: str, body: K8sResourcePatchRequest,
                                      user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await k8s_patch_deployment_resources(
            namespace, name,
            body.cpu_request, body.cpu_limit,
            body.memory_request, body.memory_limit,
        )
        await log_activity(user["username"], "PATCH_RESOURCES", f"k8s:{namespace}/{name}", "OK",
                           f"cpu={body.cpu_limit} mem={body.memory_limit}")
        return result
    except Exception as e:
        await log_activity(user["username"], "PATCH_RESOURCES", f"k8s:{namespace}/{name}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/helm/releases")
async def list_helm_releases(namespace: str = Query("default"), user: dict = Depends(get_current_user)):
    try:
        return await helm_list_releases(namespace)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/helm/install")
async def install_chart(body: HelmInstallRequest, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await helm_install(body.chart, body.release, body.namespace, body.values_yaml, body.repo_url)
        await log_activity(user["username"], "HELM_INSTALL", f"k8s:{body.namespace}/{body.release}", "OK", body.chart)
        return result
    except Exception as e:
        await log_activity(user["username"], "HELM_INSTALL", f"k8s:{body.namespace}/{body.release}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/helm/upgrade")
async def upgrade_chart(body: HelmUpgradeRequest, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await helm_upgrade(body.chart, body.release, body.namespace, body.values_yaml)
        await log_activity(user["username"], "HELM_UPGRADE", f"k8s:{body.namespace}/{body.release}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "HELM_UPGRADE", f"k8s:{body.namespace}/{body.release}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/helm/rollback")
async def rollback_chart(body: HelmRollbackRequest, user: dict = Depends(require_role("admin", "engineer"))):
    try:
        result = await helm_rollback(body.release, body.namespace, body.revision)
        await log_activity(user["username"], "HELM_ROLLBACK", f"k8s:{body.namespace}/{body.release}", "OK")
        return result
    except Exception as e:
        await log_activity(user["username"], "HELM_ROLLBACK", f"k8s:{body.namespace}/{body.release}", "FAIL", str(e))
        raise HTTPException(status_code=500, detail=str(e))
