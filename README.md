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

> **Flagship portfolio project demonstrating:** Platform Engineering · Cloud Automation · DevOps Tooling · FastAPI · Infrastructure as Code · Kubernetes Operations · Security-First Design

---

## ✨ Features

### 🔐 Authentication & Security
- **JWT + TOTP 2FA** login — bcrypt password hash (rounds=12) + pyotp time-based OTP
- `httpOnly SameSite=Strict` cookies — tokens never accessible to JavaScript
- **RBAC** — `admin`, `engineer`, `readonly` roles enforced per endpoint via FastAPI dependencies
- **nginx WAF** — blocks SQLi, XSS, path traversal, command injection, known scanner user-agents
- **Rate limiting** — 5 req/min on `/api/auth/login`, 30 req/s on all other API endpoints
- Hardened containers — `cap_drop: ALL`, `no-new-privileges: true`, read-only filesystem
- **gitleaks** secret scanning on every CI push

---

### 📊 Dashboard
Real-time infrastructure overview — all panels on a single page:

| Panel | What it shows |
|---|---|
| **Stat Cards** | Azure VM count, AWS EC2 count, container count (running/total), activity events |
| **Recent Activity** | Last 10 audit log entries with time, user, action, resource, status |
| **🐳 Docker Containers** | All containers with status, image, ports — Start / Stop / Restart controls |
| **☸️ Kubernetes Deployments** | Replicas (ready/desired), CPU & memory req→limit — Scale ➕➖ and ✏️ Resource edit |
| **☸️ Cluster & Nodes** | All nodes with role, version, ready state, schedulable, CPU/RAM capacity |

