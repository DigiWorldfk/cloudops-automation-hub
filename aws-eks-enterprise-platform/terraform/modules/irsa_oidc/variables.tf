variable "name_prefix" {
  type = string
}

variable "oidc_issuer_url" {
  description = "EKS OIDC issuer URL including https://"
  type        = string
}

variable "oidc_issuer_host" {
  description = "EKS OIDC issuer host without https://"
  type        = string
}

variable "service_accounts" {
  description = "Service accounts and exact IAM policies that may assume IRSA roles"
  type = map(object({
    namespace       = string
    service_account = string
    policy_json     = string
  }))
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
