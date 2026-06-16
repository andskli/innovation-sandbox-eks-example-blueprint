terraform {
  required_version = ">= 1.5"

  backend "s3" {
    key = "state/terraform.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.75"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.default_tags
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # Per-deployment suffix keeps account-scoped names (cluster, KMS alias) from
  # colliding with residue an imperfect aws-nuke pass may leave in a recycled
  # account. Falls back to the bare name for standalone use.
  name_suffix  = var.deploy_id != "" ? substr(replace(var.deploy_id, "-", ""), 0, 8) : ""
  cluster_name = local.name_suffix != "" ? "${var.cluster_name}-${local.name_suffix}" : var.cluster_name
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = local.azs
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  # Let EKS manage its own log group — avoids conflicts in recycled accounts
  create_cloudwatch_log_group = false

  cluster_compute_config = {
    enabled    = true
    node_pools = ["general-purpose"]
  }
}