#### Dashboard Controls at a glance
| Control | Action |
|---|---|
| ▶ Start | Start a stopped Docker container |
| ⏹ Stop | Stop a running container |
| ↻ Restart | Restart a running container |
| ➕ / ➖ | Add or remove one Kubernetes replica |
| ✏️ Resources | Edit CPU request/limit and memory request/limit per deployment |
| Cordon | Mark a node unschedulable (new pods won't land on it) |
| Uncordon | Re-enable scheduling on a cordoned node |
| Drain | Evict all pods from a node before maintenance |
| ⬆ Upgrade Cluster | Select target version + node from dropdown — applies live or provides kind recreate command |

All action buttons show a **hover tooltip** with the target resource name.

---

### 🐳 Docker Operations (`/docker.html`)
- List all containers with status, image, ports, created time
- Start / Stop / Restart / Remove containers
- Tail container logs (up to 5000 lines)
- List images with size and tags
- Pull images from any registry

---

### 🔵 Azure VM Management (`/azure.html`)
- List all VMs across a subscription with status and IP addresses
- Create VM (size, resource group, region, VNet/subnet)
- Delete VM
- Start / Stop (deallocate) VM
- Resize VM (change SKU)
- Snapshot OS disk
- Expand data disk
- Run patch baseline via Azure Update Manager

---

### 🟠 AWS EC2 Management (`/aws.html`)
- List EC2 instances with type, state, AZ, IPs
- Launch instance (AMI, type, subnet, security groups, key pair, name tag)
- Terminate instance
- Start / Stop instance
- Resize instance (stop → modify → start)
- Create snapshot
- Create and attach EBS volume
- Run patch baseline via AWS SSM `AWS-RunPatchBaseline`
- View patch compliance status
- Monthly cost breakdown via Cost Explorer

---

### ☸️ Kubernetes Operations (`/kubernetes.html` + Dashboard)
- **Pods** — List pods across any namespace, stream logs
- **Deployments** — List deployments, scale replicas, patch CPU/memory resources
- **Namespaces** — List, create, delete namespaces
- **Helm** — List releases, install chart, upgrade, rollback
- **Cluster info** — Server version, git version, platform
- **Nodes** — List nodes with version, roles, capacity, ready/schedulable state
- **Node actions** — Cordon, uncordon, drain
- **Cluster upgrade** — Select target version from live version list, apply to selected node (kubeadm or kind)

---

### 🏗️ Terraform Runner (`/terraform.html`)
- List workspaces from `terraform-workspaces/` directory
- `terraform init`
- `terraform plan` — streamed live via **Server-Sent Events** (real-time output in browser terminal)
- `terraform apply` — double-confirm required
- `terraform destroy` — double-confirm required
- Workspace path sandboxing — prevents directory traversal

---

### 📋 Activity Log (`/activity.html`)
- Every mutating API call logged to SQLite: timestamp, user, action, resource, status, detail
- Paginated (25/page)
- Full-text search across all columns
- CSV export

---

## 🏗️ Architecture

```
Browser
   │
   ▼
nginx 1.27-alpine (port 80)
   ├── WAF map blocks — scanner UAs, rate limiting
   ├── /                    → static frontend (HTML/CSS/JS)
   └── /api/*               → FastAPI backend (uvicorn :8000)
                                      │
              ┌───────────────────────┼──────────────────────┬───────────────┐
              ▼                       ▼                      ▼               ▼
       azure-mgmt-*               boto3               docker SDK        kubernetes
       DefaultAzureCredential     IAM env vars     /var/run/docker.sock  KUBECONFIG
              │
       subprocess → terraform | kubectl | helm
```

---

## 🚀 Quick Start

### Prerequisites
| Tool | Version | Notes |
|---|---|---|
| Docker | 20+ | With Docker Compose v2 |
| kubectl | 1.28+ | Already bundled inside the backend container |
| kind | 0.32+ | For local Kubernetes cluster |
| helm | 4+ | Already bundled inside the backend container |
| Authenticator app | — | Google Authenticator, Authy, 1Password |

---

### 1. Clone

```bash
git clone https://github.com/DigiWorldfk/cloudops-automation-hub.git
cd cloudops-automation-hub
cp .env.example .env
```

---

### 2. Generate secrets

```bash
# JWT secret (64+ chars)
python3 -c "import secrets; print(secrets.token_hex(64))"

# Admin password hash (bcrypt, rounds=12)
# Install bcrypt first if needed: pip install bcrypt
python3 -c "import bcrypt; print(bcrypt.hashpw(b'YourPassword', bcrypt.gensalt(12)).decode())"

# TOTP secret
python3 -c "import pyotp; print(pyotp.random_base32())"
```

> ⚠️ **bcrypt hash escaping in `.env`**: bcrypt hashes contain `$` signs. Escape each `$` as `$$` in `.env` so Docker Compose does not interpret them as variable references:
> ```
> ADMIN_PASS_HASH=$$2b$$12$$...rest-of-hash...
> ```

---

### 3. Fill in `.env`

```bash
nano .env   # fill in JWT_SECRET, ADMIN_USER, ADMIN_PASS_HASH, TOTP_SECRET
            # and optionally Azure / AWS / Kubernetes credentials
```

---

### 4. Add TOTP to your authenticator app

```bash
# Generate a scannable QR code PNG
brew install qrencode   # macOS (one-time)
qrencode -t PNG -s 8 -o /tmp/totp-qr.png \
  "otpauth://totp/CloudOps%20Hub:admin?secret=YOUR_TOTP_SECRET&issuer=CloudOps%20Hub"
open /tmp/totp-qr.png   # scan with Google Authenticator / Authy
rm /tmp/totp-qr.png     # delete after scanning
```

---

### 5. Start the stack

```bash
docker compose up -d
```

Open **http://localhost** — log in with your username, password, and 6-digit TOTP code.

---

### 6. (Optional) Create a local Kubernetes cluster for testing

```bash
# Create a 2-node kind cluster (1 control-plane + 1 worker)
kind create cluster --config k8s/kind-cluster.yaml

# Deploy 3 test pods (nginx, httpbin, redis) in cloudops-test namespace
kubectl apply -f k8s/test-workloads.yaml

# Generate a kubeconfig the backend container can reach
kind get kubeconfig --name cloudops-local \
  | sed 's/127.0.0.1/host.docker.internal/g' \
  | sed 's/certificate-authority-data:.*/insecure-skip-tls-verify: true/' \
  > k8s/kubeconfig-local.yaml

# Restart backend to pick up the kubeconfig
docker compose restart backend
```

The dashboard **☸️ Kubernetes** panels will now show the live `cloudops-local` cluster.

---

### 7. (Optional) Connect Azure

In the Azure Portal:
1. **App registrations** → New registration → name `cloudops-hub` → Register
2. Copy **Application (client) ID** → `AZURE_CLIENT_ID`
3. Copy **Directory (tenant) ID** → `AZURE_TENANT_ID`
4. **Certificates & secrets** → New client secret → copy value → `AZURE_CLIENT_SECRET`
5. **Subscriptions** → your sub → IAM → Add role assignment → `Contributor` → select `cloudops-hub`
6. Fill in `.env` and restart: `docker compose restart backend`

---

### 8. (Optional) Add a Terraform workspace

```bash
mkdir -p terraform-workspaces/my-infra
# copy your .tf files into terraform-workspaces/my-infra/
```

The workspace will appear in the Terraform dropdown on `/terraform.html`.

---

## 🔒 Security Model

| Layer | Control |
|---|---|
| Authentication | bcrypt (rounds=12) + TOTP 2FA on every login |
| Session tokens | JWT in `httpOnly SameSite=Strict` cookies — not accessible to JS |
| Transport | nginx reverse proxy (add TLS cert for production) |
| WAF | nginx blocks scanner user-agents (sqlmap, nikto, nmap, masscan, zgrab) |
| Rate limiting | 5 req/min login endpoint · 30 req/s all other API |
| Containers | `cap_drop: ALL` · `no-new-privileges: true` |
| Secrets | All credentials in `.env` (gitignored) — never in source control |
| Secret scanning | gitleaks in CI on every push |
| RBAC | `role` field in JWT · `require_role()` enforced per-endpoint |
| Audit trail | Every mutating call logged: user · action · resource · status · timestamp |

---

## 📡 API Reference

FastAPI generates interactive docs at **http://localhost/api/docs**

| Prefix | Endpoints |
|---|---|
| `/api/auth` | `POST /login` · `POST /logout` · `POST /refresh` · `GET /me` |
| `/api/dashboard` | `GET /summary` |
| `/api/azure` | VMs: list · create · delete · start · stop · resize · snapshot · expand-disk · patch |
| `/api/aws` | EC2: list · create · terminate · start · stop · resize · snapshot · attach-volume · patch · costs |
| `/api/docker` | Containers: list · start · stop · restart · remove · logs · Images: list · pull |
| `/api/k8s` | Namespaces · Pods · Pod logs · Deployments · Scale · Patch resources · Cluster info · Cluster versions · Node cordon/uncordon/drain · Cluster upgrade · Helm: list/install/upgrade/rollback |
| `/api/terraform` | list-workspaces · init · plan (SSE) · apply · destroy |
| `/api/activity` | `GET /` paginated · `GET /export` CSV |

---

## 🗂️ Project Structure

```
cloudops-automation-hub/
├── .github/
│   └── workflows/ci.yml           # Lint · secret scan · Docker build test
├── .gitleaks.toml                 # Custom secret detection rules
├── .env.example                   # All variables with generation instructions
├── docker-compose.yml             # nginx + backend, hardened containers
├── k8s/
│   ├── kind-cluster.yaml          # 2-node local cluster (1 control-plane + 1 worker)
│   └── test-workloads.yaml        # 3 test pods: nginx, httpbin, redis
├── nginx/
│   ├── Dockerfile
│   └── nginx.conf                 # WAF + rate limiting + reverse proxy
├── backend/
│   ├── Dockerfile                 # Python 3.12 + Terraform + kubectl + Helm
│   ├── requirements.txt
│   ├── main.py                    # FastAPI app, router mounts
│   ├── routers/
│   │   ├── auth.py                # Login, logout, refresh, me
│   │   ├── dashboard.py           # Summary overview
│   │   ├── azure.py               # Azure VM operations
│   │   ├── aws.py                 # AWS EC2 operations
│   │   ├── docker_ops.py          # Docker container/image operations
│   │   ├── kubernetes_ops.py      # K8s + Helm + cluster/node management
│   │   ├── terraform.py           # Terraform runner with SSE streaming
│   │   └── activity.py            # Audit log
│   ├── services/
│   │   ├── azure_client.py        # azure-mgmt-compute/network
│   │   ├── aws_client.py          # boto3 EC2 + SSM + Cost Explorer
│   │   ├── docker_client.py       # docker SDK via socket
│   │   ├── k8s_client.py          # kubernetes Python client + kubectl subprocess
│   │   └── terraform_runner.py    # async subprocess + SSE generator
│   ├── auth/
│   │   ├── jwt_handler.py         # bcrypt verify + TOTP verify + JWT encode/decode
│   │   └── dependencies.py        # FastAPI dependency injection for auth/RBAC
│   ├── db/database.py             # aiosqlite activity log
│   └── models/schemas.py          # Pydantic request/response models
└── frontend/
    ├── style.css                  # Dark theme (#0a0f1a bg · #3b82f6 accent)
    ├── shared.js                  # authGuard · buildSidebar · api() helper · badge()
    ├── login.html                 # TOTP 2FA login form
    ├── dashboard.html             # Overview + Docker controls + K8s controls + Cluster panel
    ├── azure.html                 # Azure VM CRUD
    ├── aws.html                   # AWS EC2 CRUD
    ├── docker.html                # Full Docker management
    ├── kubernetes.html            # Pods · Deployments · Helm · Namespaces
    ├── terraform.html             # Streaming plan/apply/destroy terminal
    └── activity.html              # Paginated searchable audit log
```

---

## 🌍 Environment Variables

See [`.env.example`](.env.example) for the full list with generation commands.

| Variable | Required | Description |
|---|---|---|
| `JWT_SECRET` | ✅ | 64+ char random string — `secrets.token_hex(64)` |
| `ADMIN_USER` | ✅ | Login username |
| `ADMIN_PASS_HASH` | ✅ | bcrypt hash — escape `$` as `$$` in `.env` |
| `TOTP_SECRET` | ✅ | Base32 seed — `pyotp.random_base32()` |
| `AZURE_SUBSCRIPTION_ID` | Azure | Azure subscription UUID |
| `AZURE_TENANT_ID` | Azure | Service Principal tenant UUID |
| `AZURE_CLIENT_ID` | Azure | Service Principal app UUID |
| `AZURE_CLIENT_SECRET` | Azure | Service Principal secret value |
| `AWS_ACCESS_KEY_ID` | AWS | IAM access key |
| `AWS_SECRET_ACCESS_KEY` | AWS | IAM secret key |
| `AWS_DEFAULT_REGION` | AWS | e.g. `us-east-1` |
| `KUBECONFIG` | K8s | Path inside container — default `/app/kubeconfig.yaml` |
| `DB_PATH` | Optional | SQLite path — default `/app/data/cloudops.db` |

---

## 🗺️ Roadmap

| Phase | Feature |
|---|---|
| **Phase 4** | RBAC approval workflow — engineer raises request · admin approves · action executes |
| **Phase 4** | Cost dashboard with Chart.js trend graphs |
| **Phase 5** | AI incident recommendations via Azure OpenAI |
| **Phase 5** | ChatOps assistant — natural language → infrastructure action |
| **Production** | HTTPS/TLS via Let's Encrypt · multi-user accounts · PostgreSQL · Prometheus metrics |

---

## 🔗 Related Projects

- [Azure AKS Enterprise Platform](../azure-aks-enterprise-platform/) — 9-module Terraform platform with private AKS, WAF, Key Vault
- [AWS EKS Enterprise Platform](../aws-eks-enterprise-platform/) — 14-module Terraform platform with EKS, GuardDuty, Config rules
- [DigiWorld Portfolio](https://digiworldfk.github.io/DigitalFreelanceWorld/) — Live portfolio site


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

