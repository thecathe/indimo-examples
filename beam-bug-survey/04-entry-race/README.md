# 04 — The entry race: two agents check, then both act

> *AI-generated: Claude Sonnet 5.5, effort xhigh; first generated 2026-11-16, last edited 2026-11-16. Source readings are summaries of survey fixes; see "Sources" for what was read.*

**Verdict:** the layer *explains and rules out*; the fix is not informational (it merges check and act at the owner, or adds a clause for the loser).
Detect: possible when the accesses are visible. **Topics:** races (check-then-act).

## Scenario
Many agents each read a shared cell and write back a value derived from it. Between one agent's read and its write another agent's write
lands, and the first write is overwritten. Nobody crashes; the count is just wrong.

## Interaction
```
 A: lookup k -> 0                  B: lookup k -> 0
 A: insert k = 1                   B: insert k = 1        (A's update is lost)
```
The one whose assumption ("k is still 0") was true when checked and false when acted on is the **loser** (the Check-Then-Act family's own word).

## Erlang
[`entry_race.erl`](entry_race.erl): `buggy_incr/2` (read then insert), `fixed_incr/2` (`ets:update_counter`). `make demo M=entry_race`.

## The layer in four lines
- **View.** A's view at the write is its view at the read plus its own steps; B's act sent it nothing.
- **Worlds.** W1: no one wrote since my read. W2: someone did.
- **What the code does.** Acts as if W1.
- **What is missing.** A knew φ ("k = 0") at t1 and does not know it at t2. φ is unstable, and knowledge of an unstable fact does not outlast the observation.

## Distributed knowledge
A's view is "saw 0, will write 1"; B's is the same. **Pooled**, they entail "both will write 1 and one write is lost". That is distributed
knowledge of the group (Halpern and Moses) that neither member has. It cannot be *used* by the agents: pooling takes messages, which can cross
B's write. Only the **owner of the cell**, which sees both requests in some order, can pool the views at the right instant.

## What helps
- **Rules out:** re-checking just before writing (narrows the window, does not close it); telling the other agent your intent (the notice can cross its write).
- **Avoid (feasible):** merge check and act at the owner (`update_counter`, `insert_new`, one `gen_server` call), or give the loser a clause (`insert_new` returns `false`).
  Separating the worlds by informing the agents is **not** feasible.
- **Detect:** "A is between its read and its write" and "B is between its read and its write" at once is a conjunction of two local conditions,
  the kind of global predicate that can be detected from a trace with logical clocks (Garg and Waldecker; Cooper and Marzullo). Visible only when
  accesses are messages to the owner; a direct ETS access is invisible to a message-level monitor.

## Needs
The read-write window as an event with a precondition; the owner as a node; distributed knowledge (a group operator).

## Sources
Accepted in all three passes, under Check-Then-Act on Shared State.
- `akira/exq#87`, fix `19f8608f23ca437fe519987e24f14f088b397b19`: worker count read then written, to `ets:update_counter`. Diff read; flagged in two of three passes.
- `emqx/emqx#17575`, fix `849402d534f21e2a0bf02f8666ea6c465da40cf1`: a counter and the records it counts, reordered so a crash leaves the counter on the safe side. Diff read in part.
