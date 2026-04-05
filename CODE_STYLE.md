# Code Style

Terraform and HCL style preferences for code reviewers. `terraform fmt` handles formatting — this file covers what formatters can't catch.

## Resource naming

- **Resource names:** lowercase with underscores: `google_compute_instance.coder`, `google_compute_firewall.allow_iap`
- **GCP resource names:** lowercase with hyphens: `coder-server`, `coder-nat`, `allow-iap-to-coder`
- **Variables:** lowercase with underscores: `project_id`, `boot_disk_size_gb`
- **Locals:** lowercase with underscores: `workspace_name`, `use_claude`

## File organization

- One `.tf` file per logical group (provider config, resources, variables, outputs)
- Use `# --- Section Name ---` comments to separate resource groups within a file
- Keep `variables.tf` in the same order as they appear in `terraform.tfvars.example`

## Variables

- Always include `description`
- Use `default` for optional variables, omit for required ones
- Mark secrets with `sensitive = true`
- Group related variables (region/zone, OAuth client ID/secret)

## Comments

- Explain *why* a resource exists or has a particular configuration
- Inline comments for non-obvious values (e.g., `# Google's IAP tunnel IP range`)
- Skip comments on self-explanatory resources

## Workspace templates

- Parameters use `data "coder_parameter"` — keep them at the top of the file
- Separate workspace resources (disk, VM) from Coder resources (agent, modules)
- Use `locals {}` for computed values shared across resources
- Use conditional `count` for optional resources (e.g., `local.use_claude ? 1 : 0`)
