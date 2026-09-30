# Drill 2: node failure (2026-09-30)

## What was done

With steady load from the laptop (about 7 requests/second; every request logged
with its status code and the node that answered, using `scripts/load.sh`), WSL on
pc2 was shut down with `wsl --shutdown` at **14:44:17 IST (09:14:17 UTC)**. This
simulates a sudden node loss: no drain, no warning to Kubernetes. pc2 was started
again at 14:49:25 IST, giving **5 minutes 8 seconds** of downtime.

The service runs two replicas with `hostNetwork: true`, one on pc1 and one on pc2,
behind Traefik on pc1.

## Timeline (IST)

| Time | Event |
|---|---|
| 14:44:17 | pc2 WSL shut down |
| ~14:44:30 | Prometheus: `up` for the pc2 replica drops to 0 |
| 14:44:38 | `slo-pc2` marked NotReady, **21 s after the failure**; its pod marked not ready (`NodeNotReady` event), which removes it from the Service |
| 14:44:51 | First logged request after the failure: served by pc1 (traffic had moved by this time at the latest) |
| 14:44:51–14:49:30 | All ~1,900 logged requests served by pc1, **0 failures** |
| 14:49:25 | pc2 WSL started |
| 14:49:30 | `slo-pc2` Ready, 5 s after start |
| 14:49:33 | pc2 replica ready again (container restarted once), **8 s after start** |
| 14:49:38 | Pod eviction deadline (5-minute default toleration). Cancelled, because pc2 returned 8 s earlier |

## Results

| Measure | Value |
|---|---|
| Detection (failure → node NotReady) | 21 s |
| Traffic moved to pc1 | within 34 s at the latest |
| Failed requests after 14:44:51 | 0 of ~1,900 |
| Failed requests 14:44:17–14:44:51 | **not measured** (see "Test issue") |
| What the availability SLI showed | 0% errors throughout |
| Recovery (WSL start → replica serving) | 8 s |

## Findings

**1. The availability SLI is blind to this failure.** The SLI is computed from the
application's own request counters. A replica that is down counts nothing, so
`slo:availability_errors:ratio_rate5m` stayed at 0 for the whole outage while
`up` for the pc2 replica was 0. Any requests that failed during the switchover
never reached an application, so they could never be counted. A failure mode
that removes a replica is therefore invisible to the SLO and its alerts.
*Fix:* measure the SLIs at the ingress (Traefik), which records every request,
including those that fail before reaching a replica.

**2. Eviction has nowhere to go.** Had pc2 stayed down 8 s longer, its pod would
have been evicted. The replacement cannot run on pc1 (host port 18080 already in
use) or on the laptop (excluded by node affinity), so the service would run on a
single replica until someone intervened. This happened for real during a full
reboot earlier the same day: pod `thw4h` was evicted and its replacement stayed
Pending until pc2 returned. This is the main cost of the host-network design
(chosen because WSL mirrored networking drops pod-to-pod traffic between nodes).
*Options:* raise `tolerationSeconds` for the `node.kubernetes.io/unreachable` and
`not-ready` taints on this Deployment, so the pod waits for its node instead of
being evicted into a Pending state; or add another eligible node.

**3. Detection is fast; routing followed it.** The node was marked NotReady 21 s
after the failure, and the pod's removal from the Service followed immediately.
By 14:44:51 at the latest, all traffic was on pc1 and nothing failed afterwards.

## Test issue

The load log for this run was accidentally truncated at about 14:44:50: a shell
line containing `> ~/drill2.log` was re-run, which emptied the file. The first 34
seconds after the failure, the window in which users could have seen errors, are
therefore missing. From the next run on, each drill uses a fresh log file, and
the operator checks that exactly one load generator is running before starting.

## Open items

- [ ] Re-run with a clean log, and with an EndpointSlice watch, to measure failed
      requests in the first ~34 s and the exact moment the pc2 endpoint stops
      being ready.
- [ ] Move the SLIs to Traefik metrics (finding 1).
- [ ] Decide on eviction behaviour for this Deployment (finding 2).
