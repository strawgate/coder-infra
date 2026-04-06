packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = ">= 1.1.0"
    }
  }
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "image_family" {
  type    = string
  default = "coder-workspace"
}

source "googlecompute" "workspace" {
  project_id          = var.project_id
  zone                = var.zone
  source_image_family = "ubuntu-2404-lts-amd64"
  source_image_project_id = ["ubuntu-os-cloud"]
  machine_type        = "e2-medium"
  image_name          = "coder-workspace-{{timestamp}}"
  image_family        = var.image_family
  image_description   = "Coder workspace image with Node.js 22, git, and common tools"
  disk_size           = 20
  disk_type           = "pd-ssd"
  ssh_username        = "packer"
  tags                = ["packer"]
  omit_external_ip    = false
  use_iap             = true
}

build {
  sources = ["source.googlecompute.workspace"]

  # System updates
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y",
    ]
  }

  # Node.js 22 (needed for Copilot CLI)
  provisioner "shell" {
    inline = [
      "NODE_VERSION=$(curl -fsSL 'https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt' | grep 'linux-x64.tar.xz' | awk '{print $2}' | sed 's/node-\\(v[0-9.]*\\)-.*/\\1/')",
      "curl -fsSL \"https://nodejs.org/dist/$${NODE_VERSION}/node-$${NODE_VERSION}-linux-x64.tar.xz\" | sudo tar -xJf - -C /usr/local --strip-components=1",
      "node --version",
      "npm --version",
    ]
  }

  # Common development tools
  provisioner "shell" {
    inline = [
      "sudo apt-get install -y git curl wget unzip jq build-essential",
    ]
  }

  # Clean up apt cache to shrink image
  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
    ]
  }
}
