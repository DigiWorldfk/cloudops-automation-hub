import docker
from typing import List, Optional
import logging

logger = logging.getLogger(__name__)


def _client() -> docker.DockerClient:
    return docker.from_env()


def docker_list_containers(all_containers: bool = True) -> List[dict]:
    client = _client()
    containers = client.containers.list(all=all_containers)
    return [
        {
            "id":      c.short_id,
            "name":    c.name,
            "image":   c.image.tags[0] if c.image.tags else c.image.short_id,
            "status":  c.status,
            "ports":   c.ports,
            "created": str(c.attrs.get("Created", "")),
        }
        for c in containers
    ]


def docker_start_container(container_id: str) -> dict:
    client = _client()
    c = client.containers.get(container_id)
    c.start()
    return {"id": c.short_id, "name": c.name, "status": "started"}


def docker_stop_container(container_id: str) -> dict:
    client = _client()
    c = client.containers.get(container_id)
    c.stop()
    return {"id": c.short_id, "name": c.name, "status": "stopped"}


def docker_restart_container(container_id: str) -> dict:
    client = _client()
    c = client.containers.get(container_id)
    c.restart()
    return {"id": c.short_id, "name": c.name, "status": "restarted"}


def docker_remove_container(container_id: str) -> dict:
    client = _client()
    c = client.containers.get(container_id)
    c.remove()
    return {"id": container_id, "status": "removed"}


def docker_get_logs(container_id: str, tail: int = 100) -> str:
    client = _client()
    c = client.containers.get(container_id)
    return c.logs(tail=tail, timestamps=True).decode("utf-8", errors="replace")


def docker_list_images() -> List[dict]:
    client = _client()
    images = client.images.list()
    return [
        {
            "id":      img.short_id,
            "tags":    img.tags,
            "size":    img.attrs.get("Size", 0),
            "created": img.attrs.get("Created", ""),
        }
        for img in images
    ]


def docker_pull_image(image: str) -> dict:
    client = _client()
    img = client.images.pull(image)
    return {"status": "pulled", "tags": img.tags, "id": img.short_id}
