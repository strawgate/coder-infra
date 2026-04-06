# Developing

Project structure, Terraform layout, and how to extend coder-infra.

## Project structure

```
coder-infra/
├── control-plane/                     # Terraform for the Coder server VM
│   ├── main.tf                        # Provider config (google ~> 5.0)
│   ├── control_plane.tf               # VM, firewall, IAM, service account, Cloud NAT
│   ├── variables.tf                   # Input variables (project_id, admin_email, etc.)
│   ├── outputs.tf                     # Connection commands and metadata
│   └── startup.sh                     # VM bootstrap (installs Coder, configures systemd)
├── workspace-templates/               # Coder workspace templates
│   └── gcp-agent/                     # AI agent workspace (Claude Code or Copilot)
│       └── main.tf                    # VM, disk, agent config, registry modules
├── scripts/                           # Helper scripts
│   ├── connect.sh                     # Open IAP tunnel to Coder
│   ├── ssh.sh                         # SSH into control plane via IAP
│   ├── start.sh                       # Start the control plane VM
│   └── stop.sh                        # Stop the control plane VM
├── Makefile                           # Top-level commands
└── .gitignore                         # Excludes .terraform, tfstate, tfvars, secrets
```

## Control plane resources

The control plane Terraform (`control-plane/`) manages 10 GCP resources:

| Resource | Purpose |
|----------|---------|
| `google_compute_instance.coder` | e2-micro VM running Coder server |
| `google_service_account.coder` | Service account for workspace VM management |
| `google_project_iam_member.coder_compute` | roles/compute.admin for workspace VMs |
| `google_project_iam_member.coder_sa_user` | roles/iam.serviceAccountUser |
| `google_project_iam_member.iap_tunnel` | IAP tunnel access for admin |
| `google_compute_firewall.allow_iap` | Allows IAP range (35.235.240.0/20) → ports 22, 3000 |
| `google_project_service.compute` | Enables Compute Engine API |
| `google_project_service.iap` | Enables IAP API |
| `google_compute_router.coder` | Cloud Router for NAT |
| `google_compute_router_nat.coder` | Cloud NAT (outbound internet, no public IP) |

### Variables

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `project_id` | Yes | — | GCP project ID |
| `admin_email` | Yes | — | Google account for IAP access |
| `region` | No | `us-central1` | GCP region (free tier regions) |
| `zone` | No | `us-central1-a` | GCP zone |
| `machine_type` | No | `e2-micro` | Control plane VM type |
| `boot_disk_size_gb` | No | `30` | Boot disk size (30 GB = free tier) |
| `coder_version` | No | `""` (latest) | Coder version to install |
| `github_oauth_client_id` | No | `""` | GitHub OAuth App for git in workspaces |
| `github_oauth_client_secret` | No | `""` | GitHub OAuth App secret |

### Startup script

`startup.sh` is a Terraform templatefile that:

1. Installs Coder via the official install script
2. Creates a `coder` system user
3. Configures a systemd service (`coder.service`)
4. Optionally adds a GitHub external auth drop-in if `github_oauth_client_id` is set

## Workspace template

`workspace-templates/gcp-agent/main.tf` is a Coder template, not standard Terraform infra. It uses the Coder Terraform provider and creates:

- **Persistent disk** (`pd-balanced`) that survives workspace stop/start
- **Spot e2-small VM** (destroyed on stop, recreated on start)
- **Coder agent** with startup script that installs Node.js 22 and clones a repo
- **Claude Code** via [`coder/claude-code`](https://registry.coder.com/modules/coder/claude-code) v4.9.1
- **GitHub Copilot** via [`coder-labs/copilot`](https://registry.coder.com/modules/coder-labs/copilot) v0.4.0
- **Tasks integration** via `coder_ai_task` + `data.coder_task` for Coder's task queue UI
- **Firewall rule** allowing IAP SSH to workspace VMs

### Template parameters

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `project_id` | — | GCP project for workspace VMs |
| `region` | `us-central1` | GCP region |
| `zone` | `us-central1-a` | GCP zone |
| `machine_type` | `e2-small` | Workspace VM size |
| `disk_size_gb` | `50` | Persistent disk size |
| `repo_url` | `""` | Repository to clone (optional) |
| `agent` | `claude` | AI agent: Claude Code or GitHub Copilot |

### Template variables

| Variable | Purpose |
|----------|---------|
| `anthropic_api_key` | Anthropic API key for Claude Code (sensitive) |

### Pushing template changes

```bash
coder templates push gcp-agent --directory workspace-templates/gcp-agent
```

## Adding a new workspace template

1. Create a directory under `workspace-templates/`:
   ```
   workspace-templates/my-template/main.tf
   ```
2. Use the `coder` Terraform provider — see the [Coder template docs](https://coder.com/docs/templates)
3. Push to Coder:
   ```bash
   coder templates push my-template --directory workspace-templates/my-template
   ```

## GitHub external auth

To let workspace agents authenticate with GitHub:

1. Create a GitHub OAuth App at https://github.com/settings/applications/new
   - **Homepage URL:** `http://localhost:3000`
   - **Callback URL:** `http://localhost:3000/external-auth/primary-github/callback`
2. Add to `terraform.tfvars`:
   ```hcl
   github_oauth_client_id     = "your-client-id"
   github_oauth_client_secret = "your-client-secret"
   ```
3. Re-apply: `make apply`

## Make targets

```bash
make init TF_STATE_BUCKET=<bucket>  # terraform init with remote backend
make plan                           # terraform plan
make apply                          # terraform apply
make destroy                        # terraform destroy
make fmt                            # terraform fmt -recursive
make validate                       # terraform validate
make connect                        # Open IAP tunnel → localhost:3000
make ssh                            # SSH into control plane
make start                          # Start the VM
make stop                           # Stop the VM
make bootstrap-ci GCP_PROJECT_ID=<id> GITHUB_REPO=<owner/repo>  # One-time CI setup
make migrate-state TF_STATE_BUCKET=<bucket>                      # Migrate local → GCS
```

## CI/CD

### Architecture

```
PR opened/updated → terraform-plan.yml → plan posted as PR comment
Merge to main     → terraform-apply.yml → auto-apply
```

Both workflows use **Workload Identity Federation** (keyless) to authenticate with GCP — no service account keys stored in GitHub.

### Components

| Component | Purpose |
|-----------|---------|
| GCS bucket (`<project>-tfstate`) | Remote Terraform state with versioning |
| Workload Identity Pool (`github-actions`) | Maps GitHub OIDC tokens to GCP |
| Service Account (`github-actions-terraform`) | IAM identity for Terraform in CI |

### GitHub Secrets required

| Secret | Example |
|--------|---------|
| `GCP_PROJECT_ID` | `project-758068e8-e931-45df-ae8` |
| `GCP_WIF_PROVIDER` | `projects/.../providers/github` |
| `GCP_SERVICE_ACCOUNT` | `github-actions-terraform@...iam.gserviceaccount.com` |
| `TF_STATE_BUCKET` | `project-758068e8-e931-45df-ae8-tfstate` |
| `GCP_ADMIN_EMAIL` | `you@example.com` |

### First-time setup

```bash
# 1. Run bootstrap (requires gcloud auth'd locally)
./scripts/bootstrap-ci.sh <project_id> <github_owner/repo>

# 2. Add secrets printed by the script to GitHub repo settings

# 3. Migrate existing local state to GCS
make migrate-state TF_STATE_BUCKET=<bucket>

# 4. Push to trigger workflows
```

### Scope

CI/CD covers only the **control plane** (`control-plane/`). Workspace templates are managed by Coder itself — push them with `coder templates push`.
