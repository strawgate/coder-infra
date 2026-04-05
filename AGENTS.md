# Agent Instructions

Instructions for AI coding agents working in this repository.

## Quick reference

- **Format:** `make fmt` (terraform fmt -recursive)
- **Validate:** `make validate`
- **Plan:** `make plan`
- **Structure:** see [DEVELOPING.md](DEVELOPING.md) for full layout

## Key files

| Area | Start here |
|------|-----------|
| Control plane VM | `control-plane/control_plane.tf` |
| Control plane variables | `control-plane/variables.tf` |
| VM bootstrap | `control-plane/startup.sh` |
| Workspace template | `workspace-templates/gcp-agent/main.tf` |
| Helper scripts | `scripts/connect.sh`, `scripts/ssh.sh` |

## Rules

### Security invariants

1. **No secrets in Terraform files.** All sensitive values go in `terraform.tfvars` (gitignored). Never hardcode project IDs, emails, API keys, or OAuth secrets.

2. **No public IPs.** Both the control plane and workspace VMs have no public IP. All access goes through IAP tunnel or Cloud NAT for outbound.

3. **IAP-only ingress.** Firewall rules allow only `35.235.240.0/20` (Google's IAP range). No `0.0.0.0/0` source ranges.

4. **Sensitive variables use `sensitive = true`.** Terraform variables containing secrets (API keys, OAuth secrets) must be marked sensitive.

### Patterns

- **Control plane vs workspace templates:** `control-plane/` is standard GCP Terraform. `workspace-templates/` uses the Coder Terraform provider — different lifecycle, different state.
- **Coder registry modules:** Use official modules from `registry.coder.com` for agent integrations. Don't hand-roll agent install scripts.
- **Persistent disks:** Workspace disks are separate resources with `prevent_destroy = false` and `ignore_changes = [image]` so they survive stop/start.
- **Spot VMs:** Workspace VMs use `preemptible = true` with `automatic_restart = false`.

### Style

- See [CODE_STYLE.md](CODE_STYLE.md) for Terraform formatting conventions
- Run `make fmt` before committing

### What not to do

- Do not add public IPs to any VM (`access_config` block)
- Do not open firewall rules to `0.0.0.0/0`
- Do not put secrets in `.tf` files — use `terraform.tfvars` (gitignored)
- Do not modify the control plane Terraform state from workspace templates
