# CloudOps Automation Hub: Setup and Code Walkthrough

This guide is a learning-oriented companion for the repository. It explains how to run the local CloudOps Automation Hub, how a browser request moves through the system, and how the Terraform, Kubernetes, Helm, GitOps, and CI/CD folders fit together.

`README.md` is intentionally preserved. It remains the existing Azure AKS Enterprise Platform document. This file focuses on the complete repository and the local application that sits beside the AWS and Azure platform examples.

## 1. What This Repository Contains

The repository has four related concerns:

1. **CloudOps Automation Hub application**
   - Static HTML/CSS/JavaScript frontend in `frontend/`.
   - FastAPI backend in `backend/`.
   - Nginx reverse proxy and static-file server in `nginx/`.
   - Local orchestration in `docker-compose.yml`.
2. **Reusable platform infrastructure**
   - Azure AKS platform in the root `terraform/`, `kubernetes/`, `helm/`, and `gitops/` directories.
   - AWS EKS platform in `aws-eks-enterprise-platform/`.
   - Azure AKS platform documentation and a second, self-contained platform layout in `azure-aks-enterprise-platform/`.
3. **Operational policy and automation**
   - Kubernetes hardening in `kubernetes/policy/`, `kubernetes/network-policies/`, and `kubernetes/rbac/`.
   - OPA policy in `policies/terraform.rego`.
   - GitHub Actions workflows in `pipelines/` and `.github/`.
4. **Local development and learning assets**
   - `k8s/` contains the local Kind cluster definition, test workloads, and the ignored local kubeconfig mount point.
   - `docs/` contains architecture material and screenshots.

A useful mental model is:

```text
Browser
  |
  v
Nginx :80  ---- serves frontend/*.html and frontend/*.js
  |
  +---- /api/* ----> FastAPI :8000
                         |
                         +--> SQLite activity and approval records
                         +--> Azure SDK / AWS SDK
                         +--> Docker SDK (disabled by default; no host socket mounted)
                         +--> Kubernetes SDK and kubectl via kubeconfig
                         +--> Terraform CLI in isolated workspaces
                         +--> OpenAI or Azure OpenAI for the AI agent

Terraform / Helm / GitOps files describe the infrastructure where the
platform and its workloads can run.
```

## 2. Prerequisites

For the local application:

- Docker Desktop with the Compose plugin.
- Git.
- A shell that can run the commands below.
- A local Kubernetes cluster such as Kind or Docker Desktop Kubernetes if you want Kubernetes features.
- A local kubeconfig file for that cluster.

For infrastructure deployment, additionally install only the tools for the path you are using:

- Terraform >= 1.5 for the root Azure platform.
- Azure CLI (`az`) for Azure authentication and AKS operations.
- AWS CLI for the AWS EKS platform.
- `kubectl`, Helm, and optionally Argo CD CLI for Kubernetes operations.
- `tflint`, `pre-commit`, and `gitleaks` for repository checks.

Cloud credentials are not needed just to open the local UI, but the provider, Docker, Kubernetes, and Terraform actions need their corresponding credentials and connectivity.

## 3. First-Time Local Setup

Run these commands from the repository root.

### Step 1: Create the runtime environment file

```bash
cp .env.example .env
```

Edit `.env` before starting the application. At minimum, replace the placeholder values for:

- `JWT_SECRET`
- `ADMIN_PASS_HASH`
- `TOTP_SECRET`
- Any Azure, AWS, Kubernetes, Terraform, or AI credentials needed for the features you intend to use

Generate an administrator password hash and TOTP secret. The backend installs `bcrypt`, so this command does not require an extra host-side Python package:

```bash
python3 -c "import bcrypt; print(bcrypt.hashpw(b'replace-this-password', bcrypt.gensalt()).decode())"
python3 -c "import pyotp; print(pyotp.random_base32())"
```

The application requires both the configured password and a valid TOTP code during login. The default username is `admin` unless `ADMIN_USER` is changed.

Important: `.env` is gitignored. Never commit it, cloud credentials, real Terraform variable files, kubeconfig files, or database files.

### Step 2: Prepare the Kubernetes kubeconfig mount

