# ⚙️ CloudOps Automation Hub

![Python](https://img.shields.io/badge/Python-3.12-3776AB?style=flat&logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-0.111-009688?style=flat&logo=fastapi&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)
![Azure](https://img.shields.io/badge/Azure-%230072C6.svg?style=flat&logo=microsoftazure&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=flat&logo=amazon-aws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-%23326ce5.svg?style=flat&logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-%235835CC.svg?style=flat&logo=terraform&logoColor=white)
![nginx](https://img.shields.io/badge/nginx-%23009639.svg?style=flat&logo=nginx&logoColor=white)

A **self-service Platform Engineering Portal** for day-to-day CloudOps work across AWS, Azure, Docker, Kubernetes, and Terraform — all from a single hardened web dashboard.

> **Flagship project demonstrating:** Platform Engineering · Cloud Automation · DevOps Tooling · FastAPI · Infrastructure as Code · Kubernetes Operations · Security-First Design

---

## Architecture

```
Browser
   │
   ▼
nginx (port 80) ─── WAF rules: SQLi, XSS, path traversal, command injection
   │                Rate limiting: 5r/m login, 30r/s API
   ├── /                → frontend (static HTML/CSS/JS)
   └── /api/*           → FastAPI backend (uvicorn, port 8000)
                                │
                ┌───────────────┼───────────────────┬────────────────┐
                ▼               ▼                   ▼                ▼
         azure-mgmt-*        boto3           docker SDK         kubernetes
         DefaultAzure        IAM creds      /var/run/docker.sock  KUBECONFIG
         Credential          env vars                              mount
                │
         subprocess → terraform binary
```

All services run in Docker Compose with `read_only: true`, `cap_drop: ALL`, and `no-new-privileges: true`. Secrets are injected at runtime via `.env` — never committed.

---

## Features

### Phase 1 — MVP ✅
| Feature | Details |
|---|---|
| JWT + TOTP 2FA Login | bcrypt password, TOTP via pyotp, `httpOnly SameSite=Strict` cookies |
| Dashboard | Live summary cards: Azure VM count, EC2 count, container count, recent activity |
| Docker Operations | List, start, stop, restart, remove containers; pull images; tail logs |
| VM Inventory | Azure and AWS instance listing with status |
| Terraform Runner | Init, streaming Plan (SSE), Apply, Destroy with double-confirm |
| Activity Log | Every mutating API call logged to SQLite with user/action/resource/status |
| nginx WAF | Blocks SQLi, XSS, path traversal, command injection, known scanner UAs |

### Phase 2 — Cloud Automation ✅
| Feature | Details |
|---|---|
| Azure VM CRUD | Create, Delete, Resize, Start, Stop, Snapshot, Disk Expand |
| AWS EC2 CRUD | Launch, Terminate, Resize (stop→modify→start), Start, Stop, Snapshot, Attach EBS |
| Patch Management | AWS SSM `AWS-RunPatchBaseline`, Azure `install_patches()` |
| Cost Dashboard | AWS Cost Explorer API |

### Phase 3 — Kubernetes ✅
| Feature | Details |
|---|---|
| Namespace management | List, Create, Delete |
| Pod operations | List pods, tail logs |
| Deployment scaling | Scale replicas via `patch_namespaced_deployment_scale` |
| Helm management | Install, Upgrade, Rollback, List releases |

---

## Quick Start

### Prerequisites
- Docker + Docker Compose v2
- An Azure Service Principal (for Azure operations)
- AWS IAM credentials (for AWS operations)
- Authenticator app (Google Authenticator, Authy, 1Password)

### 1. Clone and configure

```bash
git clone https://github.com/DigiWorldfk/cloudops-automation-hub.git
cd cloudops-automation-hub
cp .env.example .env
```

### 2. Generate secrets

```bash
# JWT secret (64+ chars)
python3 -c "import secrets; print(secrets.token_hex(64))"

# Admin password hash (bcrypt, rounds=12)
python3 -c "from passlib.context import CryptContext; print(CryptContext(schemes=['bcrypt']).hash('YourPasswordHere'))"

# TOTP secret — scan the QR code below into your authenticator
python3 -c "import pyotp, qrcode; s = pyotp.random_base32(); print('TOTP_SECRET =', s); qrcode.make(pyotp.TOTP(s).provisioning_uri('admin', issuer_name='CloudOps Hub')).save('/tmp/totp.png')"
# open /tmp/totp.png and scan with your authenticator app
```

Edit `.env` and fill in all values.

### 3. Add a Terraform workspace (optional)

```bash
mkdir -p terraform-workspaces/my-infra
# copy your .tf files into terraform-workspaces/my-infra/
```

### 4. Start

```bash
docker compose up -d
```

Open http://localhost — log in with your admin credentials + TOTP code.

---

## Security Model

| Layer | Control |
|---|---|
| Authentication | bcrypt (rounds=12) + TOTP 2FA required on every login |
| Tokens | JWT in `httpOnly SameSite=Strict` cookies; never accessible to JavaScript |
| Transport | nginx TLS termination (add cert for production) |
| WAF | nginx `map` blocks SQLi, XSS, LFI, path traversal, command injection at the edge |
| Rate limiting | 5r/m on `/api/auth/login`; 30r/s on all other API endpoints |
| Containers | `read_only: true`, `cap_drop: ALL`, `no-new-privileges: true` |
| Secrets | All credentials in `.env` (gitignored); never in source control |
| Secret scanning | gitleaks runs in CI on every push |
| RBAC | JWT payload `role` field; `require_role()` dependency enforced per endpoint |
| Audit log | Every mutating operation logged to SQLite: user, action, resource, status, timestamp |

---

## Environment Variables

See [`.env.example`](.env.example) for the complete list with generation instructions.

| Variable | Required | Description |
|---|---|---|
| `JWT_SECRET` | ✅ | 64+ char random string |
| `ADMIN_USER` | ✅ | Login username |
| `ADMIN_PASS_HASH` | ✅ | bcrypt hash of admin password |
| `TOTP_SECRET` | ✅ | Base32 TOTP seed |
| `AZURE_SUBSCRIPTION_ID` | Azure ops | Azure subscription ID |
| `AZURE_TENANT_ID` | Azure ops | Service Principal tenant |
| `AZURE_CLIENT_ID` | Azure ops | Service Principal client ID |
| `AZURE_CLIENT_SECRET` | Azure ops | Service Principal secret |
| `AWS_ACCESS_KEY_ID` | AWS ops | IAM access key |
| `AWS_SECRET_ACCESS_KEY` | AWS ops | IAM secret key |
| `AWS_DEFAULT_REGION` | AWS ops | Default region |

---

## API Reference

FastAPI generates interactive docs automatically.  
After `docker compose up`, open: **http://localhost/api/docs**

| Prefix | Description |
|---|---|
| `/api/auth` | Login, logout, refresh, me |
| `/api/dashboard` | Summary overview |
| `/api/azure` | Azure VM CRUD + disk operations |
| `/api/aws` | AWS EC2 CRUD + patching + costs |
| `/api/docker` | Container and image operations |
| `/api/k8s` | Pods, namespaces, deployments, Helm |
| `/api/terraform` | Init, plan (SSE stream), apply, destroy |
| `/api/activity` | Paginated audit log |

---

## Project Structure

```
cloudops-automation-hub/
├── .github/workflows/ci.yml      # Lint, secret scan, Docker build test
├── .gitleaks.toml                 # Custom secret detection rules
├── .env.example                   # All required variables + generation commands
├── docker-compose.yml             # nginx + backend, hardened containers
├── nginx/
│   ├── Dockerfile
│   └── nginx.conf                 # WAF + rate limiting + reverse proxy
├── backend/
│   ├── Dockerfile                 # Python 3.12 + Terraform + kubectl + Helm
│   ├── requirements.txt
│   ├── main.py                    # FastAPI app, router mounts, startup
│   ├── routers/                   # auth, dashboard, azure, aws, docker_ops,
│   │                              # kubernetes_ops, terraform, activity
│   ├── services/                  # azure_client, aws_client, docker_client,
│   │                              # k8s_client, terraform_runner
│   ├── auth/                      # jwt_handler.py, dependencies.py
│   ├── db/database.py             # aiosqlite activity log
│   └── models/schemas.py          # Pydantic request/response models
└── frontend/
    ├── style.css                  # Dark theme (#0a0f1a / #3b82f6)
    ├── shared.js                  # Auth guard, sidebar, API helper, badges
    ├── login.html                 # TOTP 2FA login form
    ├── dashboard.html             # Overview cards + recent activity
    ├── azure.html                 # Azure VM management
    ├── aws.html                   # AWS EC2 management
    ├── docker.html                # Container + image management
    ├── kubernetes.html            # Pods, deployments, Helm, namespaces
    ├── terraform.html             # Streaming plan/apply/destroy terminal
    └── activity.html              # Paginated searchable audit log
```

---

## Roadmap

- **Phase 4**: RBAC approval workflow (engineer creates request → admin approves → action executes), cost dashboard with Chart.js
- **Phase 5**: AI incident recommendations (OpenAI/Azure OpenAI), auto-remediation suggestions, ChatOps assistant
- **Production hardening**: HTTPS/TLS, multiple user accounts, PostgreSQL swap, Prometheus metrics endpoint

---

## Related Projects

- [Azure AKS Enterprise Platform](../azure-aks-enterprise-platform/) — 9-module Terraform platform
- [AWS EKS Enterprise Platform](../aws-eks-enterprise-platform/) — 14-module Terraform platform
- [DigiWorld Platform](../projects/digiworld-platform/) — Docker-based portfolio platform (JWT + TOTP 2FA origin)
