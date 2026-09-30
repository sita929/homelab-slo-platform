# Drill 1: error injection (2026-09-30)

**SLO context.** 99.5% availability over 30 days (129,600 failures allowed at 10 requests/second). Fast burn alert (page) at 7.2% error rate over 1 hour; slow burn alert (ticket) at 3% over 6 hours.

**What was done.** With steady load of about 10 requests/second from the laptop, `error_rate` was set to 0.5 at 10:25:20 IST (04:55:20 UTC) and back to 0.0 at 10:42:03 IST (05:12:03 UTC): 16 minutes 43 seconds of 50% errors.

| Time (IST) | Event |
|---|---|
| 10:25:20 | 50% errors injected |
| 10:34:35 | Slow burn pending |
| 10:36:30 | Fast burn pending |
| 10:37:30 | Fast burn firing (page), 12 min 10 s after injection |
| 10:39:37 | Slow burn firing (ticket) |
| 10:42:03 | Errors switched off |
| 10:47:30 | Fast burn back to normal, 5 min 27 s after the fix |
| ~11:10 | Slow burn back to normal |

**Budget used.** About 5,000 failed requests (estimate), roughly 4% of the 30-day error budget (129,600 failures allowed at 10 requests/second).

**Observations.**

- Time to page was 12 minutes, about 1 minute of which was the ConfigMap change reaching the pods. That matches the design: at 50% errors, the 1-hour window needs about 9 minutes of errors to pass the 7.2% threshold. A total outage would page in roughly 5 minutes.
- The slow burn fired before the fast burn because Prometheus had less than 6 hours of traffic history, so the 6-hour window behaved like a short one while its threshold (3%) is lower. With a full 6 hours of history, the slow burn needs about 22 minutes of 50% errors before it even goes pending, so it would not have fired during this drill at all.
- The page cleared within 6 minutes of the fix; the ticket stays open for about 28 minutes because its short window is 30 minutes. Pages resolve fast, tickets linger: intended.

**Follow-ups.**

- [ ] Re-run once Prometheus has more than 6 hours of steady traffic to confirm the fast burn pages first and the slow burn stays quiet.
