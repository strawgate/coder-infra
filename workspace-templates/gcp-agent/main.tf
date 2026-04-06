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
  project = data.coder_parameter.project_id.value != "" ? data.coder_parameter.project_id.value : "placeholder"
  region  = data.coder_parameter.region.value
  zone    = data.coder_parameter.zone.value
}

# --- Parameters ---

data "coder_parameter" "project_id" {
  name         = "project_id"
  display_name = "GCP Project"
  type         = "string"
  default      = "project-758068e8-e931-45df-ae8"
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
  default      = "e2-standard-2"
  description  = "VM size for the workspace"
  mutable      = true
  option {
    name  = "Small (0.5 vCPU, 2 GB)"
    value = "e2-small"
  }
  option {
    name  = "Medium (1 vCPU, 4 GB)"
    value = "e2-medium"
  }
  option {
    name  = "Standard (2 vCPU, 8 GB)"
    value = "e2-standard-2"
  }
  option {
    name  = "Large (4 vCPU, 16 GB)"
    value = "e2-standard-4"
  }
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
  display_name = "Repository"
  type         = "string"
  default      = "https://github.com/strawgate/memagent.git"
  description  = "GitHub repo to clone into the workspace"
  mutable      = true
  option {
    name  = "logfwd / memagent (Rust)"
    value = "https://github.com/strawgate/memagent.git"
  }
  option {
    name  = "octo11y (TypeScript)"
    value = "https://github.com/strawgate/octo11y.git"
  }
  option {
    name  = "None"
    value = ""
  }
}

