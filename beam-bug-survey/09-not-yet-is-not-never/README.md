# 09 — "Not yet" read as an answer

> *AI-generated: Claude Sonnet 5.5, effort unrecorded; first generated 2026-11-16, last edited 2026-11-16. Source readings are summaries of survey fixes; see "Sources" for what was read.*

**Verdict:** helps avoid (separate the worlds: gate on the callee's readiness; or fit every world: retry on "not ready"). The first tick is a policy.
**Topics:** ordering (startup, admission).

## Scenario
A node accepts a join while its own startup is still running, so the cluster state diverges. Or a joining node copies configuration from a peer that
has not finished booting and treats the peer's transient "not ready" as a hard failure that crashes it. In both, a state that is **about to change** is
read as one that will not.

## Interaction
```
 joiner                      peer (still booting)
   | -- give me config ------>  not_ready          <- transient
   | crash (read as final)
 ... peer finishes booting 40 ms later ...
```

## Erlang
[`not_yet_is_not_never.erl`](not_yet_is_not_never.erl): `join_buggy/join_gated`, `copy_buggy/copy_knowing/copy_retrying`. `make demo M=not_yet_is_not_never`.

## The layer in four lines
- **View.** The caller has a reply "not ready", or no evidence of readiness.
- **Worlds.** W1: the peer will be ready soon. W2: it will not.
- **What the code does.** Acts as if W2 (a hard failure), or admits as if the callee were ready.
- **What is missing.** The callee can often *say* it is not ready (`init:get_status/0` for itself; a membership view for peers). The state that will change is
  read as a state that will not.

## What helps
- **Avoid, separate the worlds:** a readiness fact the agent can read (gate admission on it, or choose only peers known to be running).
- **Avoid, fit every world:** `not_ready` is retryable, `down` is not; retry with a bound.
- **A policy remains:** at the very first moment nothing separates "booting" from "broken"; how long to wait is a choice (as the leader's grace period).
- **Detect:** a monitor holding the startup protocol (which state a node must reach before it may be admitted) flags an admission that precedes readiness.

## Needs
A boot-stage state on a node (a node that sleeps before it answers); an announcement of readiness.

## Sources
Accepted in all three passes under Startup / Initialisation Ordering.
- `basho/riak_core#764`, fix `c622100291cb508ff4aa8245a69438852411771d`. Diff read.
- `emqx/emqx#7728`, fix `14e0296221e8d80e58d9f15f7163f032afe44e4a`. Reviewer text only; flagged in one pass.
- Same shape, not read: `bitwalker/swarm#43`, `basho/riak_kv#1532`, `akira/exq#196`, `zotonic/zotonic#4367`.