Compose mounts `k8s/kubeconfig-local.yaml` into the backend container as `/app/kubeconfig.yaml`. Create or copy that file before starting:

```bash
mkdir -p k8s
touch k8s/kubeconfig-local.yaml
```

For Kubernetes features, replace the empty file with a kubeconfig for the local cluster. For a Kind cluster, a typical sequence is:

```bash
kind create cluster --name cloudops-local --config k8s/kind-cluster.yaml
kind get kubeconfig --name cloudops-local > k8s/kubeconfig-local.yaml
```

The file is ignored by Git through `k8s/kubeconfig-*.yaml`.

### Step 3: Check the Compose configuration

```bash
docker compose config --quiet
```

If this fails with a missing `.env` or kubeconfig file, complete Steps 1 and 2. This command validates configuration without starting containers.

### Step 4: Build and start the application

```bash
docker compose up --build -d
```

Compose starts two services:

- `backend`: builds from `backend/Dockerfile`, listens internally on port `8000`, and includes Python, Terraform 1.8.5, kubectl 1.30.2, and Helm.
- `nginx`: builds from `nginx/Dockerfile`, publishes host port `80`, serves the frontend, and proxies API requests to `backend:8000`.

Check status and logs:

```bash
docker compose ps
docker compose logs -f backend nginx
```

### Step 5: Verify the service

```bash
curl http://localhost/health
curl http://localhost/api/health
```

Both health paths are handled by FastAPI. Nginx maps `/health` to the backend health endpoint; `/api/health` reaches the same FastAPI route directly.

Open `http://localhost/` in a browser. Nginx uses `login.html` as the default page and falls back to it for unknown frontend paths.

### Step 6: Log in and explore

Use the configured `ADMIN_USER`, password, and current TOTP code. After login, the frontend stores the current user in `sessionStorage` and uses the HTTP-only access cookie for API requests.

The main pages are:

| Page | Purpose | Main backend area |
| --- | --- | --- |
| `dashboard.html` | Summary and platform status | `/api/dashboard` |
| `agent.html` | AI tool conversation and approvals | `/api/ai` |
| `azure.html` | Azure VM operations | `/api/azure` |
| `aws.html` | AWS EC2 operations and costs | `/api/aws` |
| `docker.html` | Container and image operations | `/api/docker` |
| `kubernetes.html` | Cluster, pods, deployments, nodes, and Helm | `/api/k8s` |
| `terraform.html` | Workspace init, plan, apply, and destroy | `/api/terraform` |
| `activity.html` | Audit/activity history | `/api/activity` |

The interactive API reference is available at `http://localhost/api/docs`.

### Step 7: Stop or reset local services

```bash
docker compose down
```

To remove the persistent local volumes as well, use this only when you are willing to lose the SQLite activity database and Terraform workspace data:

```bash
docker compose down -v
```

## 4. Runtime Logic, Step by Step

### 4.1 Browser to API

1. The browser requests `/` from Nginx.
2. Nginx serves files from the read-only `frontend/` mount.
3. Each protected page calls `authGuard()` from `frontend/shared.js`.
4. `authGuard()` calls `/api/auth/me`; an unsuccessful response redirects to `login.html`.
5. Frontend API calls use the shared `api()` helper, which prefixes paths with `/api`, sends JSON, includes cookies, and redirects to login on HTTP 401.
6. Nginx applies security headers, scanner user-agent blocking, and rate limits before proxying the request.
7. FastAPI dispatches the request to the router registered in `backend/main.py`.

### 4.2 Authentication

The authentication path is:

```text
POST /api/auth/login
  -> validate username
  -> verify bcrypt password hash
  -> verify TOTP code
  -> create short-lived access JWT and refresh JWT
  -> set HTTP-only cookies
  -> write a LOGIN activity record
```

`backend/auth/jwt_handler.py` creates HS256 tokens. `backend/auth/dependencies.py` accepts the access token from either the `access_token` cookie or an `Authorization: Bearer ...` header. Protected routes use `Depends(get_current_user)` and role-restricted routes use `require_role(...)`.

The configured defaults are a 15-minute access token and a 7-day refresh token. Local development uses `COOKIE_SECURE=false`; production must set `ENVIRONMENT=production`, `COOKIE_SECURE=true`, and run behind HTTPS. The backend fails startup if production security settings are missing.

