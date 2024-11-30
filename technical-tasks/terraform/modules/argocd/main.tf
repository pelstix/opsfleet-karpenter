resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version

  values = [
    <<-EOT
    server:
      service:
        type: ClusterIP
    EOT
  ]
}

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
    path: technical-tasks/manifests/amd64-apps
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
        kubernetes.io/arch: amd64
  YAML

  depends_on = [helm_release.argocd]
}

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
    path: technical-tasks/manifests/arm64-apps
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
