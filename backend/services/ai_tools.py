"""
AI Agent Tool Registry
======================
Each entry in TOOL_REGISTRY maps a tool name to:
  - schema    : OpenAI function-calling parameters schema
  - description: human/model-readable description
  - risk_tier : 'green' (auto-execute) | 'amber' (requires approval) | 'red' (requires approval)
  - executor  : async callable(args: dict) -> any

OPENAI_TOOLS is the ready-to-use list to pass to the OpenAI API.
"""

from typing import Any
import json

# ── service imports ────────────────────────────────────────────────────────────
from services.docker_client import (
    docker_list_containers, docker_get_logs,
    docker_start_container, docker_stop_container, docker_restart_container,
)
from services.k8s_client import (
    k8s_list_namespaces, k8s_list_pods, k8s_pod_logs,
    k8s_list_deployments, k8s_scale_deployment,
    k8s_get_cluster_info, k8s_cordon_node, k8s_uncordon_node, k8s_drain_node,
    helm_list_releases,
)
from services.azure_client import azure_list_vms, azure_start_vm, azure_stop_vm
from services.aws_client import aws_list_instances, aws_start_instance, aws_stop_instance, aws_get_costs
from db.database import get_activity

GREEN = "green"
AMBER = "amber"
RED   = "red"


# ── executors ─────────────────────────────────────────────────────────────────

async def _exec_list_docker_containers(args: dict) -> Any:
    return docker_list_containers(all_containers=args.get("all", True))

async def _exec_get_container_logs(args: dict) -> Any:
    return docker_get_logs(args["container_id"], tail=args.get("tail", 100))

async def _exec_start_container(args: dict) -> Any:
    return docker_start_container(args["container_id"])

async def _exec_stop_container(args: dict) -> Any:
    return docker_stop_container(args["container_id"])

async def _exec_restart_container(args: dict) -> Any:
    return docker_restart_container(args["container_id"])

async def _exec_list_k8s_namespaces(args: dict) -> Any:
    return await k8s_list_namespaces()

async def _exec_list_k8s_pods(args: dict) -> Any:
    return await k8s_list_pods(namespace=args.get("namespace", "default"))

async def _exec_get_pod_logs(args: dict) -> Any:
    return await k8s_pod_logs(
        namespace=args.get("namespace", "default"),
        pod_name=args["pod_name"],
        tail=args.get("tail", 100),
    )

async def _exec_list_k8s_deployments(args: dict) -> Any:
    return await k8s_list_deployments(namespace=args.get("namespace", "default"))

async def _exec_scale_deployment(args: dict) -> Any:
    return await k8s_scale_deployment(
        namespace=args.get("namespace", "default"),
        name=args["name"],
        replicas=args["replicas"],
    )

async def _exec_get_cluster_info(args: dict) -> Any:
    return await k8s_get_cluster_info()

async def _exec_cordon_node(args: dict) -> Any:
    return await k8s_cordon_node(args["node_name"])

async def _exec_uncordon_node(args: dict) -> Any:
    return await k8s_uncordon_node(args["node_name"])

async def _exec_drain_node(args: dict) -> Any:
    return await k8s_drain_node(args["node_name"])

async def _exec_list_helm_releases(args: dict) -> Any:
    return await helm_list_releases(namespace=args.get("namespace", "default"))

async def _exec_list_azure_vms(args: dict) -> Any:
    return await azure_list_vms()

async def _exec_start_azure_vm(args: dict) -> Any:
    return await azure_start_vm(args["resource_group"], args["vm_name"])

async def _exec_stop_azure_vm(args: dict) -> Any:
    return await azure_stop_vm(args["resource_group"], args["vm_name"])

async def _exec_list_aws_instances(args: dict) -> Any:
    return await aws_list_instances()

async def _exec_start_aws_instance(args: dict) -> Any:
    return await aws_start_instance(args["instance_id"])

async def _exec_stop_aws_instance(args: dict) -> Any:
    return await aws_stop_instance(args["instance_id"])

async def _exec_get_aws_costs(args: dict) -> Any:
    return await aws_get_costs(period_days=args.get("period_days", 30))

async def _exec_get_activity_log(args: dict) -> Any:
    return await get_activity(limit=args.get("limit", 20), offset=0)


