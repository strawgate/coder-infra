# coder-infra

Coder-on-GCP infrastructure for AI agent dev environments. Terraform + shell scripts to spin up a self-hosted [Coder](https://coder.com) instance behind a GCP IAP tunnel with zero public IP exposure.

## Architecture

```
┌─────────────────┐      IAP tunnel       ┌─────────────────────┐
│  Your laptop    │ ───────────────────── │  e2-micro (free)    │
│  localhost:3000 │                        │  Coder control plane│
└─────────────────┘                        │  No public IP       │
                                           └────────┬────────────┘
                                                    │ Internal VPC
                                    ┌───────────────┼───────────────┐
                                    │               │               │
                              ┌─────┴─────┐   ┌────┴──────┐  ┌────┴──────┐
                              │ workspace │   │ workspace │  │ workspace │
                              │ e2-small  │   │ e2-small  │  │ e2-small  │
                              │ Claude    │   │ Claude    │  │ Claude    │
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

## Quick start

### Prerequisites

- [Terraform](https://terraform.io) >= 1.5
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) authenticated (`gcloud auth login`)
- A GCP project with billing enabled

### Setup

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
```

### Daily usage

```bash
make connect   # Open tunnel → http://localhost:3000
make stop      # Stop the VM (save compute, disk persists)
make start     # Start it back up
make ssh       # SSH into the control plane
```

### Tear down

```bash
make destroy   # Destroys all GCP resources
```

## Repo structure

```
coder-infra/
├── control-plane/             # Terraform for the Coder server VM
│   ├── main.tf                # Provider config
│   ├── control_plane.tf       # VM, firewall, IAM, service accounts
│   ├── variables.tf           # Input variables
│   ├── outputs.tf             # Connection commands and metadata
│   ├── startup.sh             # VM bootstrap (installs Coder)
│   └── terraform.tfvars.example
├── workspace-templates/       # Coder workspace templates
│   └── claude-agent/          # GCP VM with Claude Code
│       └── main.tf
├── scripts/                   # Helper scripts
│   ├── connect.sh             # Open IAP tunnel
│   ├── ssh.sh                 # SSH via IAP
│   ├── start.sh               # Start the VM
│   └── stop.sh                # Stop the VM
├── Makefile                   # Top-level commands
└── README.md
```

## Workspace template

The `claude-agent` template creates:
- An **e2-small** GCP VM (spot pricing) with no public IP
- A **persistent 50 GB disk** that survives stop/start
- **Claude Code** pre-installed
- Optional **repo clone** on first start

To add the template to Coder, push it via the dashboard or CLI:

```bash
# After connecting to Coder
coder templates push claude-agent --directory workspace-templates/claude-agent
```

## Swapping access method

The IAP tunnel works with zero cost but requires `gcloud` on every client. If you later want browser-native access, swap to one of:

- **Tailscale** — 2 commands, free, mesh VPN (no public URL)
- **Cloudflare Tunnel + Access** — free, public URL with Google OAuth
- **GCP HTTPS LB + IAP** — $18/mo, native Google SSO

No changes needed on the Coder side — just update the firewall and `CODER_ACCESS_URL`.
