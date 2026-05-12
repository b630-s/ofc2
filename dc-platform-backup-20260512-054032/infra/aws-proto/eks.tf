data "aws_iam_role" "eks_cluster" {
  name = var.eks_cluster_role_name
}

data "aws_iam_role" "eks_node" {
  name = var.eks_node_role_name
}

data "aws_iam_role" "ebs_csi" {
  name = var.ebs_csi_role_name
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.eks_cluster_name
  cluster_version = var.eks_cluster_version

  create_iam_role = false
  iam_role_arn    = data.aws_iam_role.eks_cluster.arn

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }

    kube-proxy = {
      most_recent = true
    }

    vpc-cni = {
      most_recent = true
    }
  }

  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports = {
      description                = "Node to node communication"
      protocol                   = "-1"
      from_port                  = 0
      to_port                    = 0
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  eks_managed_node_group_defaults = {
    ami_type = "AL2023_x86_64_STANDARD"
  }

  eks_managed_node_groups = {
    core = {
      create_iam_role = false
      iam_role_arn    = data.aws_iam_role.eks_node.arn

      min_size       = var.core_node_min_size
      max_size       = var.core_node_max_size
      desired_size   = var.core_node_desired_size
      instance_types = var.core_node_instance_types
      disk_size      = var.core_node_disk_size

      labels = {
        NodeGroupType = "core"
        WorkloadClass = "platform"
      }

      tags = {
        Name = "${var.eks_cluster_name}-core"
      }
    }

    workload = {
      create_iam_role = false
      iam_role_arn    = data.aws_iam_role.eks_node.arn

      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      instance_types = var.node_instance_types
      disk_size      = var.node_disk_size

      labels = {
        NodeGroupType = "workload"
        WorkloadClass = "tenant"
      }

      tags = {
        Name = "${var.eks_cluster_name}-workload"
      }
    }
  }

  tags = local.common_tags
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = data.aws_iam_role.ebs_csi.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    module.eks
  ]

  tags = local.common_tags
}
