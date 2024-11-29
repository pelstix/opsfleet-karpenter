module "data_sources" {
  source = "./modules/data-sources"
  region = var.region
}

module "networking" {
  source = "./modules/networking"
  
  cluster_name = var.cluster_name
  region       = var.region
  vpc_id       = module.data_sources.existing_vpc_id
  vpc_cidr     = module.data_sources.existing_vpc_cidr

}

module "eks" {
  source = "./modules/eks"
  
  cluster_name    = var.cluster_name
  vpc_id          = module.data_sources.existing_vpc_id
  subnet_ids      = module.networking.private_subnet_ids
  intra_subnet_ids = module.networking.intra_subnet_ids
  depends_on           = [module.networking]

}

module "karpenter" {
  source = "./modules/karpenter"


  cluster_name           = module.eks.cluster_name
  cluster_endpoint       = module.eks.cluster_endpoint
  node_iam_role_name     = module.eks.node_iam_role_name
  ecr_username       = module.data_sources.ecr_token_username
  ecr_password       = module.data_sources.ecr_token_password
  cluster_certificate_authority_data = module.eks.cluster_certificate_authority_data
  
  x86_deployment_types   = module.data_sources.x86_deployment_instance_types
  arm64_deployment_types = module.data_sources.arm64_deployment_instance_types
  
}

module "alb" {
  source = "./modules/alb"
  
  cluster_name    = module.eks.cluster_name
  vpc_id         = module.data_sources.existing_vpc_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  depends_on          = [module.eks, module.networking, module.karpenter]

}


module "argocd" {
  source = "./modules/argocd"


  cluster_certificate_authority_data = module.eks.cluster_certificate_authority_data
  cluster_name = module.eks.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint

  karpenter_node_role = module.karpenter.karpenter_node_role

  
}

module "monitoring" {
  source = "./modules/monitoring"
  depends_on = [module.eks, module.karpenter, module.alb]
}