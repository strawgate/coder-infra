# --- Service account for the Coder control plane ---
resource "google_service_account" "coder" {
  account_id   = "coder-server"
  display_name = "Coder control plane"
}

# The control plane needs to create/manage workspace VMs
resource "google_project_iam_member" "coder_compute" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.coder.email}"
}

resource "google_project_iam_member" "coder_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.coder.email}"
}

# --- Persistent data disk (survives VM recreates) ---
resource "google_compute_disk" "coder_data" {
  name = "coder-data"
  zone = var.zone
  type = "pd-standard"
  size = var.data_disk_size_gb

  lifecycle {
    prevent_destroy = true
  }
}

# --- Control plane VM ---
resource "google_compute_instance" "coder" {
  name         = "coder-server"
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["coder-server"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = var.boot_disk_size_gb
      type  = "pd-standard"
    }
  }

  attached_disk {
    source      = google_compute_disk.coder_data.self_link
    device_name = "coder-data"
  }

  network_interface {
    network = "default"
    # No access_config = no public IP
  }

  service_account {
    email  = google_service_account.coder.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/startup.sh", {
    coder_version              = var.coder_version
    coder_admin_email          = var.coder_admin_email != "" ? var.coder_admin_email : var.admin_email
    coder_admin_password       = var.coder_admin_password
    github_oauth_client_id     = var.github_oauth_client_id
    github_oauth_client_secret = var.github_oauth_client_secret
  })

  # Allow the VM to be stopped/started without recreating
  allow_stopping_for_update = true
}

# --- Firewall: IAP tunnel traffic only ---
resource "google_compute_firewall" "allow_iap" {
  name    = "allow-iap-to-coder"
  network = "default"

  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["22", "3000"]
  }

  # Google's IAP tunnel IP range
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["coder-server"]
}

# --- Firewall: IAP tunnel to workspace VMs (shared across all workspaces) ---
resource "google_compute_firewall" "allow_iap_workspaces" {
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

# --- IAP access for admin ---
resource "google_project_iam_member" "iap_tunnel" {
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "user:${var.admin_email}"
}

# --- Enable required APIs ---
resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iap" {
  service            = "iap.googleapis.com"
  disable_on_destroy = false
}

# --- Cloud NAT (gives VMs with no public IP internet access) ---
resource "google_compute_router" "coder" {
  name    = "coder-router"
  network = "default"
  region  = var.region
}

resource "google_compute_router_nat" "coder" {
  name                               = "coder-nat"
  router                             = google_compute_router.coder.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
