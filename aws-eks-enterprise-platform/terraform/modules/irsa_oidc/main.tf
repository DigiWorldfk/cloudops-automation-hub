data "tls_certificate" "eks" {
  url = var.oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = var.oidc_issuer_url
  tags            = var.tags
}

resource "aws_iam_role" "service_account" {
  for_each = var.service_accounts

  name = "${var.name_prefix}-irsa-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_issuer_host}:sub" = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
          "${var.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    ServiceAccount = each.value.service_account
    Namespace      = each.value.namespace
  })
}

resource "aws_iam_role_policy" "service_account" {
  for_each = var.service_accounts

  name   = "${var.name_prefix}-irsa-${each.key}-policy"
  role   = aws_iam_role.service_account[each.key].id
  policy = each.value.policy_json
}