### 4.3 Startup and persistence

FastAPI registers a startup handler in `backend/main.py`. It calls `db.database.init_db()`, which creates these SQLite tables when they do not exist:

- `activity_log`: user, action, resource, status, timestamp, and detail.
- `ai_approvals`: AI tool requests, risk tier, approval status, reviewer, and result.

Compose stores `/app/data` in the `cloudops_data` named volume, so the database survives a normal container recreation. Terraform workspace files use the separate `terraform_workspaces` volume.

### 4.4 Provider operations

The route modules validate request models and call service modules:

- `routers/azure.py` -> `services/azure_client.py` -> Azure management SDK.
- `routers/aws.py` -> `services/aws_client.py` -> boto3.
- `routers/docker_ops.py` -> `services/docker_client.py` -> Docker SDK. Docker operations are disabled by default and the backend does not mount the host Docker socket.
- `routers/kubernetes_ops.py` -> `services/k8s_client.py` -> Kubernetes Python client, kubectl, and Helm.
- `routers/terraform.py` -> `services/terraform_runner.py` -> Terraform subprocesses.

Successful and failed operational actions are intended to be represented in the activity log so operators can inspect what happened from `activity.html`.

### 4.5 Terraform operations from the UI

The Terraform service treats each named workspace as a directory beneath `TERRAFORM_WORKSPACES`. `workspace_path()` resolves the path and rejects names that escape the configured root. The backend then runs:

- `terraform init`
- `terraform plan` as a streamed output response
- `terraform apply -auto-approve`
- `terraform destroy -auto-approve`

The container has Terraform installed, but the UI's workspace directory is not automatically populated with a Terraform configuration. Put a valid, reviewed configuration in the selected workspace before initializing or planning it. Treat UI apply and destroy actions as privileged operations.

### 4.6 AI agent and approvals

`backend/services/ai_tools.py` defines the callable tool registry used by the AI router. Tools are classified as:

- `green`: read-only or low-risk actions that can execute automatically.
- `amber`: mutating actions that require approval.
- `red`: higher-risk actions that require approval.

The AI route can create pending records in `ai_approvals`. Approval and denial endpoints update the record and, where applicable, execute the requested operation. The AI provider is configured with either Azure OpenAI variables or standard OpenAI variables from `.env`.

Read the registry before enabling AI operations in a shared environment. The model can invoke operational tools, so credentials and role restrictions must be deliberately scoped.

## 5. Local Kubernetes Learning Path

Use this path when you want the UI to inspect and operate a local cluster.

1. Create the Kind cluster using `k8s/kind-cluster.yaml`.
2. Export the cluster kubeconfig to `k8s/kubeconfig-local.yaml`.
3. Apply the sample workloads from `k8s/test-workloads.yaml`.
4. Start or restart the backend so it reads the mounted kubeconfig.
5. Open `kubernetes.html` and inspect namespaces, pods, deployments, and logs.
6. Test a reversible action such as scaling a test deployment.
7. Inspect the activity log after the action.

For the shared Kubernetes platform manifests, apply the hardening layers from the repository root only after reviewing the target cluster:

```bash
make apply-k8s-policy
make otel-install
```

The root Makefile also provides:

```bash
make help
make health
make logs
make port-forward
```

`make port-forward` targets the Argo CD service in the `argocd` namespace and is for a cluster where Argo CD has already been installed.

## 6. Root Azure Platform Deployment

The root Terraform tree provisions the Azure AKS platform described by the existing `README.md`. It is separate from the local Compose application, although the application can operate against the resulting Azure and Kubernetes resources when credentials and kubeconfig are configured.

### Step 1: Authenticate to Azure

```bash
az login
az account set --subscription <subscription-id>
az account show
```

Use a least-privileged deployment identity in CI. Do not place client secrets in Terraform files.

### Step 2: Configure remote state

The one-time bootstrap creates the Azure Storage resources used for Terraform state:

```bash
make bootstrap
```

Then create a gitignored `backend.hcl` in each environment directory using its example file, or follow the environment-specific instructions in the platform README.

