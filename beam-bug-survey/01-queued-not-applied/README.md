# 01 — The return that meant only "queued"

> *AI-generated: Claude Sonnet 5.5, effort unrecorded; first generated 2026-11-16, last edited 2026-11-16. Source readings are summaries of survey fixes; see "Sources" for what was read.*

**Verdict:** helps avoid (separate the worlds: make the acknowledgement mean more). Detect: at test time only.
**Topics:** asynchronous effect visibility.

## Scenario
A server owns some state (a list of hooks, a dispatch table) that readers consult **directly**, not through the server. A
caller asks the server to change it with a `cast`, which returns as soon as the request is queued. A reader that runs right after
the caller's call returns can still see the old state. The symptom is a value that is right a moment later and wrong at the
instant it is read, and the bug vanishes whenever anything slows the reader down.

## Interaction
```
 caller               server (busy)                reader (reads the table directly)
   | -- cast del(a) ---> [queued]
   | <-- ok ------------|
   |  "a is gone"       |
   | ------------------ read ----------------------->  sees a   <-- wrong
   |                    | apply del(a); table changes
```
Fixed: `call`; the server replies **after** applying, so the reader's read happens-after the write.

## Erlang
[`queued_not_applied.erl`](queued_not_applied.erl): `del_async/1` (buggy), `del_sync/1` (fixed). `make demo M=queued_not_applied`.

## The layer in four lines
- **View.** The caller has received `ok`.
- **Worlds it cannot tell apart.** W1: the request is queued and not applied. W2: it is applied.
- **What the code does.** Acts as if W2.
- **What is missing.** The acknowledgement entails "queued" and not "applied": `K(ok) ⊨ queued`, `K(ok) ⊭ applied`. The fix changes the
  reply so that `K(ok) ⊨ applied`.

## What helps
- **Avoid, separate the worlds:** strengthen the acknowledgement (cast to call; a barrier). A reader that cannot be changed can also
  *wait until it learns* (poll), which is slower and needs a bound.
- **Detect:** a monitor on the server's own traffic sees the cast and the later apply, but **not** the reader's direct read, so it
  cannot see the violation. At test time the property is a pair of schedules in which the caller's view is identical (it saw `ok`)
  and the reader's result differs; a controlled scheduler can search for that pair.
- **Trade-off the fix takes on:** a synchronous call adds a wait-for edge from caller to server (a deadlock if the server ever calls
  the caller).
- **Why it hides:** slowing the *reader* lets the apply land first, so W1 occurs only on fast schedules.

## Needs (mechanisation)
Request and reply; a table the reader reads (data); an acknowledgement event whose precondition is "applied". Nothing new in the calculus.

## Sources
All accepted in `full-1b`, `full-2` and `full-3`, under Asynchronous Effect Visibility. Diffs read.
- `emqx/emqx#17821`, fix `2488d0f0dc4365d63516c8d8bb1b9112b2c6a758`: `emqx_hooks:del/2` cast to call.
- `esl/MongooseIM#968`, fix `a38e217b01308f2d97971019c587caa274c8a603`: cowboy dispatch reload, cast to call.
- `elixir-lang/elixir@3ae579de30c7e621e234f716dbb07388af0a4ece`: lexical tracker stop, cast to call.
- Same shape, reviewer text only: `erlang/otp@a18f564053d6ff60403093495010fd702ea82a55` (stopping a Diameter service returns before its registry entry is removed).
