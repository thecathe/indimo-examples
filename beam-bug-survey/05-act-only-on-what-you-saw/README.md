# 05 — Act only on as much as you saw

> *AI-generated: Claude Sonnet 5.5, effort unrecorded; first generated 2026-11-16, last edited 2026-11-16. Source readings are summaries of survey fixes; see "Sources" for what was read.*

**Verdict:** helps avoid (fit every world: bound the act to the extent of what was observed). Detect: a history monitor can check it.
**Topics:** races (check-then-act); asynchronous visibility.

## Scenario
A server persists the keys marked "dirty" by folding over a table, then clears the table. A key marked **while the fold was running** was not
seen by the fold, but the clear removed it too, so it was never persisted. The fix makes each mark a counter; after persisting a key the server
subtracts exactly the count the fold saw. Anything marked later is still there for the next round.

## Interaction
```
 server                               writer
   | fold: sees {early}                  |
   | persist(early) ...                  | mark(late)        <- not in the fold's view
   | clear table  ------------------------> removes early AND late   (late lost)
```

## Erlang
[`act_only_on_what_you_saw.erl`](act_only_on_what_you_saw.erl): `buggy_flush/2`, `fixed_flush/2`. `make demo M=act_only_on_what_you_saw`.

## The layer in four lines
- **View.** The server's observation is the fold: the set (and count) of marks it read.
- **Worlds.** W1: nothing was marked during the fold. W2: something was.
- **What the code does.** The clear acts on "everything now in the table", which it believes equals "what I saw".
- **What is missing.** Nothing needs to be *learned*: the fix restricts the act to the known part (`K`-bounded action), so it is right in every world.

## What helps
- **Avoid, fit every world:** record exactly what was observed and discard only that. No extra information and no exclusion.
- **Detect:** a monitor that keeps the *history* (marks arriving; persists performed) can check the invariant "every key marked after the
  fold began is persisted in a later round". The agent's own state cannot, because it lost the distinction; the history has it.
- **A close relative** (`emqx/emqx#17575`): choose the order of two steps so that a crash between them errs on the safe side (the counter is
  left slightly high, never low).

## Needs
Counters (data); history against state (observation by history, for the monitor).

## Sources
`vernemq/vernemq#509`, fix `fe493dd6ee237189fc6ef1895f673344d222d827`, accepted in all three passes under Check-Then-Act on Shared State. Diff read.
