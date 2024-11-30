variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the EKS cluster"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "intra_subnet_ids" {
  description = "Intra subnet IDs for control plane"
  type        = list(string)
}

variable "ami_type" {
  description = "The AMI type for the EKS managed node group."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "instance_types" {
  description = "The instance types for the EKS managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "cluster_version" {
  description = "The Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.31"
}