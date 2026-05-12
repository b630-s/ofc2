1. Create or review infrastructure plan:
   `infra/aws-proto/deploy-infra.sh`

2. Apply infrastructure when ready:
   in infra/aws-proto
   `infra/aws-proto/deploy-infra.sh --apply`

   Note:
   During `--apply`, the script now:
   - runs `terraform fmt -recursive` automatically during apply
   - bootstraps the VPC, subnets, routing, and NAT first
   - bootstraps the EKS control plane next
   - updates IRSA trust policies from the cluster OIDC issuer
   - then runs the full Terraform apply

   This avoids the earlier timing issues where:
   - the EBS CSI add-on needed IRSA trust too late
   - worker nodes launched before private-subnet routing and NAT were ready

   After a successful apply, the script also writes timestamped backups of the Terraform state into `infra/aws-proto/bkp/`.

   If apply is still running and you want to confirm progress from another shell, use these diagnostics:

   Check EKS cluster status:
   `aws eks describe-cluster --region us-east-1 --name dc-platform-bss-eks-proto --query 'cluster.status' --output text`

   Show full cluster summary:
   `aws eks describe-cluster --region us-east-1 --name dc-platform-bss-eks-proto`

   List managed node groups:
   `aws eks list-nodegroups --region us-east-1 --cluster-name dc-platform-bss-eks-proto`

   Then inspect a specific node group with its actual returned name:
   `aws eks describe-nodegroup --region us-east-1 --cluster-name dc-platform-bss-eks-proto --nodegroup-name <actual-nodegroup-name>`

   Check the EBS CSI add-on:
   `aws eks describe-addon --region us-east-1 --cluster-name dc-platform-bss-eks-proto --addon-name aws-ebs-csi-driver --query 'addon.status' --output text`

   After `platform/scripts/02-connect-cluster.sh`, you can also inspect the Kubernetes side:
   `kubectl get nodes`
   `kubectl get pods -n kube-system`

   `platform/scripts/02-connect-cluster.sh` is not required for Terraform apply itself.
   Use it:
   - after infra apply succeeds, before platform install
   - or during troubleshooting from another shell if you need to inspect nodes or `kube-system` pods while apply is still running

Next steps - refer to `platform/scripts/README.md`.

Current AWS Terraform layout:

- `infra/aws-proto/network.tf`
- `infra/aws-proto/eks.tf`
- `infra/aws-proto/storage.tf`
- `infra/aws-proto/iam.tf`
- `infra/aws-proto/variables.tf`
- `infra/aws-proto/terraform.tfvars`

This keeps the AWS prototype infrastructure in one readable folder while still separating network, cluster, storage, and IAM concerns by file.

Important current prototype note:

- Airflow PostgreSQL persistence is explicitly set to `storageClass: gp2` in the platform values for this AWS environment so it does not depend on a default StorageClass.
