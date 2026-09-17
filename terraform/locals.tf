locals {
  name = "classroom-attendance"

  common_tags = {
    Project     = "classroom-attendance"
    Environment = "assessment"
    ManagedBy   = "terraform"
  }

  # First three AZs in the region.
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # RequestCountPerTarget is per minute, not per second. 1,600 req/s = 96,000/min,
  # which is 80% of the 2,000 req/s benchmark.
  scale_out_requests_per_minute = 96000
  scale_in_requests_per_minute  = 48000
}
