variable "aws_region" {
  description = "AWS region. The ACM certificate must be in the same region."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR. Split into /24s for public and private subnets."
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "Instance size for the nginx fleet."
  type        = string
  default     = "t3.xlarge"
}

variable "asg_min_size" {
  description = "ASG minimum. 6 gives two instances per AZ."
  type        = number
  default     = 6
}

variable "asg_desired_capacity" {
  description = "Instances running under normal load."
  type        = number
  default     = 6
}

variable "asg_max_size" {
  description = "ASG maximum."
  type        = number
  default     = 20
}

variable "acm_certificate_arn" {
  description = "Existing ACM certificate ARN for the HTTPS listener. Required."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:", var.acm_certificate_arn))
    error_message = "Expected an ACM certificate ARN, e.g. arn:aws:acm:<region>:<account-id>:certificate/<id>."
  }
}
