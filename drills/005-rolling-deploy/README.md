# Drill 5: rolling deployment under load (2026-10-01)

## What was done

Deployments are one of the most common causes of real incidents, so this drill
checks whether a routine release costs any error budget. With steady load from
the laptop (about 7 requests/second, every request logged with its status code
and the node that answered, using `scripts/load.sh`), the service was restarted
three times with `kubectl rollout restart`, one minute apart.

The Deployment replaces one replica at a time (`maxUnavailable: 1`,
`maxSurge: 0`, because each replica needs host port 18080). Before a pod stops,
a 5-second `preStop` pause gives Traefik time to stop routing to it, and the app
stops accepting new connections on SIGTERM.

The load log covers **23:21:33–23:26:25 IST (17:51:33–17:56:25 UTC)**, which
spans all three rollouts.

## Results

| Measure | Value |
|---|---|
| Requests during the drill | 2,053 |
| **Failed requests** | **0** |
| Requests served by a single replica during switches | 358 |
| Time each replica was out of rotation | 6–11 s |
| Duration of one full rollout | about 17–19 s |
| Moments with both replicas out of rotation | none |

Because Traefik alternates strictly between the two replicas, a run of
consecutive responses from the same node shows that the other replica was out of
rotation. The six runs in the load log, two per rollout (times in IST):

| Rollout | Replica out of rotation | Duration | Requests served by the other replica |
|---|---|---|---|
| 1 | pc1, 23:23:08–23:23:16 | 8 s | 57 |
| 1 | pc2, 23:23:16–23:23:27 | 11 s | 75 |
| 2 | pc2, 23:24:33–23:24:44 | 11 s | 80 |
| 2 | pc1, 23:24:46–23:24:52 | 6 s | 43 |
| 3 | pc1, 23:25:57–23:26:05 | 8 s | 57 |
| 3 | pc2, 23:26:05–23:26:11 | 6 s | 46 |

## Findings

**1. Deployments cost no error budget at this load.** All 2,053 requests
succeeded, including the 358 that arrived while one replica was being replaced.
The `preStop` pause, the one-at-a-time rollout and the readiness probe together
moved traffic away from each replica before it stopped, and back once its
replacement was healthy.

**2. The rollout never removed both replicas.** The out-of-rotation windows
follow each other directly: a replica is only taken out once the other one's
replacement is ready. Which node goes first varies between rollouts (rollout 2
started with pc2).

**3. Each replica is out of rotation for 6–11 seconds.** That is the 5-second
`preStop` pause, plus startup, plus waiting for the first successful readiness
probe. The probe runs every 5 seconds, which explains most of the variation. A
shorter probe period would shorten these windows.

**4. Every rollout halves capacity for about 15–20 seconds.** During each switch,
one replica serves all traffic. At 7 requests/second that is harmless, but it
means peak load must fit on a single replica, or releases must avoid peak times.

## Limits of this test

The load generator sends one request at a time over a fresh connection, at about
7 requests/second. Under heavier, concurrent traffic, a request can be in flight
on a reused connection at the moment a replica shuts down, which this test would
not catch. A follow-up run with concurrent open-loop load and per-request logging
would check for that.

## Open items

- [ ] Repeat with concurrent load (for example 50 requests/second) to look for
      failures on connections that are open while a replica shuts down.
- [ ] Shorten the readiness probe period to reduce the single-replica windows
      (finding 3).
