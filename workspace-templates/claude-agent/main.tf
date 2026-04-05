terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.0"
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

# --- Parameters (prompted when creating a workspace) ---

data "coder_parameter" "project_id" {
  name        = "project_id"
  display_name = "GCP Project"
  type        = "string"
  description = "Google Cloud project ID"
  mutable     = false
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
  description  = "GitHub repo to clone (optional)"
  mutable      = true
}

# --- Workspace metadata ---

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  workspace_name = data.coder_workspace.me.name
}

# --- Persistent disk (survives stop/start) ---

resource "google_compute_disk" "workspace" {
  name  = "coder-${local.workspace_name}"
  zone  = data.coder_parameter.zone.value
  type  = "pd-balanced"
  size  = data.coder_parameter.disk_size_gb.value
  image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"

  lifecycle {
    # Don't destroy disk when workspace is merely stopped
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
    # Coder agent init script
    startup-script = coder_agent.main.init_script
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  scheduling {
    # Use spot pricing for cost savings (workspace can be preempted)
    preemptible       = true
    automatic_restart = false
  }

  tags = ["coder-workspace"]
}

# --- Coder agent ---

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  dir  = "/home/coder"

  display_apps {
    vscode          = true
    vscode_insiders = false
    web_terminal    = true
  }

  startup_script = <<-SCRIPT
    #!/bin/bash
    set -euo pipefail

    # Install Claude Code if not present
    if ! command -v claude &>/dev/null; then
      echo "Installing Claude Code..."
      curl -fsSL https://claude.ai/install.sh | sh
    fi

    # Clone repo if specified and directory doesn't exist
    REPO_URL="${data.coder_parameter.repo_url.value}"
    if [[ -n "$REPO_URL" ]]; then
      REPO_NAME=$(basename "$REPO_URL" .git)
      if [[ ! -d "/home/coder/$REPO_NAME" ]]; then
        git clone "$REPO_URL" "/home/coder/$REPO_NAME"
      fi
    fi
  SCRIPT

  startup_script_behavior = "blocking"
}

# --- Claude Code AI integration ---

resource "coder_app" "claude" {
  agent_id     = coder_agent.main.id
  slug         = "claude-code"
  display_name = "Claude Code"
  icon         = "https://claude.ai/favicon.ico"
  command      = "claude --ide"
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
