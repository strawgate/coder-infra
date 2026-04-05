# Handoff: coder-infra next steps

Status as of April 5, 2026. This document captures what's done, what's running, and what remains.

## What exists

### Live infrastructure

- **Coder v2.31.7** running on an e2-micro VM in `us-central1-a`
- **GCP project:** `project-758068e8-e931-45df-ae8`
- **Admin account:** `partners@strawgate.com` (first user = owner)
- **Access:** IAP tunnel only — no public IP, no load balancer
- **Cloud NAT** provides outbound internet for VMs without public IPs
- **10 Terraform-managed resources** in `control-plane/` (VM, service account, 2 IAM bindings, firewall, 2 API enables, Cloud Router, Cloud NAT)

### Registered template

- **`gcp-agent`** template is pushed and active in Coder (0 workspaces created so far)
- Supports **Claude Code** (`coder/claude-code` v4.9.1) and **GitHub Copilot** (`coder-labs/copilot` v0.4.0) via parameter selection
- Tasks integration (`coder_ai_task` + `data.coder_task`) for Coder's task queue UI
- Workspace VMs: spot e2-small, persistent pd-balanced disk, no public IP

### Connectivity

To access Coder:
```bash
make connect   # Opens IAP tunnel → http://localhost:3000
```

To SSH into the control plane:
```bash
make ssh
```

Coder CLI was authenticated locally (v2.30.6, installed at `~/Documents/repos/coder-infra/coder-cli` but gitignored — re-download if needed from https://github.com/coder/coder/releases).

## What's NOT done

### 1. Test creating a workspace (high priority)

Nobody has actually created a workspace yet. The template is registered but untested end-to-end.

```bash
# Via CLI (after make connect):
coder create test-workspace --template gcp-agent

# Or use the dashboard at http://localhost:3000
```

**What to verify:**
- Workspace VM comes up (spot e2-small)
- Persistent disk is created and attached
- Agent startup script runs (Node.js 22 install, optional repo clone)
- Claude Code or Copilot module initializes correctly
- Tasks tab shows in the UI
- Workspace stop/start preserves disk

**Likely issues:**
- The `anthropic_api_key` template variable needs to be set for Claude Code to work. Set it in the template settings or via `coder templates push` with `-var 'anthropic_api_key=sk-...'`
- Workspace VMs need the same Cloud NAT for outbound internet (they're in the same VPC, so this should work — but verify)

### 2. GitHub external auth (medium priority)

Workspace agents can't authenticate with GitHub yet. Needed for cloning private repos and pushing branches.

**Steps:**
1. Create a GitHub OAuth App at https://github.com/settings/applications/new
   - **Application name:** `Coder - AI Agents`
   - **Homepage URL:** `http://localhost:3000`
   - **Callback URL:** `http://localhost:3000/external-auth/primary-github/callback`
2. Add to `control-plane/terraform.tfvars`:
   ```hcl
   github_oauth_client_id     = "Ov23li..."
   github_oauth_client_secret = "your-secret"
   ```
3. Re-apply: `make apply` (this adds a systemd drop-in to `/etc/systemd/system/coder.service.d/github-auth.conf` via startup.sh)
4. Restart Coder on the VM: `make ssh` then `sudo systemctl restart coder`
5. Verify: Go to Coder Settings → External Auth and confirm GitHub shows up

**Note:** The callback URL uses `localhost:3000` because access is via IAP tunnel. If you switch to a public URL later, update both the OAuth App callback and `CODER_ACCESS_URL`.

### 3. Anthropic API key for Claude Code (medium priority)

The template has a `variable "anthropic_api_key"` but it's not being populated. Options:
- Set it as a Coder template variable: Coder dashboard → Templates → gcp-agent → Settings → Variables
- Or pass via CLI: `coder templates push gcp-agent --directory workspace-templates/gcp-agent --var 'anthropic_api_key=sk-...'`

### 4. terraform.tfvars.example is stale (low priority)

The example file may not include all current variables. Verify it matches `variables.tf` and add any missing examples:
```hcl
project_id                 = "my-gcp-project"
admin_email                = "me@example.com"
region                     = "us-central1"
zone                       = "us-central1-a"
# github_oauth_client_id   = ""
# github_oauth_client_secret = ""
```

### 5. Coder version pinning (low priority)

Coder was installed as v2.31.7 manually on the VM. The startup.sh uses `curl -fsSL https://coder.com/install.sh | sh` which grabs latest. Consider:
- Setting `coder_version` in tfvars to pin it
- The startup.sh already accepts a `coder_version` templatefile variable but the install script path doesn't use it yet — the version param is logged but not passed to the install command

### 6. Backup / disaster recovery (low priority)

- Terraform state is local only (`control-plane/terraform.tfstate`). Not in git (gitignored). If the laptop is lost, state is gone.
- Options: Add a GCS backend for remote state, or periodically copy tfstate to a secure location.
- The VM boot disk is not snapshotted. Coder uses SQLite by default — if the VM disk is lost, all workspace configs and user data are gone.

## Known quirks

1. **Terraform ADC permissions:** `gcloud auth application-default login` may not have `serviceusage.services.use`. Workaround: prefix Terraform commands with `GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)`.

2. **Startup script didn't fully run initially:** The VM was created before Cloud NAT existed, so `curl` in the startup script hung. Coder was installed manually via SSH. On a fresh deploy (with NAT already in place), the startup script should work end-to-end.

3. **Google provider placeholder:** The workspace template uses `project_id != "" ? project_id : "placeholder"` in the Google provider block because Coder validates templates during import with empty parameter values. This is expected.

4. **Coder CLI version mismatch:** Local CLI is v2.30.6, server is v2.31.7. Should work fine for basic operations but consider upgrading the local CLI if you hit issues.

## Repo structure

```
coder-infra/
├── control-plane/           # Terraform for the Coder server VM
│   ├── main.tf              # Provider config
│   ├── control_plane.tf     # All GCP resources (10 total)
│   ├── variables.tf         # Input variables
│   ├── outputs.tf           # Connection commands
│   ├── startup.sh           # VM bootstrap (templatefile)
│   └── terraform.tfvars     # Local secrets (gitignored)
├── workspace-templates/
│   └── gcp-agent/main.tf    # Coder template (Claude + Copilot)
├── scripts/                 # connect.sh, ssh.sh, start.sh, stop.sh
├── Makefile                 # plan, apply, destroy, connect, ssh, start, stop
├── DEVELOPING.md            # Full dev docs
├── AGENTS.md                # Agent rules (security invariants)
├── CODE_STYLE.md            # HCL conventions
└── README.md                # User-facing quick start
```
