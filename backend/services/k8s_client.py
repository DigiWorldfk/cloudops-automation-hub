import os
import asyncio
import subprocess
from kubernetes import client, config
from kubernetes.client.rest import ApiException
from typing import Optional
import logging
import yaml

logger = logging.getLogger(__name__)


def _load_kube_config():
    kubeconfig = os.getenv("KUBECONFIG", "")
    if kubeconfig:
        config.load_kube_config(config_file=kubeconfig)
    else:
        try:
            config.load_incluster_config()
        except Exception:
            config.load_kube_config()


async def k8s_list_namespaces() -> list:
    def _list():
        _load_kube_config()
        v1 = client.CoreV1Api()
        ns_list = v1.list_namespace()
        return [
            {"name": ns.metadata.name, "status": ns.status.phase}
            for ns in ns_list.items
        ]
    return await asyncio.to_thread(_list)


async def k8s_create_namespace(name: str) -> dict:
    def _create():
        _load_kube_config()
        v1 = client.CoreV1Api()
        ns = client.V1Namespace(metadata=client.V1ObjectMeta(name=name))
        v1.create_namespace(ns)
        return {"status": "created", "namespace": name}
    return await asyncio.to_thread(_create)


async def k8s_delete_namespace(name: str) -> dict:
    def _delete():
        _load_kube_config()
        v1 = client.CoreV1Api()
        v1.delete_namespace(name)
        return {"status": "deleted", "namespace": name}
    return await asyncio.to_thread(_delete)


async def k8s_list_pods(namespace: str = "default") -> list:
    def _list():
        _load_kube_config()
        v1 = client.CoreV1Api()
        pods = v1.list_namespaced_pod(namespace=namespace)
        return [
            {
                "name":      p.metadata.name,
                "namespace": p.metadata.namespace,
                "status":    p.status.phase,
                "node":      p.spec.node_name,
                "ready":     all(
                    cs.ready for cs in (p.status.container_statuses or [])
                ),
            }
            for p in pods.items
        ]
    return await asyncio.to_thread(_list)


async def k8s_pod_logs(namespace: str, pod_name: str, tail: int = 100) -> str:
    def _logs():
        _load_kube_config()
        v1 = client.CoreV1Api()
        return v1.read_namespaced_pod_log(name=pod_name, namespace=namespace, tail_lines=tail)
    return await asyncio.to_thread(_logs)


async def k8s_list_deployments(namespace: str = "default") -> list:
    def _list():
        _load_kube_config()
        apps = client.AppsV1Api()
        deps = apps.list_namespaced_deployment(namespace=namespace)
        return [
            {
                "name":      d.metadata.name,
                "namespace": d.metadata.namespace,
                "replicas":  d.spec.replicas,
                "ready":     d.status.ready_replicas,
                "image":     d.spec.template.spec.containers[0].image if d.spec.template.spec.containers else None,
            }
            for d in deps.items
        ]
    return await asyncio.to_thread(_list)


async def k8s_scale_deployment(namespace: str, name: str, replicas: int) -> dict:
    def _scale():
        _load_kube_config()
        apps = client.AppsV1Api()
        body = {"spec": {"replicas": replicas}}
        apps.patch_namespaced_deployment_scale(name=name, namespace=namespace, body=body)
        return {"status": "scaled", "deployment": name, "replicas": replicas}
    return await asyncio.to_thread(_scale)


async def helm_list_releases(namespace: str = "default") -> list:
    def _list():
        result = subprocess.run(
            ["helm", "list", "-n", namespace, "--output", "json"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr)
        import json
        return json.loads(result.stdout or "[]")
    return await asyncio.to_thread(_list)


async def helm_install(chart: str, release: str, namespace: str,
                        values_yaml: Optional[str], repo_url: Optional[str]) -> dict:
    def _install():
        cmd = ["helm", "install", release, chart, "-n", namespace, "--create-namespace"]
        if repo_url:
            cmd += ["--repo", repo_url]
        if values_yaml:
            import tempfile, os
            with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as f:
                f.write(values_yaml)
                cmd += ["-f", f.name]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        if result.returncode != 0:
            raise RuntimeError(result.stderr)
        return {"status": "installed", "release": release, "chart": chart}
    return await asyncio.to_thread(_install)


async def helm_upgrade(chart: str, release: str, namespace: str, values_yaml: Optional[str]) -> dict:
    def _upgrade():
        cmd = ["helm", "upgrade", release, chart, "-n", namespace]
        if values_yaml:
            import tempfile
            with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as f:
                f.write(values_yaml)
                cmd += ["-f", f.name]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        if result.returncode != 0:
            raise RuntimeError(result.stderr)
        return {"status": "upgraded", "release": release}
    return await asyncio.to_thread(_upgrade)


async def helm_rollback(release: str, namespace: str, revision: Optional[int]) -> dict:
    def _rollback():
        cmd = ["helm", "rollback", release]
        if revision:
            cmd.append(str(revision))
        cmd += ["-n", namespace]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            raise RuntimeError(result.stderr)
        return {"status": "rolled_back", "release": release}
    return await asyncio.to_thread(_rollback)
