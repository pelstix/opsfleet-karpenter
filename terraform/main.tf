###############################################################################
# Provider
###############################################################################
provider "aws" {
    region              = var.region
}

provider "aws" {
    region = "us-east-1"
    alias  = "virginia"
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}


terraform {
  backend "s3" {
    bucket         = "pelumi-opsfleet-state"  # Replace with your S3 bucket name
    key            = "eks-cluster/terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

# Data source to fetch available instance types for X86 (AMD64)
data "aws_ec2_instance_types" "x86_compatible" {
  filter {
    name   = "processor-info.supported-architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "memory-info.size-in-mib"
    values = ["1024", "2048", "4096"]  # At least 1GB memory
  }

  filter {
    name   = "vcpu-info.default-vcpus"
    values = ["1", "2", "4", "8"]
  }


  filter {
    name   = "instance-type"
    values = [
      "*.nano", 
      "*.micro", 
      "*.small", 
      "*.medium", 
      "*.large", 
      "*.xlarge", 
      "c*", 
      "m*", 
      "r*"
    ]
  }
}

# Data source to fetch available ARM64 (Graviton) instance types
data "aws_ec2_instance_types" "arm64_compatible" {
  filter {
    name   = "processor-info.supported-architecture"
    values = ["arm64"]
  }

  filter {
    name   = "memory-info.size-in-mib"
    values = ["1024", "2048", "4096"]  # At least 1GB memory
  }

  filter {
    name   = "vcpu-info.default-vcpus"
    values = ["1", "2", "4", "8"]
  }

  # Exclude specialized or extremely large instances
  filter {
    name   = "instance-type"
    values = [
      "*.nano", 
      "*.micro", 
      "*.small", 
      "*.medium", 
      "*.large", 
      "*.xlarge", 
      "c*", 
      "m*", 
      "r*"
    ]
  }
}

# Function to select instance types that match deployment requirements
locals {
  # Filter and sort instance types by size and performance
  x86_instance_types = [for t in data.aws_ec2_instance_types.x86_compatible.instance_types : t 
    if can(regex("^[mcr]\\d+\\.", t)) || 
       can(regex("^[mcr]\\d+a\\.", t)) || 
       can(regex("^[mcr]\\d+i\\.", t))
  ]

  arm64_instance_types = [for t in data.aws_ec2_instance_types.arm64_compatible.instance_types : t 
    if can(regex("^[mcr]\\d+g\\.", t))
  ]

  # Select a range of instance types from small to large
  x86_deployment_instance_types = slice(
    sort(local.x86_instance_types), 
    0, 
    min(length(local.x86_instance_types), 5)  # Select up to 5 instance types
  )

  arm64_deployment_instance_types = slice(
    sort(local.arm64_instance_types), 
    0, 
    min(length(local.arm64_instance_types), 5)  # Select up to 5 instance types
  )
}

###############################################################################
# Data Sources
###############################################################################
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

###############################################################################
# VPC
###############################################################################
# VPC Data Source

data "aws_vpc" "existing" {
  filter {
    name   = "tag:Name"
    values = ["Opsfleet-vpc"]
  }
}


# Public Subnets
resource "aws_subnet" "public_subnets" {
  count             = 3
  vpc_id            = data.aws_vpc.existing.id
  cidr_block        = cidrsubnet(data.aws_vpc.existing.cidr_block, 8, 101 + count.index)
  availability_zone = "${var.region}${["a", "b", "c"][count.index]}"

  tags = {
    Name                     = "${var.cluster_name}-public-subnet-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}

# Private Subnets
resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = data.aws_vpc.existing.id
  cidr_block        = cidrsubnet(data.aws_vpc.existing.cidr_block, 8, 1 + count.index)
  availability_zone = "${var.region}${["a", "b", "c"][count.index]}"

  tags = {
    Name                              = "${var.cluster_name}-private-subnet-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.cluster_name
  }
}

# Intra Subnets
resource "aws_subnet" "intra_subnets" {
  count             = 3
  vpc_id            = data.aws_vpc.existing.id
  cidr_block        = cidrsubnet(data.aws_vpc.existing.cidr_block, 8, 104 + count.index)
  availability_zone = "${var.region}${["a", "b", "c"][count.index]}"

  tags = {
    Name = "${var.cluster_name}-intra-subnet-${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = data.aws_vpc.existing.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-eip"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnets[0].id

  tags = {
    Name = "${var.cluster_name}-nat-gw"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = data.aws_vpc.existing.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

# Public Subnet Route Table Association
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = data.aws_vpc.existing.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt"
  }
}

# Private Subnet Route Table Association
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private.id
}
###############################################################################
# EKS
###############################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.31"

  cluster_endpoint_public_access  = true

  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }

  vpc_id                   = data.aws_vpc.existing.id
  subnet_ids               = aws_subnet.private_subnets[*].id
  control_plane_subnet_ids = aws_subnet.intra_subnets[*].id

  eks_managed_node_groups = {
    karpenter = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]

      min_size     = 1
      max_size     = 3
      desired_size = 2

      capacity_type = "SPOT"
      
      taints = {
        # This Taint aims to keep just EKS Addons and Karpenter running on this MNG
        # The pods that do not tolerate this taint should run on nodes created by Karpenter
        addons = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        },
      }
    }
  }

  # Cluster access entry
  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true

  node_security_group_tags = {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = var.cluster_name
  }
}

