# Public ALB across the three AZs.
resource "aws_lb" "this" {
  name               = "${local.name}-alb"
  load_balancer_type = "application"
  internal           = false

  security_groups = [aws_security_group.alb.id]
  subnets         = aws_subnet.public[*].id

  tags = merge(local.common_tags, { Name = "${local.name}-alb" })
}

# The ASG registers instances here. No separate attachment resource.
resource "aws_lb_target_group" "this" {
  name     = "${local.name}-nginx"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  # Fail two health checks before removing a target from rotation.
  health_check {
    path                = "/"
    interval            = 5
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, { Name = "${local.name}-nginx" })
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
