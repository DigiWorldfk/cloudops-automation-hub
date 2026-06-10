from pydantic import BaseModel, Field
from typing import Optional, List, Any
from datetime import datetime
from enum import Enum


# ── Auth ──────────────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    username: str
    password: str
    totp_code: str = Field(..., min_length=6, max_length=6)

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"

class UserInfo(BaseModel):
    username: str
    role: str


# ── Activity ──────────────────────────────────────────────────────────────────

class ActivityEntry(BaseModel):
    id: int
    timestamp: datetime
    user: str
    action: str
    resource: str
    status: str
    detail: Optional[str] = None


# ── Azure ─────────────────────────────────────────────────────────────────────

class AzureVMCreateRequest(BaseModel):
    name: str
    resource_group: str
    location: str = "eastus"
    vm_size: str = "Standard_B2s"
    image: str = "UbuntuLTS"
    admin_username: str
    admin_password: str = Field(..., min_length=12)

class AzureVMResizeRequest(BaseModel):
    vm_size: str

class AzureDiskExpandRequest(BaseModel):
    size_gb: int = Field(..., gt=0)

class AzureVMInfo(BaseModel):
    name: str
    resource_group: str
    location: str
    vm_size: str
    status: str
    os_type: Optional[str] = None
    private_ip: Optional[str] = None
    public_ip: Optional[str] = None


# ── AWS ───────────────────────────────────────────────────────────────────────

class AWSInstanceCreateRequest(BaseModel):
    ami_id: str
    instance_type: str = "t3.micro"
    subnet_id: str
    security_group_ids: List[str]
    key_name: Optional[str] = None
    name_tag: str

class AWSInstanceResizeRequest(BaseModel):
    instance_type: str

class AWSVolumeCreateRequest(BaseModel):
    instance_id: str
    size_gb: int = Field(..., gt=0, le=16384)
    volume_type: str = "gp3"
    availability_zone: str

class AWSInstanceInfo(BaseModel):
    instance_id: str
    instance_type: str
    state: str
    availability_zone: str
    private_ip: Optional[str] = None
    public_ip: Optional[str] = None
    name: Optional[str] = None
    launch_time: Optional[datetime] = None


# ── Docker ────────────────────────────────────────────────────────────────────

class DockerContainerInfo(BaseModel):
    id: str
    name: str
    image: str
    status: str
    ports: Optional[Any] = None
    created: Optional[str] = None

class DockerImageInfo(BaseModel):
    id: str
    tags: List[str]
    size: int
    created: Optional[str] = None

class DockerPullRequest(BaseModel):
    image: str


# ── Kubernetes ────────────────────────────────────────────────────────────────

class K8sScaleRequest(BaseModel):
    replicas: int = Field(..., ge=0, le=100)

class K8sNamespaceCreateRequest(BaseModel):
    name: str

class HelmInstallRequest(BaseModel):
    chart: str
    release: str
    namespace: str = "default"
    values_yaml: Optional[str] = None
    repo_url: Optional[str] = None

class HelmUpgradeRequest(BaseModel):
    chart: str
    release: str
    namespace: str = "default"
    values_yaml: Optional[str] = None

class HelmRollbackRequest(BaseModel):
    release: str
    namespace: str = "default"
    revision: Optional[int] = None


# ── Terraform ─────────────────────────────────────────────────────────────────

class TerraformWorkspaceRequest(BaseModel):
    workspace: str

class TerraformApplyRequest(BaseModel):
    workspace: str
    confirm: bool = False

class TerraformDestroyRequest(BaseModel):
    workspace: str
    confirm: bool = False
    destroy: bool = False
