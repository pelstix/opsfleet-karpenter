output "prometheus_namespace" {
  description = "Namespace where Prometheus is deployed"
  value       = "monitoring"
}

output "grafana_namespace" {
  description = "Namespace where Grafana is deployed"
  value       = "monitoring"
}

output "grafana_admin_password" {
  description = "Admin password for Grafana"
  value       = "admin123"
  sensitive   = true
}