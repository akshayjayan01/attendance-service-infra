# Classroom Attendance Service

Terraform infrastructure for the Classroom Attendance Service SRE assessment. The
application is simulated with a default nginx page, so the work here is the
infrastructure around it.

Targets: 6,000 req/s, 99.9% success, 99.9% of responses under 300 ms, across 3 AZs.

## Architecture

```
Internet
   |
 HTTPS
   |
  ALB          public subnets, 3 AZs
   |
  ASG          private subnets, 3 AZs, 6-20 instances
   |
 nginx         default welcome page
   |
CloudWatch     alarms + dashboard
```

- The ALB is public and terminates HTTPS. HTTP redirects to HTTPS.
- EC2 instances are private. No public IPs, no inbound path from the internet.
- Instances run across 3 Availability Zones, two per AZ at the baseline.
- The ASG starts at 6 instances and replaces unhealthy ones.
- nginx is stateless, so instances are disposable.
- Access is through SSM Session Manager. There is no SSH.

## Why This Design

| Component | Why |
| --- | --- |
| ALB | Distributes traffic and performs health checks |
| EC2 | Simple compute for nginx |
| ASG | Scaling and instance replacement |
| VPC | Network isolation |
| 3 AZs | Handles an AZ failure |
| NAT gateway | Outbound for package install and SSM |
| CloudWatch | Metrics, dashboard and alarms |
| Terraform | Infrastructure as code |
| k6 | Load testing |
| SSM | Instance access without SSH |

## Capacity and Scaling

| Setting | Value |
| --- | --- |
| Requirement | 6,000 req/s |
| Minimum | 6 instances |
| Desired | 6 instances |
| Maximum | 20 instances |
| Scale out | `ALBRequestCountPerTarget` > 96,000/min per target (~1,600 req/s) |
| Scale in | < 48,000/min per target (~800 req/s) for 10 minutes |

Scaling runs on request volume only. Target tracking handles scale-out; a separate
step policy handles scale-in and removes one instance at a time, with a 600-second
cooldown. Scale-in is disabled on the target tracking policy, because left on it drops
instances on any short dip.

CPU is not a scaling signal. Latency and 5xx metrics are monitored but do not control
scaling.

**2,000 req/s per t3.xlarge is a benchmark assumption, not an AWS guarantee. It must be
validated with k6 before the fleet size means anything.** If one instance only sustains
1,200 req/s, the answer is more instances, not a different architecture.

```
6 instances x 2,000 req/s = 12,000 req/s nominal   (requirement is 6,000)
4 instances x 2,000 req/s =  8,000 req/s nominal   (after one AZ failure)
```

## Availability

Six instances across three AZs is two per AZ. Losing one AZ leaves about four, which is
still 8,000 req/s nominal against the 6,000 requirement.

- The ALB removes unhealthy targets after failed health checks and the ASG replaces them.
- `healthy-hosts-low` alarms when `HealthyHostCount` drops below 4, which is more
  capacity gone than the planned single-AZ failure baseline.
- Requests still in flight during detection can fail. This design shortens that window;
  it does not eliminate it.

## SLOs

**Success rate — 99.9%**

Server-side failures only: ALB 5xx plus target 5xx, measured against `RequestCount`.
For this assessment, 4xx responses are treated as client-side and excluded from the
server-error SLO — that's a measurement decision, not a claim that every 4xx originates
from the client. AWS excludes health check requests from ALB metrics, so probes don't
inflate the denominator.

Error budget is 0.1% — roughly 1,000 failed requests per 1,000,000.

**Latency — 99.9% under 300 ms**

`TargetResponseTime` at the p99.9 extended statistic, alarmed at 300 ms. k6 measures
end-to-end client latency. Average latency is not evidence for this SLO: an average can
sit comfortably under 300 ms while the slowest 1% are far over it.

## Monitoring and Alarms

Six alarms. Five are for monitoring; one drives scale-in.

| Alarm | Metric | Purpose |
| --- | --- | --- |
| `alb-5xx` | `HTTPCode_ELB_5XX_Count` > 10/min | ALB errors |
| `target-5xx` | `HTTPCode_Target_5XX_Count` > 100/min | Target errors |
| `latency-p999` | `TargetResponseTime` p99.9 > 300 ms | Latency SLO |
| `unhealthy-targets` | `UnHealthyHostCount` >= 1 | Availability |
| `healthy-hosts-low` | `HealthyHostCount` < 4 | Availability |
| `scale-in` | `RequestCountPerTarget` < 48,000/min | Auto Scaling |

`scale-in` is an internal scaling trigger, not an alert — it is the only alarm with an
action, and that action is the scale-in step policy, not a notification. `healthy-hosts-low`
is an availability alarm and does not trigger scaling. No alarm notifies anyone, because
this stack creates no SNS topic.

The `classroom-attendance-slo` dashboard contains 3 widgets and 10 metric series covering
success rate, latency percentiles (p50/p95/p99/p99.9), and capacity/scaling.

## Health Checks

| Setting | Value | Source |
| --- | --- | --- |
| Protocol | HTTP | default |
| Path | `/` | explicit |
| Interval | 5 seconds | explicit |
| Unhealthy threshold | 2 failed checks | explicit |
| Healthy threshold | 3 | provider default |
| Timeout | 5 seconds | AWS default |

Detection lands around 5–10 seconds depending on where the failure falls in the check
cycle.

## Connection Draining

`deregistration_delay` is **300 seconds**, the AWS default — it is not set in the
Terraform. When an instance is deregistered the ALB stops sending it new requests while
in-flight requests are allowed to finish.

