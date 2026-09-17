locals {
  # Dimension pair for target-group metrics.
  alb_dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
    TargetGroup  = aws_lb_target_group.this.arn_suffix
  }
}

# Alarms have no alarm_actions - there is no SNS topic in this stack.

# ALB-generated errors. Any sustained count hits the success SLO.
resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  alarm_name        = "${local.name}-alb-5xx"
  alarm_description = "The load balancer is returning 5xx responses."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"

  dimensions = { LoadBalancer = aws_lb.this.arn_suffix }

  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 10
  treat_missing_data  = "notBreaching"
}

# nginx errors. 0.1% of 6,000 req/s is ~360/min, so 100 is an early warning.
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name        = "${local.name}-target-5xx"
  alarm_description = "nginx is returning 5xx responses."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_5XX_Count"

  dimensions = local.alb_dimensions

  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 100
  treat_missing_data  = "notBreaching"
}

# An instance out of rotation. The other five absorb it.
resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name        = "${local.name}-unhealthy-targets"
  alarm_description = "At least one nginx instance is failing health checks."

  namespace   = "AWS/ApplicationELB"
  metric_name = "UnHealthyHostCount"

  dimensions = local.alb_dimensions

  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
}

# Availability alarm, not a scaling trigger. Six instances is two per AZ, so one AZ
# loss leaves four.
resource "aws_cloudwatch_metric_alarm" "healthy_hosts_low" {
  alarm_name        = "${local.name}-healthy-hosts-low"
  alarm_description = "Fewer than 4 healthy targets - more capacity lost than a single AZ failure."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HealthyHostCount"

  dimensions = local.alb_dimensions

  # Minimum, so one node seeing fewer healthy targets is enough to trip it.
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 4

  # No targets registered means no data, which here is a fault, not a quiet period.
  treat_missing_data = "breaching"
}

# p99.9, not an average. The SLO is about the tail.
resource "aws_cloudwatch_metric_alarm" "latency_p999" {
  alarm_name        = "${local.name}-latency-p999"
  alarm_description = "p99.9 target response time above the 300 ms SLO."

  namespace   = "AWS/ApplicationELB"
  metric_name = "TargetResponseTime"

  dimensions = local.alb_dimensions

  extended_statistic  = "p99.9"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0.3
  treat_missing_data  = "notBreaching"
}

# The two SLOs on top, the scaling signals underneath.
resource "aws_cloudwatch_dashboard" "slo" {
  dashboard_name = "${local.name}-slo"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          title  = "Success rate (SLO 99.9%)"
          region = var.aws_region
          view   = "timeSeries"
          period = 60

          yAxis = { left = { min = 98, max = 100 } }

          annotations = {
            horizontal = [{ label = "99.9%", value = 99.9 }]
          }

          metrics = [
            [{ expression = "100 - 100 * (m2 + m3) / m1", label = "Success rate", id = "e1" }],
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.this.arn_suffix, "TargetGroup", aws_lb_target_group.this.arn_suffix, { id = "m1", stat = "Sum", visible = false }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.this.arn_suffix, "TargetGroup", aws_lb_target_group.this.arn_suffix, { id = "m2", stat = "Sum", visible = false }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.this.arn_suffix, { id = "m3", stat = "Sum", visible = false }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          title  = "Latency percentiles (SLO p99.9 < 300ms)"
          region = var.aws_region
          view   = "timeSeries"
          period = 60

          annotations = {
            horizontal = [{ label = "300ms", value = 0.3 }]
          }

          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.this.arn_suffix, "TargetGroup", aws_lb_target_group.this.arn_suffix, { label = "p50", stat = "p50" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.this.arn_suffix, "TargetGroup", aws_lb_target_group.this.arn_suffix, { label = "p95", stat = "p95" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.this.arn_suffix, "TargetGroup", aws_lb_target_group.this.arn_suffix, { label = "p99", stat = "p99" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.this.arn_suffix, "TargetGroup", aws_lb_target_group.this.arn_suffix, { label = "p99.9", stat = "p99.9" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          title  = "Capacity and scaling (scales out at 96k/min per target)"
          region = var.aws_region
          view   = "timeSeries"
          period = 60

          metrics = [
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", aws_autoscaling_group.nginx.name, { label = "In service", stat = "Average" }],
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", aws_lb.this.arn_suffix, "TargetGroup", aws_lb_target_group.this.arn_suffix, { label = "Healthy targets", stat = "Average" }],
            ["AWS/ApplicationELB", "RequestCountPerTarget", "LoadBalancer", aws_lb.this.arn_suffix, "TargetGroup", aws_lb_target_group.this.arn_suffix, { label = "Requests per target /min", stat = "Sum", yAxis = "right" }],
          ]
        }
      },
    ]
  })
}
