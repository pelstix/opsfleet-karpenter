variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  type        = string
}

variable "chart_version" {
  description = "Version of the ArgoCD Helm chart"
  type        = string
  default     = "6.7.3"
}

variable "cluster_certificate_authority_data" {
  description = "Endpoint of the EKS cluster"
  type        = string
}

variable "karpenter_node_role" {
  description = "Ops"
  type        = string
}


