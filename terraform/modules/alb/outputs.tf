# modules/alb/outputs.tf

output "iam_role_arn" {
  description = "ARN of the IAM role created for the ALB Controller"
  value       = module.lb_controller_role.iam_role_arn
}

output "iam_policy_arn" {
  description = "ARN of the IAM policy created for the ALB Controller"
  value       = aws_iam_policy.alb_controller.arn
}

output "helm_release_name" {
  description = "Name of the ALB Controller Helm release"
  value       = helm_release.aws_load_balancer_controller.name
}

output "status" {
  value = "ready"
}
