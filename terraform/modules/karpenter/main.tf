# modules/karpenter/main.tf
module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  cluster_name = var.cluster_name

  enable_v1_permissions = true

  enable_pod_identity             = true
  create_pod_identity_association = true

  # Attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

# Helm Release for Karpenter
resource "helm_release" "karpenter" {
  namespace           = "kube-system"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = var.ecr_username
  repository_password = var.ecr_password
  chart               = "karpenter"
  version             = "1.0.0"
  wait                = false

  values = [
    <<-EOT
    serviceAccount:
      name: ${module.karpenter.service_account}
    settings:
      clusterName: ${var.cluster_name}
      clusterEndpoint: ${var.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]
}

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
              values: [${join(",", formatlist("\"%s\"", var.x86_deployment_types))}]
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
              values: [${join(",", formatlist("\"%s\"", var.arm64_deployment_types))}]
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

# X86 Spot Node Class
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
            karpenter.sh/discovery: ${var.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      tags:
        karpenter.sh/discovery: ${var.cluster_name}
      spotMarketOptions:
        maxPrice: 0.1
  YAML

  depends_on = [helm_release.karpenter]
}

# Graviton Spot Node Class
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
            karpenter.sh/discovery: ${var.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${var.cluster_name}
      tags:
        karpenter.sh/discovery: ${var.cluster_name}
      spotMarketOptions:
        maxPrice: 0.1
  YAML

  depends_on = [helm_release.karpenter]
}