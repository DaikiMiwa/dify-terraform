# ------------------------------------------------
# DNS and ACM Certificate Configuration
# ------------------------------------------------

# Local values for domain configuration
locals {
  dify_fqdn    = "${var.dify_subdomain}.${var.domain_name}"
  cognito_fqdn = "${var.cognito_subdomain}.${var.domain_name}"
}

# ACM Certificate for both domains
resource "aws_acm_certificate" "dify_cert" {
  count = var.create_acm_certificate ? 1 : 0

  domain_name       = local.dify_fqdn
  validation_method = "DNS"

  subject_alternative_names = [
    local.cognito_fqdn
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.default_tags,
    {
      Name = "acm-${local.base_name}-001"
    }
  )
}

# DNS validation records
resource "aws_route53_record" "cert_validation" {
  for_each = var.create_acm_certificate ? {
    for dvo in aws_acm_certificate.dify_cert[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "dify_cert_validation" {
  count = var.create_acm_certificate ? 1 : 0

  certificate_arn         = aws_acm_certificate.dify_cert[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  timeouts {
    create = "5m"
  }
}

# Route 53 A record for ALB
resource "aws_route53_record" "dify_alb" {
  zone_id = var.route53_zone_id
  name    = local.dify_fqdn
  type    = "A"

  alias {
    name                   = aws_alb.dify_alb.dns_name
    zone_id                = aws_alb.dify_alb.zone_id
    evaluate_target_health = true
  }
}