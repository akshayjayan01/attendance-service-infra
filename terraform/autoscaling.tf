resource "aws_autoscaling_group" "nginx" {
  name = "${local.name}-nginx"

  min_size         = var.asg_min_size
  desired_capacity = var.asg_desired_capacity
  max_size         = var.asg_max_size

  # Six instances gives us two instances per AZ under normal conditions.
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.this.arn]

  # ELB health checks, so an instance with a dead nginx gets replaced.
  health_check_type = "ELB"

  launch_template {
    id      = aws_launch_template.nginx.id
    version = "$Latest"
  }

  # Tag blocks, not a tags argument. These propagate to instances.
  dynamic "tag" {
    for_each = merge(local.common_tags, { Name = "${local.name}-nginx" })

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# Scale on requests per target, not CPU. 96,000/min = 1,600 req/s, 80% of the
# 2,000 req/s benchmark.
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${local.name}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.nginx.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.this.arn_suffix}/${aws_lb_target_group.this.arn_suffix}"
    }

    target_value = local.scale_out_requests_per_minute

    # Scale-in handled below; target tracking alone drops instances on any dip.
    disable_scale_in = true
  }
}

# One instance at a time, only after 10 minutes below half the scale-out threshold.
resource "aws_autoscaling_policy" "scale_in" {
  name                    = "${local.name}-scale-in"
  autoscaling_group_name  = aws_autoscaling_group.nginx.name
  policy_type             = "StepScaling"
  adjustment_type         = "ChangeInCapacity"
  metric_aggregation_type = "Average"
  cooldown                = 600

  step_adjustment {
    metric_interval_upper_bound = 0
    scaling_adjustment          = -1
  }
}

resource "aws_cloudwatch_metric_alarm" "scale_in" {
  alarm_name        = "${local.name}-scale-in"
  alarm_description = "Requests per target below 800/s for 10 minutes. Remove one instance."

  namespace   = "AWS/ApplicationELB"
  metric_name = "RequestCountPerTarget"

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
    TargetGroup  = aws_lb_target_group.this.arn_suffix
  }

  # Sum is the only valid statistic for this metric. It's an average, not a total.
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 10
  datapoints_to_alarm = 10
  comparison_operator = "LessThanThreshold"
  threshold           = local.scale_in_requests_per_minute
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_autoscaling_policy.scale_in.arn]
}