### Step 3: Configure sensitive variables

Create a gitignored `terraform.tfvars` from the relevant example in `terraform/environments/<env>/`. At minimum, review the TLS certificate secret URI and MySQL administrator password. The environment variables also define network CIDRs, AKS sizing, region, custom domains, and DNS settings.

### Step 4: Validate before provisioning

```bash
make fmt
make validate
make lint
```

`make validate` initializes each environment without a backend and runs `terraform validate`. `make lint` requires `tflint`.

### Step 5: Plan and apply one environment

```bash
make plan ENV=dev
make apply ENV=dev
```

The Makefile requires an explicit `yes` confirmation for `ENV=prod` and refuses `make destroy ENV=prod`. Review the plan carefully, especially network exposure, identity assignments, database settings, and WAF mode.

### Step 6: Connect to AKS and install cluster services

```bash
make aks-creds ENV=dev
make health
make apply-k8s-policy
make velero-install ENV=dev
make argocd-install
make otel-install
```

The expected order is infrastructure first, kubeconfig second, cluster policies and platform services third, and workload synchronization through Argo CD last.

## 7. Helm and GitOps Flow

The root `helm/` chart packages the frontend and backend workloads. `values.yaml` contains shared defaults, while `values-dev.yaml` and `values-prod.yaml` override environment settings.

The GitOps flow is:

```text
Git commit
  -> CI validates Terraform, images, manifests, and security policies
  -> image build publishes a tagged frontend/backend image
  -> Argo CD watches gitops/applications/app-of-apps.yaml
  -> child Applications reconcile backend, frontend, monitoring, and policy
  -> Helm/Kubernetes manifests create or update workloads in the cluster
```

Important GitOps files:

- `gitops/applications/app-of-apps.yaml`: root Argo CD application.
- `gitops/applications/backend.yaml`: backend application definition.
- `gitops/applications/frontend.yaml`: frontend application definition.
- `gitops/applications/monitoring.yaml`: monitoring application definition.
- `gitops/applications/policy.yaml`: policy application definition.
- `gitops/argocd/project.yaml`: Argo CD project boundaries.
- `gitops/argocd/rbac.yaml`: Argo CD RBAC.
- `gitops/argocd/image-updater.yaml`: image update configuration.

Review the rendered chart before changing values:

```bash
helm lint helm
helm template cloudops helm -f helm/values.yaml
helm template cloudops helm -f helm/values-dev.yaml
```

## 8. AWS EKS Platform Path

The AWS implementation is intentionally self-contained under `aws-eks-enterprise-platform/`. Start with its README rather than mixing its Terraform state with the root Azure state:

```bash
cd aws-eks-enterprise-platform
make help
```

Its deployment stages are the same broad pattern:

1. Bootstrap remote state.
2. Configure the selected environment.
3. Validate and plan Terraform.
4. Apply the EKS, VPC, load balancer, database, ECR, security, and supporting modules.
5. Configure kubeconfig and apply GitOps workloads.
6. Complete the documented manual steps and verify security controls.

Keep AWS and Azure credentials, state backends, environment variable files, and Kubernetes contexts separate.

## 9. CI/CD and Policy Checks

The workflows under `pipelines/` cover three concerns:

- `terraform.yml`: format, initialize without a backend, validate, lint, and environment-specific infrastructure checks.
- `build.yml`: build and publish application or Helm-related artifacts when relevant paths change.
- `security.yml`: security scanning, including Terraform configuration scanning.

Before opening a change, run the checks available locally:

```bash
make pre-commit-install
make pre-commit-run
make fmt
make validate
make lint
```

The OPA policy in `policies/terraform.rego` is part of the infrastructure guardrail layer. Read it alongside the Terraform module it constrains; policy failures are usually safer to fix in the module configuration than to bypass in CI.

## 10. Security Model and Operational Warnings

This project is an operations portal, so a local convenience setting can become a serious production risk:

