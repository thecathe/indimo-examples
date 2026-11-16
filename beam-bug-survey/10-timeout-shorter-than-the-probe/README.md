# 10 — A timeout shorter than the probe's own budget

> *AI-generated: Claude Sonnet 5.5, effort unrecorded; first generated 2026-11-16, last edited 2026-11-16. Source readings are summaries of survey fixes; see "Sources" for what was read.*

**Verdict:** helps avoid (a policy: align the bounds); detect: static, from configuration. **Topics:** grey failures.

## Scenario
The caller of a channel health check waited a fixed 5 s. The probe itself was allowed longer. A slow but healthy probe read as a failure. This is the earlier
survey's own definition of a grey failure: the detector and the client "apply a different threshold to the same signal".

## Interaction
```
 caller                          probe (allowed 500 ms, takes 200 ms)
   | -- probe ------------------>  ...
   | waits 50 ms -> "down"
   |                              | replies healthy at 200 ms   <- lands in the mailbox, read by nobody
```

## Erlang
[`timeout_vs_probe.erl`](timeout_vs_probe.erl). `make demo M=timeout_vs_probe`.

## The layer in four lines
- **View.** Silence for 50 ms.
- **Worlds.** W1: the probe is slow (the paper's *slowdown*, weight 1). W2: it is down (weight 2).
- **What the code does.** Believes W2.
- **What is missing.** Silence is consistent with both; only a bound set from the probe's own budget lets silence be evidence for W2. The caller and the probe disagree on
  how long "slow" may last.

## What helps
- **Avoid:** use the probe's configured budget as the caller's bound; thereafter silence past the budget is evidence of a failure.
- **Detect:** a monitor holding the configuration can check, before runtime, that every caller's bound is at least the budget of the probe it waits on. A
  stale reply that later arrives with nobody waiting is a second symptom: evidence that outlives its question.
- **Link to the model:** the weights of the model (`epistemic-plausibility`'s ranking by the severity of the failure scenario) make the
  gap concrete: a 50 ms wait ranks "down" as the more plausible reading of silence that a 200 ms probe would explain as "slow".

## Needs
A slowdown failure and a receive with timeout (the calculus has both); nothing new.

## Sources
`emqx/emqx@5d0ec0390e58ec25196c3ae3dad832befe2b6b4e`, accepted in all three passes under Timeout Bounds the Wrong Interval. Diff read in part.
**The true grey failures are the earlier survey's**, not new here (the newer passes have no Grey Failure family): the silent websocket (`firezone/firezone#1974`), the vnode that said ok
(`basho/riak_kv#1106`), the shared keepalive counter (`emqx/emqx#8866`), the leader that resigned at once (`WhatsApp/waraft@c207562e36e525c43b7e12ab084698b626fd14e0`) and the late
health check (`emqx/emqx#14001`, `#14319`).
