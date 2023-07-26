output "dns" {
  value       = local.custom_domain ? local.cloudfront_custom_domain : module.cdn.cloudfront_distribution_domain_name
  description = "DNS to access odoo"
}
