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

variable "default_tags" {
  description = "Tags applied to all resources via the provider default_tags block. Consumers can inject their own (e.g. cost-center, owner)."
  type        = map(string)
  default     = {}
}
