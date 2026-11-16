# 07 — What licenses a retry: knowing it never happened, or assuming it is harmless

> *AI-generated: Claude Sonnet 5.5, effort xhigh; first generated 2026-11-16, last edited 2026-11-16. Source readings are summaries of survey fixes; see "Sources" for what was read.*

**Verdict:** helps avoid (separate the worlds, with an error that carries "never sent"); the alternative is an assumption, a policy.
**Topics:** failure escalation (transient failure treated as permanent).

## Scenario
A cold connection pool fails the first requests after a deploy with `pool_not_available`; the condition heals. The default retry rule retries only
GET and HEAD, so POSTs failed for good and a whole sync failed. The fix did two different things: it retried **everything** transient
("these are safe to retry"), and it added a rule for two reasons that mean the request was never processed.

## Interaction
```
 client                       pool / server
   | POST ----------------------> pool_not_available   (never left)   -> safe to retry, whatever the method
   | POST ----------------------> ... timeout           (may have run)  -> retrying may repeat an effect
```

## Erlang
[`retry_licence.erl`](retry_licence.erl): three rules side by side. `make demo M=retry_licence`.

## The layer in four lines
- **View.** The client sees a failure.
- **Worlds.** W1: the request had no effect. W2: it may have executed (reply lost, timeout).
- **What the code does.** The default rule decides by method alone. The assumption rule retries all.
- **What is missing.** A timeout cannot separate W1 from W2, so retrying a non-idempotent request after one is a *gamble*. The error type `pool_not_available` does
  separate them, but only if the error carries it.

## What helps
- **Avoid, separate the worlds:** typed errors that say "not sent" or "unprocessed". Safe for any method.
- **Avoid, an assumption:** declare operations idempotent. Fine until someone adds a non-idempotent one; the layer names that as the risk.
- **Detect:** a monitor that knows each operation's declared idempotence and sees each retry can flag "a retry of a possibly-executed non-idempotent request".
  It needs the reason of each failure, which a message-level proxy sees only if the error is in the reply.

## Needs
Fresh identities if the duplicate effect is to be shown; otherwise a flag on the request.

## Sources
`firezone/firezone#13802`, fix `bd47d8d692377006dee374b53f8301b6a166040f`, accepted in all three passes (Startup / Initialisation Ordering; Transient Failure Treated as Permanent). Diff read.
The reviewers note that the change retries the symptom and leaves the cold-pool race in place.
