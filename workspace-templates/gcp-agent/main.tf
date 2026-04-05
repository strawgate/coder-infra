terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "coder" {}

provider "google" {
  project = data.coder_parameter.project_id.value
  region  = data.coder_parameter.region.value
  zone    = data.coder_parameter.zone.value
}

# --- Parameters ---

data "coder_parameter" "project_id" {
  name         = "project_id"
  display_name = "GCP Project"
  type         = "string"
  description  = "Google Cloud project ID"
  mutable      = false
}

data "coder_parameter" "region" {
  name         = "region"
  display_name = "Region"
  type         = "string"
  default      = "us-central1"
  mutable      = false
}

data "coder_parameter" "zone" {
  name         = "zone"
  display_name = "Zone"
  type         = "string"
  default      = "us-central1-a"
  mutable      = false
}

data "coder_parameter" "machine_type" {
  name         = "machine_type"
  display_name = "Machine type"
  type         = "string"
  default      = "e2-small"
  description  = "e2-small (2 vCPU, 2 GB) or e2-medium (2 vCPU, 4 GB)"
  mutable      = true
}

data "coder_parameter" "disk_size_gb" {
  name         = "disk_size_gb"
  display_name = "Disk size (GB)"
  type         = "number"
  default      = 50
  mutable      = true
}

data "coder_parameter" "repo_url" {
  name         = "repo_url"
  display_name = "Repository URL"
  type         = "string"
  default      = ""
  description  = "GitHub repo to clone (optional, HTTPS)"
  mutable      = true
}

data "coder_parameter" "agent" {
  name         = "agent"
  display_name = "AI Agent"
  type         = "string"
  default      = "claude"
  description  = "Which AI agent to run"
  mutable      = false
  option {
    name  = "Claude Code"
    value = "claude"
  }
  option {
    name  = "GitHub Copilot"
    value = "copilot"
  }
}

variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key (required for Claude Code agent)"
  sensitive   = true
  default     = ""
}

# --- Workspace metadata ---

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  workspace_name = data.coder_workspace.me.name
  use_claude     = data.coder_parameter.agent.value == "claude"
  use_copilot    = data.coder_parameter.agent.value == "copilot"
  workdir        = "/home/coder/project"
}

# --- Tasks integration ---

data "coder_task" "me" {}

resource "coder_ai_task" "claude" {
  count  = local.use_claude ? data.coder_workspace.me.start_count : 0
  app_id = module.claude-code[0].task_app_id
}

resource "coder_ai_task" "copilot" {
  count  = local.use_copilot ? data.coder_workspace.me.start_count : 0
  app_id = module.copilot[0].task_app_id
}

# --- Persistent disk (survives stop/start) ---

resource "google_compute_disk" "workspace" {
  name  = "coder-${local.workspace_name}"
  zone  = data.coder_parameter.zone.value
  type  = "pd-balanced"
  size  = data.coder_parameter.disk_size_gb.value
  image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"

  lifecycle {
    prevent_destroy = false
    ignore_changes  = [image]
  }
}

# --- Compute instance (created on start, destroyed on stop) ---

resource "google_compute_instance" "workspace" {
  count = data.coder_workspace.me.start_count

  name         = "coder-${local.workspace_name}"
  machine_type = data.coder_parameter.machine_type.value
  zone         = data.coder_parameter.zone.value

  boot_disk {
    source      = google_compute_disk.workspace.self_link
    auto_delete = false
  }

  network_interface {
    network = "default"
    # No public IP — communicates with control plane over internal VPC
  }

  metadata = {
    startup-script = coder_agent.main.init_script
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  scheduling {
    preemptible       = true
    automatic_restart = false
  }

  tags = ["coder-workspace"]
}

# --- Coder agent ---

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  dir  = local.workdir

  display_apps {
    vscode          = true
    vscode_insiders = false
    web_terminal    = true
  }

  startup_script = <<-SCRIPT
    #!/bin/bash
    set -euo pipefail

    # Ensure Node.js 22+ is available (needed for Copilot CLI)
    if ! command -v node &>/dev/null || [[ "$(node -v | cut -d. -f1 | tr -d v)" -lt 22 ]]; then
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
      sudo apt-get install -y nodejs
    fi

    # Clone repo if specified and directory doesn't exist
    REPO_URL="${data.coder_parameter.repo_url.value}"
    if [[ -n "$REPO_URL" ]]; then
      if [[ ! -d "${local.workdir}" ]] || [[ -z "$(ls -A ${local.workdir} 2>/dev/null)" ]]; then
        git clone "$REPO_URL" "${local.workdir}"
      fi
    else
      mkdir -p "${local.workdir}"
    fi
  SCRIPT

  startup_script_behavior = "blocking"
}

# --- Claude Code (official module) ---

module "claude-code" {
  count   = local.use_claude ? 1 : 0
  source  = "registry.coder.com/coder/claude-code/coder"
  version = "4.9.1"

  agent_id       = coder_agent.main.id
  workdir        = local.workdir
  claude_api_key = var.anthropic_api_key
  ai_prompt      = data.coder_task.me.prompt
  model          = "sonnet"
}

# --- GitHub Copilot CLI (official module) ---

module "copilot" {
  count   = local.use_copilot ? 1 : 0
  source  = "registry.coder.com/coder-labs/copilot/coder"
  version = "0.4.0"

  agent_id        = coder_agent.main.id
  workdir         = local.workdir
  ai_prompt       = data.coder_task.me.prompt
  copilot_model   = "claude-sonnet-4.5"
  allow_all_tools = true
  resume_session  = true
}

# --- Firewall for workspace VMs ---

resource "google_compute_firewall" "workspace_iap" {
  name    = "allow-iap-to-workspaces"
  network = "default"

  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["coder-workspace"]
}
