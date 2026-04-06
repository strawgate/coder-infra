# coder-infra

Coder-on-GCP infrastructure for AI agent dev environments. Terraform + shell scripts to spin up a self-hosted [Coder](https://coder.com) instance behind a GCP IAP tunnel with zero public IP exposure.

## Architecture

```
┌─────────────────┐      IAP tunnel       ┌─────────────────────┐
│  Your laptop    │ ──────────────────── │  e2-micro (free)    │
│  localhost:3000 │                        │  Coder control plane│
└─────────────────┘                        │  No public IP       │
                                           └────────┬────────────┘
                                                    │ Internal VPC
                                    ┌───────────────┼───────────────┐
                                    │               │               │
                              ┌─────┴─────┐   ┌────┴──────┐  ┌────┴──────┐
                              │ workspace │   │ workspace │  │ workspace │
                              │ e2-small  │   │ e2-small  │  │ e2-small  │
                              │ Claude    │   │ Copilot   │  │ Claude    │
                              └───────────┘   └───────────┘  └───────────┘
```

## Cost

| Component | Cost |
|-----------|------|
| Control plane (e2-micro) | $0/mo (free tier) |
| Boot disk (30 GB pd-standard) | $0/mo (free tier) |
| IAP tunnel | $0/mo |
| Workspace VM (e2-small, spot) | ~$0.16/day when running |
| Workspace disk (50 GB pd-balanced) | ~$5/mo per workspace |

## Prerequisites

- [Terraform](https://terraform.io) >= 1.5
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) authenticated (`gcloud auth login`)
- A GCP project with billing enabled
- [Coder CLI](https://coder.com/docs/install) (for template management)

## Quick start

```bash
# 1. Initialize Terraform
make init

# 2. Configure your project
cp control-plane/terraform.tfvars.example control-plane/terraform.tfvars
# Edit terraform.tfvars with your project_id and admin_email

# 3. Deploy the control plane
make apply

# 4. Connect via IAP tunnel
make connect

# 5. Open http://localhost:3000 and create your admin account
#    (first user becomes the owner)

# 6. Push the workspace template
coder templates push gcp-agent --directory workspace-templates/gcp-agent
```

## Daily usage

```bash
make connect   # Open tunnel → http://localhost:3000
make stop      # Stop the VM (save compute, disk persists)
make start     # Start it back up
make ssh       # SSH into the control plane
```

## Workspace template

The `gcp-agent` template creates workspaces for AI coding agents:

- **e2-small** GCP VM (spot pricing, no public IP)
- **Persistent 50 GB disk** that survives stop/start
- **Agent selection**: Claude Code or GitHub Copilot
- **Tasks integration** for Coder's task queue UI
- **Optional repo clone** on first start

Create a workspace from the Coder dashboard or CLI:

```bash
coder create my-workspace --template gcp-agent
```

## Swapping access method

The IAP tunnel works with zero cost but requires `gcloud` on every client. Alternatives:

| Method | Cost | Notes |
|--------|------|-------|
| **IAP tunnel** (current) | $0/mo | Requires `gcloud` |
| **Tailscale** | Free | Mesh VPN, no public URL |
| **Cloudflare Tunnel + Access** | Free | Public URL with Google OAuth |
| **GCP HTTPS LB + IAP** | ~$18/mo | Native Google SSO |

No changes needed on the Coder side — just update the firewall and `CODER_ACCESS_URL`.

## CI/CD

Infrastructure changes deploy automatically via GitHub Actions:

- **Pull requests** → `terraform plan` posted as a PR comment
- **Merge to main** → `terraform apply` runs automatically

### First-time CI setup

```bash
# 1. Run the bootstrap script (creates GCS bucket, Workload Identity Federation)
./scripts/bootstrap-ci.sh <project_id> <github_owner/repo>

# 2. Add the secrets it prints to GitHub → Settings → Secrets
#    GCP_PROJECT_ID, GCP_WIF_PROVIDER, GCP_SERVICE_ACCOUNT, TF_STATE_BUCKET, GCP_ADMIN_EMAIL

# 3. Migrate local state to GCS
make migrate-state TF_STATE_BUCKET=<bucket_name>
```

See [DEVELOPING.md](DEVELOPING.md) for details on the CI architecture.

## Tear down

```bash
make destroy   # Destroys all GCP resources
```

See [DEVELOPING.md](DEVELOPING.md) for project structure, Terraform details, and how to add templates.
