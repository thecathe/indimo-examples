# 08 — The restart budget as a belief on correlated evidence

> *AI-generated: Claude Sonnet 5.5, effort unrecorded; first generated 2026-11-16, last edited 2026-11-16. Source readings are summaries of survey fixes; see "Sources" for what was read.*

**Verdict:** a *policy choice* (nothing in a crash signal separates the worlds) with a *detect* story from a knowledge map. Also a small grey-failure
point: an exit reason is a message, and `normal` can be false. **Topics:** failure escalation (supervisor sense); grey failures.

## Scenario
Several children depend on one thing (a network, a database). When it fails they all crash together. The supervisor counts each crash as separate
evidence that "this child has a fault that restarting will not clear". After a few it gives up, terminates, and takes a **healthy sibling** with it.
Five fixes in the survey: raise the budget (logplex: 15,000 in 30 s; oban: 20 in 60 s), scale it with the number of children (ranch: `1 + ceil(log2 N)`),
`rescue` so the child never crashes and the supervisor never counts (blockscout), or make the children `temporary` so the supervisor stops restarting them (supabase).

## Interaction
```
 shared dependency  X   fails
   writer 1 crash -> restart -> crash      \
   writer 2 crash -> restart -> crash       }  budget (3 in 5 s) spent on ONE cause
   writer 3 crash -> restart -> crash      /
 supervisor terminates  ->  healthy sibling killed
```

## Erlang
[`restart_budget.erl`](restart_budget.erl): a real `supervisor`; intensity 3 loses the supervisor and the sibling, intensity 100000 keeps both.
`flaky_demo` shows the `exit(normal)` point. `make demo M=restart_budget` (about two seconds).

## The layer in four lines
- **View.** The supervisor sees exit signals and their reasons.
- **Worlds.** W1: one child has a persistent local fault. W2: many children hit one shared transient cause.
- **What the code does.** A fixed count over a time window: the same threshold for W1 and W2.
- **What is missing.** The count treats correlated crashes as independent evidence. The exit reason does not say which world holds.

## What helps
- **Nothing separates the worlds at the first crashes:** the choice of budget is a policy with a cost (the leader's grace period has the same shape).
  The five fixes differ in what they keep: raising the threshold keeps the siblings but moves the cliff; `rescue` and `temporary` keep the siblings by
  **removing the supervisor's information**.
- **Detect, the knowledge map:** a monitor that holds the dependency structure (which children share what) sees k of N children crash within the window, infers
  a shared cause rather than k separate faults, and can *predict* the supervisor's termination from the budget arithmetic before it happens. Its **belief**
  ("shared transient cause" more plausible than "N independent persistent faults") is the ranked-worlds part of the model.
- **A false report:** a `transient` child that exits `normal` after a failure tells its supervisor "I finished", so it is not restarted
  (`flaky_demo(normal)` leaves 0 children; an abnormal exit leaves 1). The same shape as a reply that asserts more than the speaker knows.

## Needs
Supervisors with restart intensity, links and monitors, exit reasons; a shared-dependency relation among children; correlated evidence in the ranking.

## Sources
Accepted in all three passes under Restart Intensity Escalation. Diffs read. The reviewers tag most as "avoids, does not fix".
- `heroku/logplex#253`, fix `75063512d4be4cbf31c2d875017a0080bbedf107` (also `exit(normal)` to an abnormal exit).
- `oban-bg/oban@a20f0ef81d4a8bc2626435e06e8c04e2ee2e03c1`.
- `ninenines/ranch#244`, fix `0a3c0aa067f476229c6fa56494dbb5a191555aa2` (flagged in all three passes; the PR text and the code disagree on the formula).
- `blockscout/blockscout#10993`, fix `8a826f11285cf495c39094a621d4726711189cad`.
- `supabase/realtime@a8a163ee4e0573d9e0f2832715ed22334bf5fff8`.