data "coder_parameter" "agent" {
  name         = "agent"
  display_name = "AI Agent"
  type         = "string"
  default      = "copilot"
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

variable "github_token" {
  type        = string
  description = "GitHub PAT for Copilot (if not using Coder external auth)"
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

# --- Workspace presets (shown as options when creating Tasks) ---

data "coder_workspace_preset" "memagent" {
  name = "logfwd / memagent"
  parameters = {
    repo_url     = "https://github.com/strawgate/memagent.git"
    machine_type = "e2-standard-4"
  }
}

data "coder_workspace_preset" "octo11y" {
  name = "octo11y"
  parameters = {
    repo_url     = "https://github.com/strawgate/octo11y.git"
    machine_type = "e2-standard-2"
  }
}

data "coder_workspace_preset" "empty" {
  name = "Empty workspace"
  parameters = {
    repo_url     = ""
    machine_type = "e2-standard-2"
  }
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
  auth = "google-instance-identity"
  dir  = local.workdir
  env = {
    HOME         = "/root"
    PATH         = "/root/.cargo/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    GITHUB_TOKEN = var.github_token
    GH_TOKEN     = var.github_token
  }

  display_apps {
    vscode          = true
    vscode_insiders = false
    web_terminal    = true
  }

  startup_script = <<-SCRIPT
    #!/bin/bash
    export HOME="$${HOME:-/root}"
    set -euo pipefail

    # Install gh CLI if not present
    if ! command -v gh &>/dev/null; then
      echo "Installing GitHub CLI..."
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      sudo apt-get update -qq && sudo apt-get install -y -qq gh
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

    # Install build dependencies (needed for Cargo/Rust native compilation)
    if ! dpkg -s build-essential &>/dev/null 2>&1; then
      echo "Installing build dependencies..."
      sudo apt-get update -qq
      sudo apt-get install -y -qq build-essential pkg-config libssl-dev protobuf-compiler 2>/dev/null
    fi

    # Install language toolchains based on repo contents
    if [[ -f "${local.workdir}/Cargo.toml" ]] && ! command -v rustc &>/dev/null; then
      echo "Rust project detected — installing toolchain..."
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
      source "$${HOME}/.cargo/env"
      # Make cargo/rustc available to all shells (not just login shells)
      ln -sf /root/.cargo/bin/* /usr/local/bin/ 2>/dev/null || true
      echo "Rust $(rustc --version) installed"
    fi

    if [[ -f "${local.workdir}/justfile" ]] && ! command -v just &>/dev/null; then
      echo "Installing just..."
      cargo install just 2>/dev/null || curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin
      ln -sf /root/.cargo/bin/just /usr/local/bin/just 2>/dev/null || true
    fi

    if [[ -f "${local.workdir}/package.json" ]] && command -v npm &>/dev/null; then
      echo "Node.js project detected — installing dependencies..."
      cd "${local.workdir}" && npm ci --ignore-scripts 2>/dev/null || npm install --ignore-scripts
    fi
  SCRIPT

  startup_script_behavior = "non-blocking"
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

  agent_id         = coder_agent.main.id
  workdir          = local.workdir
  ai_prompt        = data.coder_task.me.prompt
  copilot_model    = "claude-sonnet-4.5"
  allow_all_tools  = true
  resume_session   = true
  github_token     = var.github_token
  external_auth_id = "primary-github"
  agentapi_version = "v0.12.1"
  copilot_version  = "1.0.18"

  trusted_directories = [local.workdir, "/tmp"]

  system_prompt = <<-EOT
    You are a helpful coding assistant that helps developers write, debug, and understand code.
    Provide clear explanations, follow best practices, and help solve coding problems efficiently.

    CRITICAL: You are running in a non-interactive automated environment.
    - NEVER ask the user clarifying questions or present selection menus
    - NEVER use the "Asking user" feature with multiple choice options
    - Always proceed autonomously with your best judgment
    - If a directory is empty, create the needed files directly
    - If instructions are ambiguous, pick the most reasonable interpretation and proceed

    CONTEXT: Before starting work, read AGENTS.md (or CLAUDE.md) in the project root for
    repo-specific conventions, build commands, and contribution guidelines.
    Also read DEVELOPING.md for build/test/lint instructions.
    Follow the project's existing patterns and style.

    TOOLS: You have `gh` CLI authenticated and available. Use it for all GitHub interactions
    (PRs, issues, comments, CI status). Prefer `gh` over raw API calls.

    ═══════════════════════════════════════════════════════════════
    PLAYBOOKS — When the user's prompt matches a playbook name,
    follow that playbook. The prompt may include extra context
    (PR number, repo, scope constraints) — incorporate it.
    ═══════════════════════════════════════════════════════════════

    ## PR Nurse
    Babysit an open pull request through to merge-ready. Steps:
    1. `gh pr checkout <number>` to get the branch
    2. Read the PR description and all review comments: `gh pr view <number>` and `gh pr reviews <number>`
    3. Address each reviewer comment:
       - Fix minor/non-controversial issues (typos, style, small bugs) directly
       - For major/controversial feedback, leave a reply explaining your reasoning — do NOT make large architectural changes
    4. Check CI status: `gh pr checks <number>`. If there are failures:
       - Read the failing logs
       - Fix small/obvious CI issues (lint, formatting, flaky-test retries)
       - Do NOT rewrite large test suites or change CI config substantially
    5. Rebase on the target branch if behind: `git fetch origin && git rebase origin/main`
    6. Push fixes: `git push`
    7. After all changes, run the project's test/lint suite locally to verify
    8. Summarize what you did and what still needs human review
    Constraints: Keep changes minimal. No feature work. No major refactors.
    Poll CI after pushing and fix any new failures (up to 3 rounds).

    ## Bug Hunt
    Proactively search for bugs in the codebase. Steps:
    1. Read AGENTS.md/DEVELOPING.md for build/test/lint instructions
    2. Run the full test suite and note any failures
    3. Run linters/clippy/type-checkers and note warnings
    4. Review recent commits (`git log --oneline -20`) for risky changes
    5. Look for common bug patterns: unwrap/panic in Rust, unhandled errors, race conditions, off-by-one, resource leaks
    6. For each bug found: describe it, assess severity, and create a fix
    7. Open a PR for each fix (or one PR if they're related): `gh pr create --title "..." --body "..."`
    8. Summarize all findings with severity ratings

    ## Audit README
    Review documentation as if you're a new contributor. Steps:
    1. Read README.md, DEVELOPING.md, AGENTS.md, CONTRIBUTING.md (if they exist)
    2. Try to follow the setup instructions literally — do they work?
    3. Check for: outdated commands, missing prerequisites, broken links, unclear steps
    4. Fix issues directly and open a PR
    5. Suggest improvements for unclear sections

    ## Code Review
    Deep-review a PR without making changes. Steps:
    1. `gh pr diff <number>` to read all changes
    2. Check for: security issues, performance problems, missing tests, style violations
    3. Read related code for context
    4. Post a thorough review: `gh pr review <number> --comment --body "..."`
    5. Be specific: reference file:line, suggest fixes, explain why

    ═══════════════════════════════════════════════════════════════
    If the prompt doesn't match a playbook, treat it as a freeform task.
    ═══════════════════════════════════════════════════════════════
  EOT

  mcp_config = jsonencode({
    mcpServers = {
      playwright = {
        command     = "npx"
        args        = ["-y", "@playwright/mcp@latest", "--headless", "--isolated"]
        description = "Browser automation for testing and previewing changes"
        name        = "Playwright"
        timeout     = 5000
        type        = "local"
        tools       = ["*"]
        trust       = false
      }
    }
  })

  pre_install_script = <<-EOT
    #!/bin/bash
    NODE_MAJOR=22
    if ! command -v node &>/dev/null || [[ "$(node -v | cut -d. -f1 | tr -d v)" -lt "$NODE_MAJOR" ]]; then
      echo "Installing Node.js $NODE_MAJOR via binary tarball..."
      NODE_VERSION=$(curl -fsSL "https://nodejs.org/dist/latest-v$${NODE_MAJOR}.x/SHASUMS256.txt" | grep 'linux-x64.tar.xz' | awk '{print $2}' | sed 's/node-\(v[0-9.]*\)-.*/\1/')
      curl -fsSL "https://nodejs.org/dist/$${NODE_VERSION}/node-$${NODE_VERSION}-linux-x64.tar.xz" | sudo tar -xJf - -C /usr/local --strip-components=1
      echo "Node.js $(node -v) installed with npm $(npm -v)"
    else
      echo "Node.js $(node -v) already installed"
    fi
  EOT
}

