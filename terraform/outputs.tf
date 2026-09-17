output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "alb_dns_name" {
  description = "ALB DNS name. Point the load test here."
  value       = aws_lb.this.dns_name
}

output "target_group_arn" {
  description = "Target group the ASG registers instances with."
  value       = aws_lb_target_group.this.arn
}

output "autoscaling_group_name" {
  description = "Auto Scaling group name."
  value       = aws_autoscaling_group.nginx.name
}
