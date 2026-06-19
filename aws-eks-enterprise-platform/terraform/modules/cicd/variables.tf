###############################################################################
# CICD — GitHub Actions OIDC IAM role (no long-lived keys)
###############################################################################

variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "github_org" {
  description = "GitHub organisation or username (e.g. DigiWorldfk)"
  type        = string
}
variable "github_repo" {
  description = "GitHub repository name (e.g. aws-eks-enterprise-platform)"
  type        = string
}
variable "ecr_repository_arns" {
  description = "List of ECR repository ARNs the CI role may push to"
  type        = list(string)
  default     = []
}
variable "eks_cluster_name" {
  description = "EKS cluster name — CI role gets eks:DescribeCluster + update-kubeconfig"
  type        = string
}
variable "ssm_parameter_prefix" {
  description = "SSM parameter path prefix the CI role may write to"
  type        = string
  default     = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
