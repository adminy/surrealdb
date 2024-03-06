locals {
  api_gtw_domain_name = "${local.project_name}.${var.domain}"
}

data "aws_route53_zone" "existing_zone" {
  count = var.domain != "" ? 1 : 0

  name = var.domain
}

resource "aws_acm_certificate" "ssl_certificate" {
  count = var.domain != "" ? 1 : 0

  domain_name       = local.api_gtw_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "domain" {
  for_each = {
    for dvo in aws_acm_certificate.ssl_certificate[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.existing_zone[0].zone_id
}

resource "aws_acm_certificate_validation" "domain" {
  count = var.domain != "" ? 1 : 0

  certificate_arn         = aws_acm_certificate.ssl_certificate[0].arn
  validation_record_fqdns = [for record in aws_route53_record.domain : record.fqdn]
}

resource "aws_apigatewayv2_domain_name" "domain" {
  count      = var.domain != "" ? 1 : 0
  depends_on = [aws_acm_certificate_validation.domain]

  domain_name = local.api_gtw_domain_name
  domain_name_configuration {
    certificate_arn = aws_acm_certificate.ssl_certificate[0].arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "domain" {
  count = var.domain != "" ? 1 : 0

  domain_name = aws_apigatewayv2_domain_name.domain[0].domain_name
  stage       = var.stage
  api_id      = aws_apigatewayv2_api.surrealdb.id
}

resource "aws_route53_record" "example" {
  count = var.domain != "" ? 1 : 0

  name    = aws_apigatewayv2_domain_name.domain[0].domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.existing_zone[0].id

  alias {
    evaluate_target_health = false
    name                   = aws_apigatewayv2_domain_name.domain[0].domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.domain[0].domain_name_configuration[0].hosted_zone_id
  }
}