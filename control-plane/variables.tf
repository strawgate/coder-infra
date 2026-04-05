variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region (must be us-central1, us-west1, or us-east1 for free tier)"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "machine_type" {
  description = "Machine type for control plane (e2-micro = free tier)"
  type        = string
  default     = "e2-micro"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB (max 30 for free tier with pd-standard)"
  type        = number
  default     = 30
}

variable "admin_email" {
  description = "Your Google account email for IAP access"
  type        = string
}

variable "coder_version" {
  description = "Coder version to install (empty = latest)"
  type        = string
  default     = ""
}

variable "github_oauth_client_id" {
  description = "GitHub OAuth App client ID for external auth (git operations in workspaces)"
  type        = string
  default     = ""
}

variable "github_oauth_client_secret" {
  description = "GitHub OAuth App client secret"
  type        = string
  sensitive   = true
  default     = ""
}