Left at the default deliberately. The workload is a static nginx response and the
assessment prioritizes simplicity over tuning, so there was no reason to shorten it. If
scale-in testing showed slow deregistration, this is the value to tune, based on the
request durations actually observed.

## Security

- ALB accepts HTTPS 443 from the internet. HTTP 80 is open only so the listener can
  redirect to HTTPS.
- EC2 is private. Port 80 accepts traffic only from the ALB security group, by security
  group reference rather than CIDR.
- No SSH, no key pair, no bastion. Access is `aws ssm start-session`.
- The instance role carries one policy: `AmazonSSMManagedInstanceCore`.
- IMDSv2 is required. The HTTPS listener enforces TLS 1.2 minimum.
- No secrets anywhere. The service has none to hold.

Security-group egress is currently allow-all. Tightening it would require separating the
rules into standalone security-group rule resources to avoid dependency cycles.

## Project Structure

```
.
├── README.md
├── .gitignore
├── terraform/
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── terraform.tfvars.example
│   ├── locals.tf
│   ├── network.tf
│   ├── security.tf
│   ├── iam.tf
│   ├── alb.tf
│   ├── compute.tf
│   ├── autoscaling.tf
│   ├── monitoring.tf
│   └── outputs.tf
└── tests/
    └── load-test.js
```

## Prerequisites

- Terraform >= 1.5
- AWS CLI, authenticated (`aws sts get-caller-identity` should work)
- An AWS account with permissions to create VPC, EC2, ELB, IAM and CloudWatch resources
- An existing ACM certificate, validated, in the same region as the ALB
- k6, for load testing

## Configuration

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Then set `acm_certificate_arn` in `terraform.tfvars`. It is commented out in the example
because the certificate lives outside this stack. Find it with:

```bash
aws acm list-certificates --region us-east-1 \
  --query 'CertificateSummaryList[].CertificateArn' --output text
```

Everything else has a sensible default: region `us-east-1`, `t3.xlarge`, ASG 6/6/20.

## Deploy

```bash
cd terraform

terraform init
terraform fmt -recursive
terraform validate
terraform plan  -var="acm_certificate_arn=<your-certificate-arn>"
terraform apply -var="acm_certificate_arn=<your-certificate-arn>"
```

The certificate must already exist and be validated, and it must be in the same region
as the ALB.

Outputs: `vpc_id`, `alb_dns_name`, `target_group_arn`, `autoscaling_group_name`.

## Test

`tests/load-test.js` ramps 1,000 → 8,000 req/s and fails the run if either SLO breaks.
It goes to 8,000 on purpose: the requirement is 6,000 req/s, so testing at 8,000
validates it with headroom instead of just touching the target. The two SLOs are encoded
as k6 thresholds: `http_req_failed < 0.1%` and `http_req_duration p(99.9) < 300 ms`.

```bash
BASE_URL="https://$(terraform -chdir=terraform output -raw alb_dns_name)/" k6 run tests/load-test.js
```

Run it from an instance inside the VPC or from somewhere with enough bandwidth — a home
connection will hit its own limits well before 6,000 req/s.

Two separate progressions, for different questions:

- **Single instance:** 500 → 1,000 → 1,500 → 2,000 → 3,000+ req/s, to establish what one
  t3.xlarge actually sustains while holding the latency SLO. This is a manual benchmark,
  not a script in this repo.
- **Fleet:** 1,000 → 8,000 req/s against the ALB, which is what `tests/load-test.js` does.

The first establishes per-instance capacity; the second validates the full fleet.

Alongside the run, watch success rate, p50/p95/p99/p99.9 latency, ALB 5xx, healthy target
count, and whether the ASG scaled.

**No load test results are committed.** The numbers in this README are assumptions to be
checked, not measured outcomes.

## Validation

```bash
terraform fmt -recursive -check
terraform validate
terraform plan
```

`plan` needs a real certificate ARN, as shown above.

## Cleanup

```bash
terraform destroy
```

This removes everything the configuration created. Nothing here is stateful, so it is
safe to tear down.

## Design Decisions

**EC2 rather than ECS or Fargate.** The workload is one static nginx response. There is
no image to build, nothing to schedule and no service discovery. An ASG gives instance
replacement and multi-AZ spread in about 40 lines.

**No database, cache or queue.** nginx serves a static file with no downstream
dependency. There is no state to store and nothing to decouple.

**Six instances, not three.** Provides capacity for an AZ failure while maintaining the
6,000 req/s requirement under the benchmark assumption.

**Three AZs.** Provides AZ-level resilience without adding multi-region complexity.

**`RequestCountPerTarget` for scaling.** It tracks the load each instance is actually
handling, which is far better than CPU for a static response.

**SSM instead of SSH.** No open port, no key pair to distribute or rotate, no bastion to
patch.

## Known Limitations

- 2,000 req/s per instance is a benchmark assumption, not measured.
- Single region. Regional failover is out of scope.
- ALB and EC2 egress are allow-all, for the dependency-cycle reason above.
- The ACM certificate ARN is supplied externally; this stack does not create it.
- SSM session content logging to CloudWatch Logs or S3 is not configured. CloudTrail
  records API activity such as `StartSession`, not session contents.
- `terraform plan` cannot validate the CloudWatch dashboard JSON, because the dashboard
  body is computed at apply time.
- On a fresh apply, `healthy-hosts-low` sits in ALARM until the ASG registers targets
  and `HealthyHostCount` starts reporting. It uses `treat_missing_data = "breaching"`,
  which is intended, but expect it to be red for the first minute or two.
