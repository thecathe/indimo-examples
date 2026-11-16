# 11 — Where the layer adds nothing

> *AI-generated: Claude Sonnet 5.5, effort xhigh; first generated 2026-11-16, last edited 2026-11-16. Source readings are summaries of survey fixes; see "Sources" for what was read.*

**Verdict:** *cannot help.* The contrast cards. Each is a bug in a topic area where no agent is missing information.
**Topics:** (contrast to all).

## One runnable: a timer that means something else
A start delay was a `gen_server` timeout. In `gen_server`, **any** message that arrives first cancels a pending timeout, so the delayed initialisation never ran.
No agent was missing information; a construct does not mean what the code assumed. The fix is an explicit timer message.
[`timer_that_is_cancelled.erl`](timer_that_is_cancelled.erl); `make demo M=timer_that_is_cancelled`. Source: `apache/couchdb#5185`, fix `8f966643b3d09a39bf6e320d9fc9bcaa5d62f928`
(Timeout Bounds the Wrong Interval, accepted in all three passes). Reviewer text only.

## Three described
- **A deadlock cycle.** `emqx/emqx#4909` (`709fff0de1d003232530f5f802ad9add3dbc9c77`): plugin loading on the synchronous start path deadlocks; it is moved off it. The bug is a
  cycle in who waits for whom, a structural property that detection already gives; knowledge of what others know adds nothing. (Mutual Blocking; reviewer text only.)
- **Overload.** `emqx/emqx#15396` (`b5b695e232268e291916ada9e2262274d03ca468`): a synchronous call on the subscriber-down path times out when many subscribers disconnect at once;
  the fix avoids a needless call. The problem is a resource under load. (Fault Amplification; reviewer text only; flagged in one pass.)
- **Ownership and lifetime.** `josefs/Gradualizer#343` (`d05f79a9bea82e791279e7229cbbd0cc3ff38cec`): loaded prelude state is tied to an explicit call, not to the process that
  owns it, so a restart discards it. A design of who owns what for how long, not a question of what anyone could tell. (Resource Lifetime Tied to the Wrong Process; reviewer text only.)

## The pattern
These are *mechanism* bugs (what a construct means), *resource* bugs (load, lifetime) and *structure* bugs (a wait-for cycle). The layer is about **what an agent can tell**; where
nothing is being told or hidden it has nothing to do.

## The contrast sample these come from
A seeded sample (seed 20261116): five accepted-in-all-three-passes units per topic, with no wording filter, 25 in all, read from the reviewers' first reason and the title only.
Provisional tally by one reader: about 14 are an information, acknowledgement or ordering fix of one of the shapes in cards 01 to 10; about 4 or 5 are a policy choice where the layer states the
trade-off and decides nothing; 4 are the cases above (the layer adds nothing); 2 were already in the shortlist. The topic searches in the sweep were wording-ranked and so overstate how often
the layer helps; this sample is the check.
