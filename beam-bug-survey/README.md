# beam-bug-survey: distilled examples for the epistemic layer

> *AI-generated: Claude Sonnet 5.5, effort unrecorded; first generated 2026-11-16, last edited 2026-11-16. Drafts for the author to collate by hand; every reading of a fix is a summary and may be wrong.*

Small, compile-checked Erlang snippets, interaction diagrams and scenario descriptions, each distilled from a real fix in the
[beam-bug-crawler](https://github.com/thecathe/beam-bug-crawler) survey, to motivate (or mark the limits of) an **epistemic reading** of concurrency bugs: what an agent can tell
apart at a decision point, what it knows or believes, what would separate the situations it cannot tell apart, and where the right answer is a policy. Each card says whether the
layer **helps avoid**, **helps detect**, or **cannot help**.

## How they were found
A sweep of the three de-duplicated survey passes (`full-1b`, `full-2`, `full-3`; Haiku 5.5), taking only units **accepted in all three**: 1,504 of 3,283. Filters (heuristic, not measurements): not test-only,
not a manifest or dependency bump, 3 to 120 changed lines, not tagged as a feature or upstream-fix adoption; then ranked by topic wording in the reviewers' reasons. The reviewers' text of the top 10 to
16 per topic was read and the diffs of the shortlist. A **seeded contrast sample** (5 per topic, no wording filter) was read to find the cases where the layer adds nothing. The earlier survey and the 13 cases already
discussed are used as anchors (below).

## The cards
| Card | Verdict | Topics | Shape |
|---|---|---|---|
| [01 queued-not-applied](01-queued-not-applied/README.md) | helps avoid (separate worlds) | async visibility | a cast returns "queued"; readers need "applied" |
| [02 order-as-barrier](02-order-as-barrier/README.md) | helps avoid (separate worlds, by order) | async visibility, ordering | a later reply proves an earlier message handled, over one FIFO channel |
| [03 alive-a-moment-ago](03-alive-a-moment-ago/README.md) | helps avoid; one variant fits every world | races (process death) | "alive" expires, "dead" lasts: subscribe with a monitor |
| [04 entry-race](04-entry-race/README.md) | explains and rules out; fix is owner-side, not informational | races (check-then-act) | two agents check, both act; distributed knowledge nobody holds |
| [05 act-only-on-what-you-saw](05-act-only-on-what-you-saw/README.md) | helps avoid (fit every world) | races | bound the act to the extent of what was observed |
| [06 nested-retry-layers](06-nested-retry-layers/README.md) | helps avoid; detect statically | escalation (wider) | layers multiply attempts; the inner layer lacks the caller's context |
| [07 retry-licence](07-retry-licence/README.md) | helps avoid (typed errors) or policy | escalation (wider) | retry because it never happened (knowledge) or because it is harmless (assumption) |
| [08 restart-budget-belief](08-restart-budget-belief/README.md) | policy; detect with a dependency map | escalation (supervisor), grey | a budget counts correlated crashes as independent evidence |
| [09 not-yet-is-not-never](09-not-yet-is-not-never/README.md) | helps avoid; first moment is a policy | ordering | "not yet" read as an answer |
| [10 timeout-shorter-than-the-probe](10-timeout-shorter-than-the-probe/README.md) | helps avoid (align the bounds); detect statically | grey failures | two thresholds on one signal |
| [11 where-it-adds-nothing](11-where-it-adds-nothing/README.md) | cannot help | contrast | mechanism, overload, lifetime, wait-for cycle |

## Anchors: earlier cases that fit (not rewritten here)
The cancelled checkout (`devinus/poolboy@15748054cd050ef20ee5dbefc6eb2f5582cbba57`), the channel registered too late (`emqx/emqx@367fc95`), the leader that resigned at once
(`WhatsApp/waraft@c207562e36e525c43b7e12ab084698b626fd14e0`), the silent websocket (`firezone/firezone#1974`), the vnode that said ok (`basho/riak_kv#1106`), the shared keepalive counter
(`emqx/emqx#8866`), the late health check (`emqx/emqx#14001`, `#14319`), global's view of connections (`erlang/otp#6007`). The earlier survey's true grey failures are these; the newer passes have no Grey Failure family.

## Shortlisted, not written up
- *The stale replica:* `emqx/emqx#12227` (`146b6f3a72ea99532d60ed3d57c0c23e834bfef8`; decide "first" from a counter the node owns, not from a lagging replica) and `elixir-horde/horde@8beceaed550ea915efbdbd8d17d048721607e57a` (route a terminate by a
  shared placement rule: a knowledge map known to every node).
- *Cleanup entrusted to the one that may die:* `emqx/emqx#14172` (`3abd5c54fdbb80e28b3792a564338d23573d9aa6`; move the obligation to a long-lived monitor).
- *Stale basis:* `ArweaveTeam/arweave@33686d01e5a32827b8f9806194697ea9297654ae` (a mined solution applied after the head moved; reviewer text only).

## Provisional reading of the topics (for choosing what to take further)
- **Asynchronous visibility** and **races with a stable fact** (cards 01 to 03, 05) are the cleanest: the layer names exactly what the acknowledgement or check fails to give, and the fixes sort into the two kinds.
- **Escalation, wider sense** (06 to 08) is the richest and the best fit for a monitor that holds a structure (budgets, dependencies, retry layers) and infers; the cases mostly end in a policy.
- **Check-then-act** (04) is where the layer explains and rules out without supplying information.
- **Ordering** (09) is real but repeats shapes already seen. **Grey failures** are thin in the newer passes; the best are the earlier survey's.

## Running
`make check` compiles every module with warnings on; `make demo M=<module>` runs a card's `demo/0`; `make demos` runs all. Erlang/OTP 28 was used. The snippets show the **shape**, not the original code, and the races are
made deterministic with sleeps; they are not claimed to reproduce the originals.

## What was and was not read
Where a source line says "diff read", the stored diff was read (in part where noted). "Reviewer text only" means only the pass reviewers' reasons were read. Nothing here was run against the original repositories.
