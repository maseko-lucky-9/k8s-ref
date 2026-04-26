# Terraform — AWS EKS Deployment Recipe

> Production-equivalent EKS cluster matching the homelab MicroK8s setup. Populated alongside M5.

## Status

Skeleton — populate after homelab cluster is stable (M1–M4 complete).

## Planned modules

- VPC + private/public subnets (3 AZs)
- EKS cluster (managed control plane, k8s 1.30+)
- Managed node group (t3.medium baseline) **OR** Karpenter for dynamic provisioning
- IRSA OIDC provider
- AWS Load Balancer Controller (ALB/NLB ingress)
- ExternalDNS for Route53
- Outputs: `kubeconfig`, ArgoCD bootstrap command

## Cost guard

Per the launch plan Risk Register: cap monthly hosting at R500 (~$27 USD). Default to **MicroK8s home cluster** as the live demo; EKS Terraform is **deployed on-demand** for case-study screenshots, then destroyed.

```bash
# Estimated cost (us-east-1, default sizing):
# - EKS control plane: $73/mo
# - 1× t3.medium node: $30/mo
# - NAT gateway: $32/mo
# Total: ~$135/mo  ← exceeds R500 cap
#
# Hence: tear down between case-study screenshots. Document the destroy command.
```

## Quickstart (once populated)

```bash
cd terraform
terraform init
terraform apply -var-file=terraform.tfvars
# Wait for cluster ready
aws eks update-kubeconfig --name k8s-ref-demo --region us-east-1
# Then bootstrap ArgoCD as per ../argocd/README.md
```

## Destroy

```bash
terraform destroy -var-file=terraform.tfvars
```
