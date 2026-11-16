# 06 — The retry layer that did not know it was nested

> *AI-generated: Claude Sonnet 5.5, effort unrecorded; first generated 2026-11-16, last edited 2026-11-16. Source readings are summaries of survey fixes; see "Sources" for what was read.*

**Verdict:** helps avoid (separate the worlds: tell the inner layer; or a policy that treats the inner layer's giving-up as final). Detect: static, from the structure.
**Topics:** failure escalation (the wider sense: compounding retry layers).

## Scenario
Two layers each retry the same operation, so attempts **multiply**. Two real forms:
- A transaction retry inside the caller's *own* transaction: the caller holds the lock behind the conflict, so retrying inside a savepoint can never
  succeed until the *outer* transaction ends; it re-collides, then reports a misleading timeout. The fix: the caller passes `retry: false`.
- A wrapper supervisor with its own default restart budget around an inner supervisor. When the inner one exhausts its budget and terminates, the wrapper
  restarts it with a **fresh** budget, so restarts multiply. The fix: the wrapper's intensity is set to 0, so the inner's giving up is final.

## Interaction
```
 outer layer (3 retries)  --attempt-->  inner layer (5 retries)  --attempt-->  operation (always conflicts)
 each outer attempt triggers up to 6 inner attempts: 4 x 6 = 24 attempts, not 4 or 6
```

## Erlang
[`nested_retry_layers.erl`](nested_retry_layers.erl): 24 attempts when blind, 4 when the inner layer is told. `make demo M=nested_retry_layers`.

## The layer in four lines
- **View.** The inner layer sees an operation that failed with a conflict.
- **Worlds.** W1: the conflict is transient (another transaction will finish). W2: it will last until the *outer* layer ends.
- **What the code does.** Acts as if W1 and retries.
- **What is missing.** The caller knows which world it is in (`nested`), and the inner layer does not: a missing piece of *context*. In the supervisor form, the
  inner supervisor's exhaustion is hard evidence ("the fault outlasted this many retries") that the wrapper reads as soft ("try again").

## What helps
- **Avoid:** pass the knowledge down (a flag), or treat the lower layer's give-up as final. Both separate the worlds.
- **Detect:** a monitor that holds the structure (two layers, budgets 3 and 5) can compute the worst-case attempt count (24) before anything runs, and
  compare it with attempts observed per request. A static, knowledge-map inference.
- **Mutual knowledge of the policy** is what is missing: each layer would have to know the other retries.

## Needs
Restart budgets and supervision (links, monitors) for the second form; the first needs only retry with a counter.

## Sources
Accepted in all three passes. Diffs read.
- `oban-bg/oban@cbd74ab67fc388a7091a0f115199e715e176277e` (Non-Converging Restart Loop; the reviewers tag it "avoids, does not fix"). Also `oban-bg/oban@afcb7711ee39672eac49293af9ecba0a10cf18fc` (Compounding Retry Layers; reviewer text only).
- `elixir-horde/horde@74820c24362efcc41124eeb5ff7bb40043503f55` (Compounding Retry Layers).