###############################################################################
# Karpenter
###############################################################################
module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  cluster_name = module.eks.cluster_name

  enable_v1_permissions = true

  enable_pod_identity             = true
  create_pod_identity_association = true

  # Attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

###############################################################################
# Karpenter Helm
###############################################################################
resource "helm_release" "karpenter" {
  namespace           = "kube-system"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "1.0.0"
  wait                = false

  values = [
    <<-EOT
    serviceAccount:
      name: ${module.karpenter.service_account}
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]
}

###############################################################################
# Karpenter Kubectl
###############################################################################
# X86 Spot NodePool with flexible instance types
resource "kubectl_manifest" "karpenter_x86_spot_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1beta1
    kind: NodePool
    metadata:
      name: x86-spot
    spec:
      template:
        spec:
          nodeClassRef:
            name: x86-spot
          requirements:
            - key: "topology.kubernetes.io/region"
              operator: In
              values: ["${var.region}"]
            - key: "kubernetes.io/arch"
              operator: In
              values: ["amd64"]
            - key: "node.kubernetes.io/instance-type"
              operator: In
              values: [${join(",", formatlist("\"%s\"", local.x86_deployment_instance_types))}]
            - key: "karpenter.sh/capacity-type"
              operator: In
              values: ["spot"]
      limits:
        cpu: 1000
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 30s
  YAML

  depends_on = [kubectl_manifest.karpenter_x86_spot_node_class]
}

# Graviton Spot NodePool with flexible instance types
resource "kubectl_manifest" "karpenter_graviton_spot_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1beta1
    kind: NodePool
    metadata:
      name: graviton-spot
    spec:
      template:
        spec:
          nodeClassRef:
            name: graviton-spot
          requirements:
            - key: "topology.kubernetes.io/region"
              operator: In
              values: ["${var.region}"]
            - key: "kubernetes.io/arch"
              operator: In
              values: ["arm64"]
            - key: "node.kubernetes.io/instance-type"
              operator: In
              values: [${join(",", formatlist("\"%s\"", local.arm64_deployment_instance_types))}]
            - key: "karpenter.sh/capacity-type"
              operator: In
              values: ["spot"]
      limits:
        cpu: 1000
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 30s
  YAML

  depends_on = [kubectl_manifest.karpenter_graviton_spot_node_class]
}

# Existing Node Class resources remain the same
resource "kubectl_manifest" "karpenter_x86_spot_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1beta1
    kind: EC2NodeClass
    metadata:
      name: x86-spot
    spec:
      amiFamily: AL2023
      role: ${module.karpenter.node_iam_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
      spotMarketOptions:
        maxPrice: 0.1
  YAML

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "karpenter_graviton_spot_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1beta1
    kind: EC2NodeClass
    metadata:
      name: graviton-spot
    spec:
      amiFamily: AL2023
      role: ${module.karpenter.node_iam_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
      spotMarketOptions:
        maxPrice: 0.1
  YAML

  depends_on = [helm_release.karpenter]
}