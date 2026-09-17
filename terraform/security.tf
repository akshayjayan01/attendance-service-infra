resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Public entry point. HTTPS from anywhere, HTTP only to redirect."
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from the internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP, only so the listener can redirect to HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-alb" })
}

resource "aws_security_group" "ec2" {
  name        = "${local.name}-ec2"
  description = "nginx instances. Port 80 is reachable only from the load balancer."
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP from the ALB security group only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # No SSH rule. Admin access is Session Manager.

  egress {
    description = "Package install at boot and Session Manager, via the NAT gateway"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-ec2" })
}
