variable "region" {
    type = string
    default = "eu-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  type        = string
}

variable "node_iam_role_name" {
  description = "IAM role name for nodes"
  type        = string
}

variable "x86_deployment_types" {
  description = "List of X86 instance types for deployment"
  type        = list(string)
}

variable "arm64_deployment_types" {
  description = "List of ARM64 instance types for deployment"
  type        = list(string)
}

variable "ecr_username" {
  description = "ECR public registry username"
  type        = string
}

variable "ecr_password" {
  description = "ECR public registry password"
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Endpoint of the EKS cluster"
  type        = string
}

