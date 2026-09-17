import http from 'k6/http';
import { check } from 'k6';

// Ramps to the 6,000 req/s target and then past it, to find where the SLOs break.
//
// Run it from inside the VPC or from something big enough that the generator is not
// the bottleneck - a home connection will give up well before 6,000 req/s.
//
//   BASE_URL="https://<alb-dns-name>/" k6 run tests/load-test.js
//
export const options = {
  scenarios: {
    ramp: {
      executor: 'ramping-arrival-rate',
      startRate: 1000,
      timeUnit: '1s',

      // Arrival-rate, not VUs: we care about offered requests per second, and open
      // model ramping holds that rate even when latency climbs.
      preAllocatedVUs: 500,
      maxVUs: 4000,

      stages: [
        { target: 1000, duration: '2m' },
        { target: 2000, duration: '2m' },
        { target: 4000, duration: '2m' },
        { target: 6000, duration: '5m' }, // the requirement, held long enough to scale
        { target: 8000, duration: '2m' }, // past it, to find the edge
        { target: 0, duration: '1m' },
      ],
    },
  },

  discardResponseBodies: true,

  summaryTrendStats: ['avg', 'p(50)', 'p(95)', 'p(99)', 'p(99.9)', 'max'],

  // The two SLOs, as pass/fail. A breach fails the run.
  thresholds: {
    http_req_failed: ['rate<0.001'], // 99.9% success rate
    http_req_duration: ['p(99.9)<300'], // 99.9% within 300 ms
  },
};

const BASE_URL = __ENV.BASE_URL;

export default function () {
  const res = http.get(BASE_URL);

  check(res, {
    'status is 200': (r) => r.status === 200,
  });
}
