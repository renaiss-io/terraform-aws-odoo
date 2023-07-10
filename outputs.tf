output "default_dns" {
  value       = module.alb.lb_dns_name
  description = "DNS of the load balancer to access odoo"
}
