output "gateway_public_ip" {
  value = google_compute_instance.gateway.network_interface[0].access_config[0].nat_ip
}
output "gateway_private_ip" {
  value = google_compute_instance.gateway.network_interface[0].network_ip
}
output "api_endpoint" {
  value = "http://${google_compute_instance.gateway.network_interface[0].access_config[0].nat_ip}:3111"
}
