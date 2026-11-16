# 03 — Alive a moment ago (check, then call)

> *AI-generated: Claude Sonnet 5.5, effort xhigh; first generated 2026-11-16, last edited 2026-11-16. Source readings are summaries of survey fixes; see "Sources" for what was read.*

**Verdict:** helps avoid (separate the worlds: subscribe to a fact that lasts). One variant fits every world.
**Topics:** races (process death), check-then-act. **Lead card for the discussion** (with [04](../04-entry-race/README.md) as its foil).

## What is in this card
Two files for part A and the same file for a parked part B.

| File | What it is |
|---|---|
| [`alive_a_moment_ago.erl`](alive_a_moment_ago.erl) | **The code.** Part A: a caller that checks the server is alive and then calls it (`call_checked/3`), and one that monitors and then calls (`call_monitored/3`). `run(Variant, KillAt)` runs either one against an **explicit environment**: a server that handles a request only when released, and a driver that kills it at one chosen point. Part B: `spawn_then_monitor/1` and `spawn_monitor_/1` (parked). |
| [`check_then_call_model.erl`](check_then_call_model.erl) | **The same interaction as a model**, with three roles (caller `c`, server `s`, environment `e`), every ordering of their steps tried, the caller's view recorded, and what it knows computed. `conformance/0` runs the code for each case and compares it with the model's prediction. |

Variants are named for what they do: `liveness_check` (check `is_process_alive`, then send) and `monitor` (monitor, then send).
The model was written by hand from the code. It is not extracted from it; `conformance/0` is the check that they agree.

## How the model corresponds to the code
The code's `run/2` chooses *where* the server is killed. The model enumerates the same five places. For each one the model predicts the caller's outcome, and the code returns it (all ten pairs agree; `make demo M=check_then_call_model` prints the table).

| Kill position | What happens | `liveness_check` | `monitor` |
|---|---|---|---|
| `before_first_step` | server already dead when the caller starts | `{error,noproc}` | `{error,noproc}` (monitor on a dead process: DOWN with `noproc`) |
| `after_first_step` | dies after the check (or monitor), before the send | **hang** | `{error,killed}` |
| `after_send` | dies after the send, before handling the request | **hang** | `{error,killed}` |
| `after_reply` | handles and replies, then dies | `ok` | `ok` (reply arrives before the DOWN) |
| `after_done` | dies after the caller has finished | `ok` | `ok` |

The two hangs are the bug. In the model the caller's *view* in each hang equals its view in a world where the server is alive and about to reply, so nothing the caller does can separate them. In the `monitor` variant every run ends with a reply or a DOWN in the caller's view, and the caller **knows** the server is dead exactly when a DOWN is there.

The demo in the previous version of the card corresponded to just one of these: the server dying on its first request is `after_send`.

## The context, and how much of it is now explicit
What the surrounding context contributes:
1. **Who can falsify the fact, and when.** Explicit now, in code (the driver's kill position) and in the model (role `e`). In real systems it is some other process or event (a crash, a supervisor, a peer's disconnect) that a call site cannot see; it is a question about the whole program.
2. **What channel carries news of the falsification to the caller.** Explicit: none in `liveness_check`, a DOWN in `monitor`.
3. **How fine the fact is.** *Described only, not modelled.* "This pid is dead" is stable. "The service is down" is not, if a supervisor can restart it under the same name: a name is a rebinding, so a check on a registered name is unstable in both directions. The stable fact is about an identity (a pid, a reference).

## Part B (parked): the monitor that lost the reason
`spawn_then_monitor` lets the child finish before the monitor is set. The monitor then reports `noproc`, which says the process is gone but not *why*: the **exit reason is lost**, and that is the information a monitor exists to deliver. `noproc` is therefore the intended buggy result; `spawn_monitor_` keeps the reason (`finished_badly`). This is a different shape from part A (information acquired too late, and of lower quality), so it waits.

## The layer in four lines
- **View.** The caller saw "alive" at time t1.
- **Worlds.** W1: still alive at the send. W2: died between the check and the send. W3: died after the send, before handling.
- **What the code does.** Acts as if W1.
- **What is missing.** "Alive" is an **unstable** fact; knowing it at t1 gives nothing at t2. "Dead" is **stable**, so a *standing* subscription to it is reliable: a monitor delivers DOWN even if the process is already dead.

## What helps
- **Avoid, separate the worlds:** the monitor (the model and the code agree that no run ends in a view that mixes dead and alive).
- **Avoid, fit every world** (hackney's fix): catch the failure and try the next connection; the caller stays uncertain and acts correctly either way.
- **Detect:** an *observing* monitor sees the request go out and nothing come back, and cannot tell dead from slow; at best it ranks the explanations (a belief). A stronger statement needs schedule exploration, which is what the model does. An *enforcement* monitor is a different thing (it would intervene), see the devlog's discussion of monitor kinds.
- **Static recognition:** a liveness check followed by a send or call on the same pid is a recognisable candidate, but whether it is a bug depends on context item 1.

## Needs (mechanisation)
Links/monitors and exit reasons; a process dying inside a node; an environment that can kill (none exists in the calculus today). The model uses none of the calculus.

## Sources
All accepted in all three passes. Diffs read for the first three.
- `atomvm/AtomVM#572`, fix `913aa330fcbd619e5e78c27b31b464dcdd03c6f7` (Awaited Message Never Arrives): `port:call` with a monitor.
- `benoitc/hackney#869`, fix `33351f2c0117e0ac1f4b690b4ffb7ce131c6cb96` (Process Death Races; Check-Then-Act): catch and try the next connection.
- `erlang/otp@f6bb3dc325e686375b1dee283bd91c3068b682a1` (Process Death Races): `spawn` + `monitor` to `spawn_monitor` (part B).
- Reviewer text only: `emqx/emqx#4834` (`f1dcb35f53e33ba73d068a6155b7b456779b5389`), `vernemq/vernemq#659` (`68d92b1d1c2429e469e2bfcba1be12c187d0e9bc`).
