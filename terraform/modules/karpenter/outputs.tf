# modules/karpenter/outputs.tf

output "node_iam_role_name" {
  description = "Name of the IAM role created for Karpenter nodes"
  value       = module.karpenter.node_iam_role_name
}

output "service_account" {
  description = "Name of the Karpenter service account"
  value       = module.karpenter.service_account
}

output "queue_name" {
  description = "Name of the Karpenter interruption queue"
  value       = module.karpenter.queue_name
}

output "karpenter_node_role" {
  value = module.karpenter.node_iam_role_name
}

