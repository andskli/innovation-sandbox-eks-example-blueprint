variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "sandbox-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version (null = latest)"
  type        = string
  default     = null
}

variable "deploy_id" {
  description = "Per-deployment id used to derive collision-free resource names. The blueprint injects the CloudFormation stack GUID (unique per lease); the \"local\" default gives standalone terraform a stable name so leftover/undeletable resources surface as a collision instead of silently accumulating. Empty = bare cluster_name."
  type        = string
  default     = "local"
}

variable "default_tags" {
  description = "Tags applied to all resources via the provider default_tags block. Consumers can inject their own (e.g. cost-center, owner)."
  type        = map(string)
  default     = {}
}
