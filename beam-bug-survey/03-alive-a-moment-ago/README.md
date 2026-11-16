# 03 — Alive a moment ago (check, then call)

> *AI-generated: Claude Sonnet 5.5, effort xhigh; first generated 2026-11-16, last edited 2026-11-16. Source readings are summaries of survey fixes; see "Sources" for what was read.*

**Verdict:** helps avoid (separate the worlds: subscribe to a fact that lasts). One variant fits every world.
**Topics:** races (process death), check-then-act. **Lead card for the discussion** (with [04](../04-entry-race/README.md) as its foil).

## What this card is, and is not
It has **two files and two different shapes**; the first is the lead.
- **A. Check, then call** (`alive_a_moment_ago.erl`: `call_checked` / `call_monitored`; and the explicit-context model `check_then_call_model.erl`). A caller checks that a
  server is alive, sends it a request and waits for the reply. This is the check-then-act shape.
- **B. Spawn, then monitor** (`spawn_then_monitor` / `spawn_monitor_`). A *different* shape (information acquired too late, and of lower quality), parked for now.
  In the demo the child finishes before the monitor is set, so the buggy variant returning `noproc` **is** the intended result (the real exit reason `finished_badly` is lost);
  the fixed variant returns `finished_badly`. The demo's keys now say which is which.

**The card does not do any epistemic work itself.** `alive_a_moment_ago.erl` shows the bug and the fix as code; the epistemic reading below is commentary.
`check_then_call_model.erl` is the first attempt to do the work in code, on a model written *by hand from the card*, not extracted from the Erlang.

## The context that the plain demo hides
In `alive_a_moment_ago.erl` the server kills itself on its first request (`dying_server/0`), so *who* kills it and *when* is baked in. What matters about the context is exactly this:
1. **Who can falsify the fact, and when**: some other process or event (a crash, a supervisor, a peer's disconnect). It is not part of the caller's code, and a static look at the
   call site cannot see it; it is a question about the whole program.
2. **What channels carry news of the falsification to the caller**: none in the buggy code, a monitor's DOWN in the fixed code.
3. **How fine the fact is.** "This pid is dead" is stable. "The service is down" is not, if a supervisor restarts it under the same name: a *name* is a rebinding, so a
   check on a registered name is unstable in both directions. The stable fact is about an **identity** (a pid, a reference), not about the service.

The model makes 1 and 2 explicit with three roles and tries every ordering of their steps:

```
 c  caller        buggy: check, send, await         fixed: monitor, send, await
 s  server        handles a request if alive and one is waiting
 e  environment   kills the server, once, at any point
```
`make demo M=check_then_call_model` prints, for each variant, the complete runs, the hangs, and the views in which the caller *knows* the server is dead:

| | complete runs | hangs | hangs the caller cannot tell from a live server | views where the caller knows the server is dead |
|---|---|---|---|---|
| buggy (check) | 5 (`ok` ×2, `{error,noproc}`, hang ×2) | 2 | 2 | `[{check,dead}]` only |
| fixed (monitor) | 5 (`ok` ×2, `{error,killed}` ×2, `{error,noproc}`) | 0 | 0 | any view ending in a DOWN |

The two hangs are the runs where the server dies after the check (before the send, or before it handles the request). The caller's view in each is *the same* as in a world where
the server is alive and about to reply, so no rule the caller follows can separate them. After the fix, every way the run can end puts a reply or a DOWN into the caller's view.

## Interaction (part A)
```
 caller                          server                     environment
   | is_process_alive? -> true
   |                              | (killed here, or here)  <- e
   | -- request ------------------>  dropped / unhandled
   | waits ... forever
```
Fixed: `monitor`, then send, then wait for reply **or** DOWN.

## The layer in four lines
- **View.** The caller saw "alive" at time t1.
- **Worlds.** W1: still alive at the send. W2: died between the check and the send. (W3, in the model: died after the send, before handling.)
- **What the code does.** Acts as if W1.
- **What is missing.** "Alive" is an **unstable** fact; knowing it at t1 gives nothing at t2. "Dead" is **stable**, so a *standing* subscription to it is reliable: a monitor
  delivers DOWN even if the process is already dead.

## What helps
- **Avoid, separate the worlds:** the monitor (the model confirms it: no run ends in a view that mixes dead and alive).
- **Avoid, fit every world** (hackney's fix): catch the failure and try the next connection; the agent stays uncertain and acts correctly either way.
- **Detect, statically:** a liveness check followed by a send or call on the same pid is a recognisable pattern, but whether it is a *bug* depends on context item 1 (something must be able to
  kill the server). A purely local check can flag it as a candidate only.
- **Detect, dynamically:** a monitor of the interaction that sees the caller's request and no reply or DOWN cannot tell dead from slow; to catch it, schedule exploration (as the model does) is needed.
- **Quality of information:** `noproc` is hard but poorer than the true reason (part B).

## Needs (mechanisation)
Links/monitors and exit reasons; a process dying inside a node; an environment that can kill (neither exists in the calculus today). The model above uses none of the calculus.

## Sources
All accepted in all three passes. Diffs read for the first three.
- `atomvm/AtomVM#572`, fix `913aa330fcbd619e5e78c27b31b464dcdd03c6f7` (Awaited Message Never Arrives): `port:call` with a monitor.
- `benoitc/hackney#869`, fix `33351f2c0117e0ac1f4b690b4ffb7ce131c6cb96` (Process Death Races; Check-Then-Act): catch and try the next connection.
- `erlang/otp@f6bb3dc325e686375b1dee283bd91c3068b682a1` (Process Death Races): `spawn` + `monitor` to `spawn_monitor` (part B).
- Reviewer text only: `emqx/emqx#4834` (`f1dcb35f53e33ba73d068a6155b7b456779b5389`), `vernemq/vernemq#659` (`68d92b1d1c2429e469e2bfcba1be12c187d0e9bc`).
