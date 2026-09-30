# slo-demo: Service Level Objectives

## Service

`slo-demo` is a small HTTP service running as two replicas, one on each worker
PC of a three-node k3s home lab (pc1, pc2; the laptop is excluded because it
sleeps and roams). Users reach it through Traefik on pc1. Prometheus on pc1
scrapes both replicas every 15 seconds.

Fault injection is built in: the `slo-demo-fault` ConfigMap sets an error rate
and an added latency, which every replica picks up within about a minute. This
makes it possible to spend error budget on demand instead of waiting for real
failures.

## SLIs

Both SLIs are measured on requests to `/`, as seen by the service itself.

**Availability SLI**: the proportion of requests that did not fail with a 5xx
status.

```promql
1 - (
  sum(rate(http_requests_total{namespace="slo-demo",route="/",code=~"5.."}[30d]))
  /
  sum(rate(http_requests_total{namespace="slo-demo",route="/"}[30d]))
)
```

**Latency SLI**: the proportion of requests that completed in under 250 ms.

```promql
sum(rate(http_request_duration_seconds_bucket{namespace="slo-demo",route="/",le="0.25"}[30d]))
/
sum(rate(http_request_duration_seconds_count{namespace="slo-demo",route="/"}[30d]))
```

## SLOs

Both are measured over a rolling 30-day window.

| SLO | Target | Error budget | Budget as time |
|---|---|---|---|
| Availability | 99.5% | 0.5% of requests | about 3.6 hours of total outage |
| Latency (< 250 ms) | 99% | 1% of requests | about 7.2 hours of all-slow traffic |

### Why these numbers

- **99.5%, not 99.9%.** The nodes are Windows PCs running Linux under WSL2;
  they reboot for Windows updates and occasionally lose networking. A 99.9%
  target allows about 43 minutes of outage a month, which one node failure plus
  detection time could consume on its own. 99.5% is strict enough that
  sustained problems show up, while normal home-lab maintenance fits inside it.
- **250 ms.** The service normally answers in a few milliseconds, so 250 ms
  marks requests that are clearly degraded rather than normal jitter. It is
  also a bucket boundary in the service's latency histogram; a threshold that
  falls between buckets cannot be measured exactly.
- **99% for latency.** Latency is allowed a larger budget than availability,
  because a slow response is less harmful than a failed one.

## Alerting policy

Alerts use multiwindow, multi-burn-rate rules (Google SRE Workbook, ch. 5). A
burn rate of 1 would use exactly the whole budget in 30 days. Each alert
requires a long window, to show the budget is really being spent, and a short
window, to show it is still happening now. This keeps alerts from firing on
brief blips and lets them clear soon after an incident ends.

| Alert | Burn rate | Windows | Budget spent at this rate | Action |
|---|---|---|---|---|
| Fast burn | 14.4x | 1h and 5m | 2% per hour | page |
| Slow burn | 6x | 6h and 30m | 5% per 6 hours | ticket |

Rules live in `slo-rules.yaml` (recording rules for each window, error budget
remaining, and the four alerts: availability and latency, fast and slow).

## Architecture notes and trade-offs

- **Host networking for the replicas.** WSL2's mirrored networking only
  forwards inbound traffic to ports opened by a Linux process. Flannel's VXLAN
  tunnel port is opened by the kernel, so pod-to-pod traffic between nodes
  never arrives, and NodePorts are unreachable from the LAN. The replicas
  therefore use `hostNetwork: true` on port 18080, which limits the service to
  one replica per node.
- **Monitoring shares pc1 with the control plane.** If pc1 fails, both the
  cluster API and the monitoring stack go down. This is accepted for a home lab
  and noted as a risk.

## Drill log

Record each drill: what was done, when it was detected, how long it lasted,
how much error budget it used, and a screenshot of the budget graph.

| Date | Drill | Start | Alert fired | Recovered | Budget used | Notes |
|---|---|---|---|---|---|---|
| 2026-09-30 | pc2 shut down (`wsl --shutdown`) | 14:44:17 | None: SLI blind to it (finding 1) | 14:49:33 | Not measured | [Drill 2 write-up](drills/002-node-failure/README.md) |
| 2026-09-30 | Error injection (`error_rate` 0.5) | 10:25:20 | Page 10:37:30 (+12 min), ticket 10:39:37 | 11:11:37 (page cleared 10:47:30) | ~4% of error budget | [Drill 1 write-up](drills/001-error-injection/README.md) |
| 2026-09-30 | Latency injection (`latency_ms` 400) | 16:52:51 | Page 17:07:55 (+15 min), ticket 17:22:50 (+30 min) | 17:53:53 (page cleared 17:28:58) | 6.7% of latency budget | [Drill 3 write-up](drills/003-latency-injection/README.md) |
