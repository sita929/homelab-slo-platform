# Drill 3: latency injection (2026-09-30)

## What was done

With steady open-loop load from the laptop (about 10 requests/second, using
`scripts/load-open.sh`), the `latency_ms` fault switch was set to 400 at
**16:52:51 IST (11:22:51 UTC)** and back to 0 at **17:23:35 IST (11:53:35 UTC)**:
30 minutes 44 seconds in which every request took 320–480 ms, above the 250 ms
latency SLO threshold.

**Why open-loop load.** The earlier load generator waited for each response
before sending the next request. At 400 ms per request it would have dropped
from about 7 to about 2 requests/second, so the slow period would have been
under-represented in the SLI and the page would have taken about 24 minutes
instead of about 11. Load generators that back off when the service slows down
under-report latency problems (*coordinated omission*). The open-loop generator
starts a request every 0.1 s regardless of how long earlier ones take.

## Timeline (IST)

| Time | Event |
|---|---|
| 16:52:51 | `latency_ms` set to 400 |
| ~16:54 | Pods pick up the change; the slow ratio starts climbing |
| 17:06:58 | Latency fast burn pending (+14 min 07 s) |
| 17:07:55 | **Latency fast burn firing: page** (+15 min 04 s) |
| 17:17:50 | Latency slow burn pending (+24 min 59 s) |
| 17:22:50 | **Latency slow burn firing: ticket** (+29 min 59 s) |
| 17:23:35 | `latency_ms` set back to 0 |
| 17:28:58 | Latency fast burn back to normal (5 min 23 s after the fix) |
| 17:53:53 | Latency slow burn back to normal (30 min 18 s after the fix) |

## Results

| Measure | Value |
|---|---|
| Time to page | 15 min 04 s |
| Time to ticket | 29 min 59 s |
| Page cleared after the fix | 5 min 23 s |
| Ticket cleared after the fix | 30 min 18 s |
| Slow requests (> 250 ms) | about 17,300 (about 9.6 per second for 30 minutes) |
| Latency error budget used | **6.7%** of the 30-day budget (259,200 slow requests allowed at 10 requests/second) |
| p99 latency during the drill | about 0.49 s (normally a few milliseconds) |

## Findings

**1. Both tiers behaved as designed.** A full latency regression paged after
15 minutes. The slow burn, meant for sustained, lower-level budget consumption,
opened a ticket only after 30 minutes of every request being slow. After the
fix, the page cleared in about 5 minutes and the ticket in about 30, because each
alert clears once its short window (5 minutes and 30 minutes respectively) no
longer contains the slow requests.

**2. Detection time depends on the traffic in the long window.** The page came
about 4 minutes later than estimated. The hour before the drill most likely
carried more normal traffic than usual (about 14 requests/second, because two
copies of the previous load generator were still running), so the slow requests
took longer to reach 14.4% of the 1-hour window. Burn-rate alerts are relative to
request volume: heavier traffic before an incident delays detection, and a drop
in traffic (for example at night) speeds it up.

**3. Coordinated omission avoided.** The open-loop generator held about 9.6
requests/second while every response took 400 ms. A closed-loop generator would
have dropped to about 2 per second and hidden most of the impact.

**4. The latency histogram is coarse around the threshold.** The app's buckets
jump from 0.25 s to 0.5 s, so all drill requests (0.32–0.48 s) fell into the same
bucket, and the reported p99 of about 0.49 s is an interpolation artifact rather
than a measured value. The SLI itself is exact, because 0.25 s is a bucket
boundary, but more buckets near the threshold (for example 0.2 s and 0.3 s)
would make latency percentiles meaningful.

## Open items

- [ ] Drill 4: a slow-burn-only incident (for example 5% errors for about 40
      minutes). The ticket should fire and the page should not.
- [ ] Add histogram buckets around the 250 ms threshold (finding 4).
