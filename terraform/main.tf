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
    bucket         = "pelumi-opsfleet-v1"  # Replace with your S3 bucket name
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
      "t*", 
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
      "t*", 
      "m*", 
      "r*"
    ]
  }
}

# Function to select instance types that match deployment requirements
locals {
  # Filter and sort instance types by size and performance
  x86_instance_types = [for t in data.aws_ec2_instance_types.x86_compatible.instance_types : t 
    if can(regex("^[mtcr]\\d+\\.", t)) || 
       can(regex("^[mtcr]\\d+a\\.", t)) || 
       can(regex("^[mtcr]\\d+i\\.", t))
  ]

  arm64_instance_types = [for t in data.aws_ec2_instance_types.arm64_compatible.instance_types : t 
    if can(regex("^[mtcr]\\d+g\\.", t))
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
# ALB
###############################################################################

# IAM Role for ALB Controller
module "lb_controller_role" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  role_name = "eks-alb-controller-role"

  role_policy_arns = {
    alb_controller = aws_iam_policy.alb_controller.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# IAM Policy for ALB Controller
resource "aws_iam_policy" "alb_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  path        = "/"
  description = "IAM policy for AWS Load Balancer Controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "acm:GetCertificate",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:DeleteSecurityGroup",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeTags",
          "ec2:DescribeVpcs",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:RevokeSecurityGroupIngress",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:SetWebACL",
          "iam:CreateServiceLinkedRole",
          "iam:GetServerCertificate",
          "iam:ListServerCertificates",
          "shield:DescribeProtection",
          "shield:GetSubscriptionState",
          "shield:ListProtections",
          "waf-regional:GetWebACLForResource",
          "waf-regional:GetWebACL",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "tag:GetResources",
          "tag:TagResources",
          "iam:CreateServiceLinkedRole",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "acm:GetCertificate"
        ]
        Resource = "*"
      }      
    ]
  })
}

# Helm Release for ALB Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.4.4"

  depends_on = [helm_release.karpenter]


  

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.lb_controller_role.iam_role_arn
  }

  set {
    name  = "vpcId"
    value = data.aws_vpc.existing.id
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

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "6.7.3"

  depends_on = [helm_release.karpenter]


    values = [
    <<-EOT
    server:
      service:
        type: ClusterIP
    EOT
  ]

}

###############################################################################
# ArgoCD AMD 64
###############################################################################
resource "kubectl_manifest" "argocd_sock_shop_application" {
  yaml_body = <<-YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sock-shop
  namespace: argocd
  labels:
    architecture: amd64-x86_64  
spec:
  project: default
  source:
    repoURL: https://github.com/pelstix/opsfleet-karpenter.git
    targetRevision: HEAD
    path: manifests/amd64-apps
  destination:
    server: https://kubernetes.default.svc
    namespace: sock-shop
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
  template:
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64  # Graviton-specific node selection
  YAML

  depends_on = [helm_release.argocd]
}
###############################################################################
# ArgoCD ARM 64
###############################################################################

resource "kubectl_manifest" "argocd_inflate_application" {
  yaml_body = <<-YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: inflate
  namespace: argocd
  labels:
    architecture: arm64-Graviton  
spec:
  project: default
  source:
    repoURL: https://github.com/pelstix/opsfleet-karpenter.git
    targetRevision: HEAD
    path: manifests/arm64-apps
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
  template:
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
  YAML

  depends_on = [helm_release.argocd]
}

resource "helm_release" "prometheus" {
  name             = "prometheus"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "57.1.1"
  timeout          = 600

  depends_on = [helm_release.karpenter]

  values = [
    <<-EOT
    prometheus:
      prometheusSpec:
        # Reduce storage size and retention
        retention: 7d
        retentionSize: "10GB"
        
        # Limit resources
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1Gi
        
        
        storageSpec: null
    
    # Lightweight components configuration
    kube-state-metrics:
      resources:
        requests:
          cpu: 10m
          memory: 32Mi
        limits:
          cpu: 100m
          memory: 128Mi
    
    nodeExporter:
      resources:
        requests:
          cpu: 10m
          memory: 32Mi
        limits:
          cpu: 100m
          memory: 128Mi
    
    # Disable unnecessary components
    alertmanager:
      enabled: false
    
    grafana:
      enabled: false
    
    # Minimal pod scraping configuration
    kubeApiServer:
      enabled: true
    
    kubelet:
      enabled: true
    
    kubeControllerManager:
      enabled: false
    
    kubeScheduler:
      enabled: false
    
    kubeProxy:
      enabled: false
    
    kubeEtcd:
      enabled: false
    
    prometheus-node-exporter:
      resources:
        requests:
          cpu: 10m
          memory: 32Mi
        limits:
          cpu: 100m
          memory: 128Mi
    EOT
  ]
}

resource "helm_release" "grafana" {
  name             = "grafana"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  version          = "7.3.0"

  

  values = [
    <<-EOT
    persistence:
      enabled: false
    adminPassword: "admin123"
    datasources:
      datasources.yaml:
        apiVersion: 1
        datasources:
        - name: Prometheus
          type: prometheus
          url: http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090
          access: proxy
          isDefault: true
    dashboardProviders:
      dashboardproviders.yaml:
        apiVersion: 1
        providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default
    dashboards:
      default:
        # Kubernetes Pod Metrics Dashboard
        pod-metrics:
          json: |
            {
              "annotations": {},
              "editable": true,
              "gnetId": 13498,
              "graphTooltip": 0,
              "links": [],
              "schemaVersion": 36,
              "style": "dark",
              "tags": ["kubernetes", "pods"],
              "title": "Kubernetes / Pods",
              "uid": "k8s-pods-metrics"
            }
        
        # Node Exporter Full Dashboard
        node-exporter-full:
          json: |
            {
              "annotations": {},
              "editable": true,
              "gnetId": 1860,
              "graphTooltip": 0,
              "links": [],
              "schemaVersion": 36,
              "style": "dark",
              "tags": ["node-exporter"],
              "title": "Node Exporter Full",
              "uid": "node-metrics-full"
            }
        
        # Kubernetes Cluster Detailed Metrics
        cluster-metrics:
          json: |
            {
              "annotations": {},
              "editable": true,
              "gnetId": 15661,
              "graphTooltip": 0,
              "links": [],
              "schemaVersion": 36,
              "style": "dark",
              "tags": ["kubernetes", "cluster"],
              "title": "Kubernetes / Compute Resources / Cluster",
              "uid": "k8s-cluster-metrics"
            }
    EOT
  ]

  depends_on = [helm_release.prometheus]
}
