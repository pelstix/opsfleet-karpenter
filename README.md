# OpsFleet EKS Cluster Configuration

## Overview

This repository provides a comprehensive, production-ready Amazon EKS (Elastic Kubernetes Service) cluster configuration designed for scalable, efficient, and flexible Kubernetes deployments.

### Key Features

- **Kubernetes Version**: 1.31
- **Node Scaling**: Karpenter for dynamic, cost-efficient scaling
- **Continuous Deployment**: Application deployment with ArgoCD
- **Networking**: AWS Load Balancer Controller
- **Monitoring**: Prometheus and Grafana
- **Architecture Support**: x86 and ARM64 (Graviton)

## Prerequisites

Before getting started, ensure you have the following installed:

- AWS CLI
- Terraform (version 1.0+)
- kubectl
- Helm
- Existing VPC named "Opsfleet-vpc"

  ![EKS Cluster Architecture](/images/Screenshot 2024-11-30 at 07.46.55.png)

## Cluster Components

### EKS Cluster Configuration

- **Kubernetes Version**: 1.31
- **Region**: Configurable (default set in variables)
- **Node Management**: Karpenter
- **Cluster Architecture**: x86 and ARM64 support

### Provisioned Services

1. **EKS Cluster**
   - Public endpoint access
   - Core addons (CoreDNS, kube-proxy, VPC CNI)
   - Managed node group for system components

2. **Karpenter**
   - Dynamic node provisioning
   - Spot instance support
   - Separate node pools for x86 and ARM64
   - Spot pricing cap at $0.10

3. **ArgoCD**
   - Continuous deployment
   - Sample applications:
     * Sock Shop (x86/AMD64)
     * Inflate (ARM64/Graviton)

4. **Monitoring**
   - Prometheus for metrics collection
   - Grafana for visualization
   - Pre-configured dashboards:
     * Kubernetes Pods
     * Node Metrics
     * Cluster Resources

5. **Networking**
   - AWS Load Balancer Controller
   - Internet Gateway
   - NAT Gateway
   - Public and Private subnets

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/pelstix/opsfleet-karpenter.git
cd opsfleet-karpenter
```

### 2. Configure AWS Credentials

Ensure your AWS CLI is configured:

```bash
aws configure
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Plan and Apply

```bash
terraform plan
terraform apply
```

## Deploying Applications

### X86 (AMD64) Deployment

1. Verify x86 node pool:
```bash
kubectl get nodepools
```

2. Deploy x86-specific application:
```bash
kubectl apply -f manifests/amd64-apps/your-x86-deployment.yaml
```

Use node selector in your deployment:
```yaml
spec:
  nodeSelector:
    kubernetes.io/arch: amd64
```

### ARM64 (Graviton) Deployment

1. Verify ARM64 node pool:
```bash
kubectl get nodepools
```

2. Deploy ARM64-specific application:
```bash
kubectl apply -f manifests/arm64-apps/your-arm64-deployment.yaml
```

Use node selector in your deployment:
```yaml
spec:
  nodeSelector:
    kubernetes.io/arch: arm64
```

## Accessing Services

### ArgoCD

1. Get admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

2. Port forward to access UI:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Grafana

1. Get admin password:
```bash
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode
```

2. Port forward to access:
```bash
kubectl port-forward svc/grafana -n monitoring 3000:80
```

### Frontend Application

The AWS Load Balancer Controller manages ingress and load balancing. Access the frontend via the ALB's DNS name:

`http://<alb-dns-name>.elb.amazonaws.com`

## Cleanup

To destroy the infrastructure:

```bash
terraform destroy
```

## Troubleshooting

- Verify AWS CLI configuration
- Check Terraform and provider versions
- Confirm network connectivity and VPC settings

## License

[Add your license information here]

## Contributing

[Add contribution guidelines here]