# ── tool registry ─────────────────────────────────────────────────────────────

TOOL_REGISTRY: dict[str, dict] = {
    "list_docker_containers": {
        "description": "List all Docker containers with their status, image, and ports.",
        "parameters": {
            "type": "object",
            "properties": {
                "all": {"type": "boolean", "description": "Include stopped containers (default true)."},
            },
        },
        "risk_tier": GREEN,
        "executor": _exec_list_docker_containers,
    },
    "get_container_logs": {
        "description": "Get the recent logs from a Docker container.",
        "parameters": {
            "type": "object",
            "properties": {
                "container_id": {"type": "string", "description": "Container ID or name."},
                "tail": {"type": "integer", "description": "Number of lines from the end (default 100)."},
            },
            "required": ["container_id"],
        },
        "risk_tier": GREEN,
        "executor": _exec_get_container_logs,
    },
    "start_container": {
        "description": "Start a stopped Docker container.",
        "parameters": {
            "type": "object",
            "properties": {
                "container_id": {"type": "string", "description": "Container ID or name."},
            },
            "required": ["container_id"],
        },
        "risk_tier": AMBER,
        "executor": _exec_start_container,
    },
    "stop_container": {
        "description": "Stop a running Docker container.",
        "parameters": {
            "type": "object",
            "properties": {
                "container_id": {"type": "string", "description": "Container ID or name."},
            },
            "required": ["container_id"],
        },
        "risk_tier": AMBER,
        "executor": _exec_stop_container,
    },
    "restart_container": {
        "description": "Restart a Docker container.",
        "parameters": {
            "type": "object",
            "properties": {
                "container_id": {"type": "string", "description": "Container ID or name."},
            },
            "required": ["container_id"],
        },
        "risk_tier": AMBER,
        "executor": _exec_restart_container,
    },
    "list_k8s_namespaces": {
        "description": "List all Kubernetes namespaces.",
        "parameters": {"type": "object", "properties": {}},
        "risk_tier": GREEN,
        "executor": _exec_list_k8s_namespaces,
    },
    "list_k8s_pods": {
        "description": "List all pods in a Kubernetes namespace.",
        "parameters": {
            "type": "object",
            "properties": {
                "namespace": {"type": "string", "description": "Namespace name (default 'default')."},
            },
        },
        "risk_tier": GREEN,
        "executor": _exec_list_k8s_pods,
    },
    "get_pod_logs": {
        "description": "Get logs from a Kubernetes pod.",
        "parameters": {
            "type": "object",
            "properties": {
                "namespace": {"type": "string"},
                "pod_name":  {"type": "string"},
                "tail":      {"type": "integer", "description": "Lines from end (default 100)."},
            },
            "required": ["pod_name"],
        },
        "risk_tier": GREEN,
        "executor": _exec_get_pod_logs,
    },
    "list_k8s_deployments": {
        "description": "List Kubernetes deployments and their replica counts.",
        "parameters": {
            "type": "object",
            "properties": {
                "namespace": {"type": "string", "description": "Namespace (default 'default')."},
            },
        },
        "risk_tier": GREEN,
        "executor": _exec_list_k8s_deployments,
    },
    "scale_deployment": {
        "description": "Scale a Kubernetes deployment to a target replica count.",
        "parameters": {
            "type": "object",
            "properties": {
                "namespace": {"type": "string"},
                "name":      {"type": "string", "description": "Deployment name."},
                "replicas":  {"type": "integer", "minimum": 0},
            },
            "required": ["name", "replicas"],
        },
        "risk_tier": AMBER,
        "executor": _exec_scale_deployment,
    },
    "get_cluster_info": {
        "description": "Get Kubernetes cluster server version and node information.",
        "parameters": {"type": "object", "properties": {}},
        "risk_tier": GREEN,
        "executor": _exec_get_cluster_info,
    },
    "cordon_node": {
        "description": "Cordon a Kubernetes node so no new pods are scheduled on it.",
        "parameters": {
            "type": "object",
            "properties": {
                "node_name": {"type": "string"},
            },
            "required": ["node_name"],
        },
        "risk_tier": AMBER,
        "executor": _exec_cordon_node,
    },
    "uncordon_node": {
        "description": "Uncordon a Kubernetes node to re-enable scheduling.",
        "parameters": {
            "type": "object",
            "properties": {
                "node_name": {"type": "string"},
            },
            "required": ["node_name"],
        },
        "risk_tier": AMBER,
        "executor": _exec_uncordon_node,
    },
    "drain_node": {
        "description": "Drain all pods from a Kubernetes node before maintenance.",
        "parameters": {
            "type": "object",
            "properties": {
                "node_name": {"type": "string"},
            },
            "required": ["node_name"],
        },
        "risk_tier": RED,
        "executor": _exec_drain_node,
    },
    "list_helm_releases": {
        "description": "List Helm releases in a namespace.",
        "parameters": {
            "type": "object",
            "properties": {
                "namespace": {"type": "string", "description": "Namespace (default 'default')."},
            },
        },
        "risk_tier": GREEN,
        "executor": _exec_list_helm_releases,
    },
    "list_azure_vms": {
        "description": "List all Azure VMs in the configured subscription with status and IPs.",
        "parameters": {"type": "object", "properties": {}},
        "risk_tier": GREEN,
        "executor": _exec_list_azure_vms,
    },
    "start_azure_vm": {
        "description": "Start a stopped Azure VM.",
        "parameters": {
            "type": "object",
            "properties": {
                "resource_group": {"type": "string"},
                "vm_name":        {"type": "string"},
            },
            "required": ["resource_group", "vm_name"],
        },
        "risk_tier": AMBER,
        "executor": _exec_start_azure_vm,
    },
    "stop_azure_vm": {
        "description": "Stop (deallocate) an Azure VM.",
        "parameters": {
            "type": "object",
            "properties": {
                "resource_group": {"type": "string"},
                "vm_name":        {"type": "string"},
            },
            "required": ["resource_group", "vm_name"],
        },
        "risk_tier": AMBER,
        "executor": _exec_stop_azure_vm,
    },
    "list_aws_instances": {
        "description": "List all AWS EC2 instances with type, state, AZ, and IP addresses.",
        "parameters": {"type": "object", "properties": {}},
        "risk_tier": GREEN,
        "executor": _exec_list_aws_instances,
    },
    "start_aws_instance": {
        "description": "Start a stopped AWS EC2 instance.",
        "parameters": {
            "type": "object",
            "properties": {
                "instance_id": {"type": "string"},
            },
            "required": ["instance_id"],
        },
        "risk_tier": AMBER,
        "executor": _exec_start_aws_instance,
    },
    "stop_aws_instance": {
        "description": "Stop a running AWS EC2 instance.",
        "parameters": {
            "type": "object",
            "properties": {
                "instance_id": {"type": "string"},
            },
            "required": ["instance_id"],
        },
        "risk_tier": AMBER,
        "executor": _exec_stop_aws_instance,
    },
    "get_aws_costs": {
        "description": "Get AWS cost breakdown for the past N days.",
        "parameters": {
            "type": "object",
            "properties": {
                "period_days": {"type": "integer", "description": "Number of days (default 30)."},
            },
        },
        "risk_tier": GREEN,
        "executor": _exec_get_aws_costs,
    },
    "get_activity_log": {
        "description": "Get the recent CloudOps audit log entries.",
        "parameters": {
            "type": "object",
            "properties": {
                "limit": {"type": "integer", "description": "Max entries to return (default 20)."},
            },
        },
        "risk_tier": GREEN,
        "executor": _exec_get_activity_log,
    },
}

# ── OpenAI-compatible tool list ────────────────────────────────────────────────

OPENAI_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": name,
            "description": meta["description"],
            "parameters": meta["parameters"],
        },
    }
    for name, meta in TOOL_REGISTRY.items()
]


async def execute_tool(name: str, args: dict) -> Any:
    """Execute a registered tool by name and return its result as a JSON-serialisable value."""
    entry = TOOL_REGISTRY.get(name)
    if not entry:
        raise ValueError(f"Unknown tool: {name}")
    result = await entry["executor"](args)
    return result


def tool_risk_tier(name: str) -> str:
    entry = TOOL_REGISTRY.get(name)
    return entry["risk_tier"] if entry else GREEN
