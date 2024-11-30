module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }

  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = var.intra_subnet_ids

  eks_managed_node_groups = {
    karpenter = {
      ami_type       = var.ami_type
      instance_types = var.instance_types

      min_size     = 1
      max_size     = 3
      desired_size = 2

      capacity_type = "SPOT"
      
      taints = {
        addons = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        },
      }
    }
  }

  enable_cluster_creator_admin_permissions = true

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}