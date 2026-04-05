output "instance_name" {
  description = "Name of the Coder control plane VM"
  value       = google_compute_instance.coder.name
}

output "instance_zone" {
  description = "Zone of the Coder control plane VM"
  value       = google_compute_instance.coder.zone
}

output "service_account_email" {
  description = "Service account email used by the control plane"
  value       = google_service_account.coder.email
}

output "connect_command" {
  description = "Command to open IAP tunnel to Coder"
  value       = "gcloud compute start-iap-tunnel ${google_compute_instance.coder.name} 3000 --local-host-port=localhost:3000 --zone=${google_compute_instance.coder.zone}"
}

output "ssh_command" {
  description = "Command to SSH into the control plane via IAP"
  value       = "gcloud compute ssh ${google_compute_instance.coder.name} --zone=${google_compute_instance.coder.zone} --tunnel-through-iap"
}
