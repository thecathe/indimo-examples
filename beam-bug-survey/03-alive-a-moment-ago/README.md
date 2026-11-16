# 03 — Alive a moment ago

> *AI-generated: Claude Sonnet 5.5, effort unrecorded; first generated 2026-11-16, last edited 2026-11-16. Source readings are summaries of survey fixes; see "Sources" for what was read.*

**Verdict:** helps avoid (separate the worlds: subscribe to a fact that lasts). One variant fits every world.
**Topics:** races (process death), check-then-act.

## Scenario
Code checks `is_process_alive(Pid)`, then sends a request and waits for the reply. If the process dies after the check, nothing wakes the
caller. A second form: `spawn` then `monitor`; if the child exits first, the monitor reports `noproc` and the real exit reason is lost.

## Interaction
```
 caller                         server
   | is_process_alive? -> true
   |                              | (dies)
   | -- request ------------------>  (dropped; nobody replies)
   | waits ... forever
```
Fixed: `monitor`, then send, then wait for reply **or** DOWN. For spawn: `spawn_monitor` (the monitor exists before the child can die).

## Erlang
[`alive_a_moment_ago.erl`](alive_a_moment_ago.erl): `call_checked/2` against `call_monitored/2`; `spawn_then_monitor/1` against `spawn_monitor_/1`.
`make demo M=alive_a_moment_ago`.

## The layer in four lines
- **View.** The caller saw "alive" at time t1.
- **Worlds.** W1: still alive at the send. W2: died between the check and the send.
- **What the code does.** Acts as if W1.
- **What is missing.** "Alive" is an **unstable** fact (it can become false unobserved), so knowing it at t1 gives nothing at t2. "Dead" is
  **stable** (once true, always true), so a *standing* subscription to it is reliable: a monitor delivers DOWN even if the process is already dead.

## What helps
- **Avoid, separate the worlds:** the monitor. Compare [04](../04-entry-race/README.md): the same family (check-then-act), a different verdict,
  because here the fact the agent needs has a stable side it can subscribe to.
- **Avoid, fit every world** (hackney's fix): catch the failure and try the next connection. The agent stays uncertain but acts correctly either way.
- **Detect:** *statically*, a liveness check followed by a send or call on the same pid is a recognisable pattern (knowledge that expires,
  used after it expires). At run time a proxy monitor sees the request go out and no reply or DOWN come back, but cannot tell dead from slow.
- **Quality of information:** `noproc` is hard but poorer than the true reason; the atomic `spawn_monitor` keeps the better one.

## Needs
Links/monitors and exit reasons, and a process dying inside a node (neither exists in the calculus today).

## Sources
All accepted in all three passes. Diffs read for the first three.
- `atomvm/AtomVM#572`, fix `913aa330fcbd619e5e78c27b31b464dcdd03c6f7` (Awaited Message Never Arrives): `port:call` with a monitor.
- `benoitc/hackney#869`, fix `33351f2c0117e0ac1f4b690b4ffb7ce131c6cb96` (Process Death Races; Check-Then-Act): catch and try the next connection.
- `erlang/otp@f6bb3dc325e686375b1dee283bd91c3068b682a1` (Process Death Races): `spawn` + `monitor` to `spawn_monitor`.
- Reviewer text only: `emqx/emqx#4834` (`f1dcb35f53e33ba73d068a6155b7b456779b5389`), `vernemq/vernemq#659` (`68d92b1d1c2429e469e2bfcba1be12c187d0e9bc`).
