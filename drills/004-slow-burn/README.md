# Drill 4: Slow burn (ticket, no page)

**Date:** 1 Oct 2026 (first attempt 30 Sep, invalid)
**Fault:** `error_rate = 0.05` (5% of requests return 500), steady
**Goal:** a mild, sustained error rate should open a ticket (slow burn, 6×) at about 5% of the monthly budget consumed, and never page (fast burn, 14.4×).

## Outcome: pass

The slow burn went Pending at T + 3 h 22 m and Firing at T + 3 h 27 m, and the notification reached Discord. The fast burn did not fire. About 6,650 requests failed in total, 5.1% of the 129,600-request monthly budget. The ticket resolved 13 m 57 s after the fault was removed, inside the 12–15 minute prediction.

## Results against the plan

| | Expected | Actual (IST) | Since start |
|---|---|---|---|
| Errors on | — | 12:25:32 | 0 |
| Slow burn Pending | T + 3 h 36 m | 15:47:35 | 3 h 22 m |
| Slow burn Firing (Discord) | T + 3 h 41 m | 15:52:35 | 3 h 27 m |
| Errors off | — | 16:19:38 | 3 h 54 m |
| Slow burn back to Normal | 12–15 min after stop | 16:33:35 | 13 m 57 s after stop ✓ |
| Failed requests | ~6,700 | ~6,650 | 5.1% of 129,600 ✓ |

Pending to Firing took exactly the 5-minute pending period.

## Timeline (IST)

| Time | Event |
|---|---|
| 12:25:32 | `error_rate` set to 0.05 on pc1, with a 5 h safety timer |
| ~12:45 | 30m ratio crosses 3% (short window armed) |
| 15:47:35 | 6h ratio crosses 3%: slow burn → Pending |
| 15:52:35 | Slow burn → Firing, Discord notification received |
| 16:19:38 | `error_rate` set to 0.0, safety timer cancelled |
| 16:33:35 | 30m ratio falls below 3%: slow burn → Normal |

## Findings

### 1. Both availability alert rules had wrong expressions, and only this drill could catch it

The fast and slow rules had the same query: 6h/30m windows with a 0.072 threshold. The slow burn's threshold was 2.4× too high, and the fast burn used slow-burn windows. On 30 Sep the 6h ratio reached 3.7%, well above the real 3% threshold, and the ticket never fired. Drills 1 and 3 used error rates well above 7.2%, which crossed both thresholds and hid the bug.

The rules were corrected on 1 Oct, 09:27 IST:

```promql
# Fast burn (page)
(slo:availability_errors:ratio_rate1h > bool 0.072) * (slo:availability_errors:ratio_rate5m > bool 0.072)

# Slow burn (ticket)
(slo:availability_errors:ratio_rate6h > bool 0.03) * (slo:availability_errors:ratio_rate30m > bool 0.03)
```

**Lesson:** a drill that only uses big failures can't test the thresholds. Each burn rate needs a drill that sits between its threshold and the next one.

### 2. The fast burn rule had no contact point

Its contact point was "empty". Even with a correct query, a real page would have notified no one.

### 3. Editing rules mid-drill caused No Data states

On 30 Sep, alert rules were edited during the run, replacing the `> bool … * …` form with an `and` form and a placeholder metric name. Rules built with `> bool` and `*` always return 0 or 1, so No Data only appears when metrics are actually missing. Rules built with `and` return nothing when healthy.

**Lesson:** freeze alert rules during a drill, and keep the `> bool` form.

### 4. The safety timer failed silently on 30 Sep

It should have turned the errors off at 23:37 IST. It didn't, and with output going to `/dev/null` there's no record of why. It was most likely killed when the WSL session closed.

**Fix:** log to `~/drill-timer.log` and keep the terminal open. This worked on 1 Oct.

### 5. The ticket fired 14 minutes earlier than modelled

The total error ratio was right, at about 5%. At ~9.5 req/s, a full 6h window should need ~6,150 failures to reach 3%. The rule went Pending at ~5,740 failures, which means the window held about 7% fewer requests than a full one. That points to a traffic gap or a late load-generator start during the warm-up (09:47–12:25 IST).

**Lesson:** the warm-up only needs 2.4 h of clean traffic (6 h − 3.6 h), but the traffic has to be continuous. Check the request-rate graph before starting:

```promql
sum(rate(http_requests_total{namespace="slo-demo"}[5m]))
```

### 6. The latency recording rules return no data

`slo:latency_slow:ratio_rate*` showed No data in the rule previews, so the latency alerts currently can't fire. This doesn't affect Drill 4, but it needs a fix before any latency drill.

## Follow-ups

- [ ] Set the availability fast burn contact point (to Discord or a dedicated paging channel)
- [ ] Add `summary` and `runbook_url` annotations to all four rules, since notifications currently contain only labels
- [ ] Investigate the missing `slo:latency_slow` recording-rule data
- [ ] Confirm availability fast and both latency rules show no transitions between 12:25 and 16:35 IST
- [ ] Add a pre-drill checklist: rule expressions verified, no rule edits during the run, request rate continuous for ≥ 2.4 h, one load generator, timer logging to a file
