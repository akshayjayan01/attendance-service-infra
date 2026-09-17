# Latest AL2023 for the region. No pinned AMI ID.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_launch_template" "nginx" {
  name_prefix   = "${local.name}-nginx-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.instance.name
  }

  # ASG places these in private subnets. No public IPs.
  vpc_security_group_ids = [aws_security_group.ec2.id]

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  # No `dnf update` - it adds minutes to boot and slows instance replacement.
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail
    dnf install -y nginx
    systemctl enable --now nginx
  EOF
  )

  tags = merge(local.common_tags, { Name = "${local.name}-nginx" })
}
