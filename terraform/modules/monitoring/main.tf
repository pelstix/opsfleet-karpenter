resource "helm_release" "prometheus" {
  name             = "prometheus"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.prometheus_chart_version
  timeout          = 600

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
  version          = var.grafana_chart_version

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