- Replace every placeholder in `.env`; the fallback JWT secret in code is for development only.
- Keep `.env`, Terraform variable files, state, kubeconfig, cloud keys, and database files out of Git.
- Use a narrowly scoped Azure service principal or managed identity and a narrowly scoped AWS identity.
- The backend container does not mount `/var/run/docker.sock`; Docker operations remain disabled unless a separately isolated privileged worker is designed.
- The backend can run Terraform, kubectl, Helm, Docker, AWS, and Azure operations. Restrict network access and authenticated roles accordingly.
- Nginx rate-limits login and API requests and blocks several scanner user agents, but it is not a replacement for a production WAF, TLS termination, identity provider, or network segmentation.
- CORS is configured from `CORS_ALLOWED_ORIGINS`, and cross-origin state-changing requests are rejected unless explicitly allowed. Production requires secure cookies and HTTPS.
- Enable HTTPS, secure cookies, a managed identity or secret manager, production WAF blocking mode, logging, backups, and alerting before production use.
- Test backup and restore procedures rather than treating a successful backup configuration as proof of recoverability.

The repository's `SECURITY.md` contains the vulnerability reporting process and credential-handling policy.

## 11. Troubleshooting Checklist

### Compose does not start

1. Confirm `.env` exists: `test -f .env`.
2. Confirm the kubeconfig mount exists: `test -f k8s/kubeconfig-local.yaml`.
3. Run `docker compose config --quiet`.
4. Rebuild after dependency or Dockerfile changes: `docker compose up --build -d`.
5. Read service logs: `docker compose logs --tail=200 backend nginx`.

### Login fails

1. Confirm `ADMIN_USER` matches the submitted username.
2. Confirm `ADMIN_PASS_HASH` is a valid bcrypt hash, not a plaintext password.
3. Confirm the authenticator uses the configured `TOTP_SECRET`.
4. Check `docker compose logs backend` for startup or database errors.
5. Confirm the browser is receiving cookies from the same host.

### Kubernetes actions fail

1. Confirm the mounted kubeconfig points to a reachable cluster.
2. Check the current context outside the container.
3. Confirm the backend container can resolve and reach the cluster endpoint.
4. Verify the requested namespace, pod, deployment, or Helm release exists.
5. Inspect backend logs for Kubernetes client or subprocess errors.

### Cloud actions fail

1. Confirm the corresponding variables exist in `.env`.
2. Confirm the identity has the required least-privilege permissions.
3. Confirm the configured subscription, account, region, and resource group are correct.
4. Validate cloud CLI access independently before retrying from the UI.
5. Review the activity log and backend logs for the exact provider response.

### Terraform actions fail

1. Confirm the workspace contains Terraform configuration.
2. Run `terraform init` and `terraform validate` in that workspace.
3. Confirm the backend configuration and credentials are available.
4. Check that the container has network access to provider endpoints.
5. Inspect the streamed plan output before applying changes.

## 12. Suggested Reading Order

For a first pass through the code, use this order:

1. `docker-compose.yml` to understand the two containers, volumes, networks, and security settings.
2. `nginx/nginx.conf` to understand static routing, proxying, headers, and rate limits.
3. `backend/main.py` to see startup, health, and router registration.
4. `backend/auth/` and `backend/db/database.py` to understand authentication and persistence.
5. One router and its matching service, such as `routers/kubernetes_ops.py` and `services/k8s_client.py`.
6. `frontend/shared.js` and the corresponding HTML page to see how the UI calls the API.
7. `Makefile` for operational commands.
8. `helm/`, `kubernetes/`, and `gitops/` for workload deployment.
9. `terraform/environments/dev/main.tf` and the modules it calls for Azure infrastructure.
10. `aws-eks-enterprise-platform/README.md` and `azure-aks-enterprise-platform/README.md` for the two platform-specific deployment guides.

That sequence moves from one local request, through its backend implementation, to the infrastructure that can host and operate it.

## 13. Useful Commands

```bash
# Local application
docker compose up --build -d
docker compose ps
docker compose logs -f backend nginx
docker compose down

# Repository Makefile
make help
make health
make logs
make plan ENV=dev
make apply ENV=dev
make output ENV=dev

# Kubernetes and Helm
kubectl get pods --all-namespaces
helm list --all-namespaces
kubectl get applications -n argocd

# API documentation
open http://localhost/api/docs
```

Use `README.md` for the existing Azure AKS platform reference and this file for the end-to-end repository learning path.
