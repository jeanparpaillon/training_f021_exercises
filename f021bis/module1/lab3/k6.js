// Lab 3 load: productpage at a constant arrival rate, from OUTSIDE the
// cluster, through the NodePort — where users are. Run it with lab3/load.
//
// Not a Job in the cluster, as in F021: `kubectl drain` evicts every pod,
// the load generator included, and its summary goes with it.
//
// Adapted from F021 module 2 (k6/constant-load.yaml).
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    constant: {
      // Open loop: RATE requests per second whatever the latency, like
      // real users. A closed loop slows down with the service and hides it.
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE || 10),
      timeUnit: '1s',
      duration: __ENV.DURATION || '25m',
      preAllocatedVUs: 10,
      maxVUs: 100,
    },
  },
  // A new connection per request, as from many independent users. With
  // keep-alive, k6's few connections stay pinned (kube-proxy picks the pod
  // once per connection) to a pod after it has left the endpoints, and
  // the failures measured would be the client's, not the workload's.
  noConnectionReuse: true,
  // Zero downtime means zero: one failed request fails the run. k6 still
  // runs to the end and prints the summary.
  thresholds: {
    http_req_failed: ['rate==0'],
    http_req_duration: ['p(99)<1000'],
  },
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  const res = http.get(__ENV.TARGET || 'http://127.0.0.1:30080/productpage', { timeout: '10s' });
  // productpage answers 200 with an apology when a dependency fails:
  // count those separately from failed requests.
  check(res, {
    'status 200': (r) => r.status === 200,
    'reviews shown': (r) => !!r.body && !r.body.includes('reviews are currently unavailable'),
    'details shown': (r) => !!r.body && !r.body.includes('details are currently unavailable'),
    'ratings shown': (r) => !!r.body && !r.body.includes('Ratings service is currently unavailable'),
  });
}
