# Timeout Bounds the Wrong Interval

> Failure family **35**, a root with no sub-families.
> **Invariant:** *correspondence between a timer and the interval it bounds.*

Every timeout has two intervals. There is the one the code **means** to bound — "the whole
response", "two seconds of waiting for a reply" — and there is the one the timer **actually
measures**. Call them **I** and **M**. This family is `M ≠ I`.

A timeout fires when it should not, or never fires when it should, and in both cases the
timeout is *present and looks correct*. That is what separates this family from a missing
bound: there is an `after` in the source, it has a sensible-looking number in it, and it is
measuring something other than what was wanted.

This directory distils that family from the [beam-bug-crawler](https://github.com/thecathe/beam-bug-crawler)
survey corpus into something you can run. See [`provenance.yaml`](./provenance.yaml) for the
exact examples, commits and grades, and [`erlang/`](./erlang/README.md) to run it.

## Why this family needed a different shape from family 8

[Family 8](../awaited-message-never-arrives/README.md) was one symptom reachable from several
unrelated causes, so its matrix held the symptom fixed and varied the cause. That does not
transfer. Family 35's invariant is single, but its symptom runs in two opposite directions, and
**the discrepancy between I and M is signed**:

| relation | what happens to the timer | symptom | from |
|---|---|---|---|
| `M ⊂ I` | restarted by an event *inside* I, so it only ever measures a piece | never fires — runs forever despite having a timeout | **26** hackney |
| `M ⊃ I` | charged for time *outside* I — time the process could not have received in anyway | fires early — gives up without having waited | **44** erts |
| `M = ∅` | discarded outright by an unrelated event | no bound at all | **114** gen_server |

So the axis is **direction × remedy**, not cause × remedy. Two remedies appear in the corpus:

- **`abs`** — one deadline computed at entry, remaining time derived at each `receive`.
  hackney's `remaining/1`; OTP's `{timeout, T, Msg, [{abs, true}]}`.
- **`paused`** — the timer does not run while the process could not have received.
  OTP's `erts_pause_proc_timer`.

## Finding 1 — the remedies are opposed, and neither dominates

`make run cross`, measured on OTP 28 / stdlib 7.3:

|  | no remedy | `abs` | `paused` |
|---|---|---|---|
| `M ⊂ I` (26, hackney) | runs forever | **bounded, fired at 301ms** | no effect — the re-arm is the problem |
| `M ⊃ I` (44, suspension) | survived, got the reply | **GAVE UP, peer was fine** | erts-only, and already in place |

Read the two `abs` cells together. The remedy that repairs hackney is the one that breaks the
suspended wait, against a peer that answered on time. It is not a no-op in the wrong place — it
is the other direction's bug.

Family 8's result was that its two escape hatches are asymmetric and one of them dominates:
bounding a wait discharges the obligation unconditionally, monitoring only sometimes. **Family
35 has no dominating remedy at all**, which is a stronger statement about an invariant. There is
no move that is safe not knowing which direction you are in, and the direction is a fact about
intent.

## Finding 2 — OTP's fix for 114 is 26's bug, and OTP says so

`make run otp` runs the real thing rather than a distillation, because the fix is live in
whatever runtime you are on and it did something worth seeing.

Before erlang/otp#9615, gen_server's plain timeout — the bare integer in
`{noreply, State, 500}` — lived in the `after` of the main receive. A system message came out of
that receive like any other and went off to `sys:handle_system_msg`; what it came back to knew
nothing about a pending timeout, and the bound was simply gone. One `sys:get_status/1` was
enough. That is the `M = ∅` row.

#9615 fixed it by carrying the loop action across the system message. Read what it survives as:

```erlang
system_continue(Parent, Debug, [ServerData, State, HibT, Timer]) ->
    loop(update_callback_cache(ServerData), State, HibT, Debug, Timer).

loop(ServerData, State, Time, Debug, Timer) when ?is_rel_timeout(Time) ->
    receive Msg -> ... after Time -> ... end.
```

`Time`, not what is left of it — there is no remaining-time arithmetic anywhere in
`gen_server`. The timeout is not *resumed*, it is **re-armed at its full value** by every system
message. Measured on stdlib 7.3, bound 300ms:

```
plain timeout, left alone                      fired after 301ms
plain timeout, sys:get_status every 120ms      never fired (1500ms)
  ... measured again once polling stops        fired 252ms later  (= the bound)
{timeout, T, tick} action, same polling        fired after 301ms
```

Ten seconds of polling behaves the same as one and a half. **Poll a gen_server faster than its
own timeout and the timeout never fires** — which is hackney's bug, in the standard library,
introduced by the fix for the other direction of the same family.

OTP knows. From the `action()` documentation in stdlib:

> A system message restarts the time-out, which is a **known and unfortunate flaw in its
> implementation**. […] it is recommended to not use them in combination with this legacy
> time-out type.

and the remedy it offers is `{timeout, Time, Message}`, which is *"not affected by system
messages"* and takes `{abs, true}`. That is hackney's fix, arrived at independently, in the
standard library.

**The corpus records 114 as a fix. It is better described as a move between two rows of one
family**, and the residue is documented rather than closed.

## Finding 3 — the ERTS fix for 44 cannot protect the userland remedy for 26

erlang/otp#8670 made `erlang:suspend_process/2` pause the suspended process's timer, so a
`receive ... after T` no longer expires while its process is not running. The fix works: on
OTP 28, `make run suspended` survives a suspension longer than its own bound.

`erts_pause_proc_timer` pauses timers **the runtime owns**. An absolute deadline computed in
Erlang is not a timer — it is arithmetic on a wall clock, and the runtime cannot pause
arithmetic. So:

```
suspended       plain `after 300`                       got the reply at 1002ms
suspended_abs   the same wait, hackney's remedy         GAVE UP at 901ms, peer was responsive
```

Same suspension, same responsive peer, opposite outcomes. The process comes back from a
suspension it had no say in, re-enters its receive, computes `remaining(Deadline) = 0` and gives
up.

**Every codebase that took hackney's remedy has re-opened 44 for itself, on a runtime where 44
is fixed.** No further work in ERTS can reach it, because the thing needing to be paused is no
longer a timer.

## Finding 4 — I exists only in prose, so the family is not observable

In all three confirmed members, the intended interval is recorded in a comment, a test name or
an exit reason — never in code:

| id | where I is written down |
|---|---|
| 26 | `%% Timeout is per-chunk - resets each time data is received. This allows large responses to complete as long as data keeps flowing.` — deleted by the fix |
| 114 | `%% a system message should not cancel a plain timeout` — in the added test |
| 44 | `exit(timer_not_paused)` — the exit reason the added test asserts |

Read hackney's comment again. The second sentence is not a mistake; it is the intended interval,
written down, and it is genuinely wanted behaviour for a large download. The bug is that a peer
gets to decide whether "data keeps flowing" means a megabyte or one byte. What the fix had to
give up is exactly the property that comment describes — which is why it also had to add a size
cap, a *size* bound standing in for a *time* bound that could not be stated correctly.

M, by contrast, is recoverable from outside with no cooperation at all: watch when a process
runs and read the gaps. `observe:pulses/3` does this, and reports hackney's 200ms dribble as
`[204, 204, 204, ...]`. So an observer gets one operand of the comparison and never the other,
and `make run boundary` shows what that costs:

| observable class | family 35 scenario | and, indistinguishably |
|---|---|---|
| `silent` | timer discarded (114) | awaited message never arrives (family 8) |
| `bursts` | timer re-armed per chunk (26) | a healthy process that is merely slow |
| `exited` | gave up early, `M ≠ I` (44) | a bound that is correct and simply too small (family 31) |

Four families, six scenarios, three classes. Every class holds a family 35 scenario and
something that is not one — and in the `bursts` row, one of the two is not a bug at all.

**Family 35 is the first family in this survey whose invariant is not checkable by observation.**
Family 8's is: look at the receive and see whether there is a monitor or an `after`, or watch
the process and see whether it advances. Family 35's compares a measurable quantity against an
unwritten one. Any oracle for it has to state both its window and its assumed I, and the second
of those is a claim about intent that no amount of instrumentation supplies.

## Finding 5 — sub-families are not justified, and the taxonomy already explains why

Family 35's description enumerates three shapes, and the three certain members map onto them
1:1, which invites splitting them into children. They should not be split, because they are not
a partition of *instances*. They are a partition of *states one instance passes through*:

- **115** turned correct into `M = ∅`
- **114** turned `M = ∅` into `M ⊂ I`
- **hackney's fix** turned `M ⊂ I` into an endpoint that now includes the process's own work

A split by mechanism would put a single commit's before and after into two different
sub-families, three times over in a five-candidate family.

The one defensible cut is by **direction** — `M ⊂ I` and `M ⊃ I` are observationally opposite
and have opposed remedies. But the taxonomy has already met that situation and decided it.
Fault Amplification's own description says of two of its children that they *"are opposite ends
of one axis, which is why neither can be the parent of the other"*, and resolves it with
siblings under a shared parent. **Family 35 already is that shared parent.** Splitting it would
also have to survive finding 1, where each child's remedy is the other child's cause — which is
a very poor property for two families that are supposed to be diagnosed separately.

*Suggested amendment to `families.yaml`: leave 35 a childless root, and add the direction to its
`parameters`, where it is currently unnamed:*

```yaml
    parameters:
      - intended interval
      - measured interval
      - what resets or cancels the timer
      - direction               # measured is a sub-interval, or a super-interval
```

Nothing has been changed in the corpus — this is a finding to weigh, not an edit.

## Finding 6 — the observation window has to be twice an interval you cannot see

Family 8's finding 4 noted that family 35 separates from it only because the observation window
outlasts the re-arm interval, and left it there. `make run sweep` measures it, and the honest
number is worse than the concession:

```
window       saw an interval  typical gap    reads as
50ms         0 of 5           -              family 8 -- one wakeup at most, no interval
100ms        0 of 5           -              family 8
150ms        0 of 5           -              family 8
200ms        0 of 5           -              family 8
300ms        3 of 5           190ms          either, depending on the run
400ms        5 of 5           204ms          35 -- an interval is visible
800ms        5 of 5           202ms          35
```

The threshold is not the re-arm interval, it is **twice** it. One wakeup is not an interval, so
the window has to span two, and a 200ms window on a 200ms cycle only does that if it starts
between chunks — which the observer does not choose either.

That number was itself wrong the first time. The initial sweep settled for exactly one dribble
interval before opening the window, phase-locking every run to the same point in the cycle, and
produced a beautifully sharp threshold at 200ms: 0 of 3 below, 3 of 3 at and above, five times
running. The sharpness was an artifact of the harness. `boundary.erl` now randomises the offset,
and says so in a comment, because the artifact is easier to reproduce than to notice.

## Relation to family 8

Family 8's boundary table lists family 35 as a look-alike that *separates* — "yes, it runs" —
with the caveat above. Both halves survive contact with this directory, but the caveat turns out
to be the bigger half: 35 separates from 8 only in the `M ⊂ I` direction, only under a window of
at least twice an interval nothing reveals, and in the `M = ∅` direction it does not separate
from family 8 at all, ever. A discarded timer leaves precisely a bare unbounded receive.

The two families also meet at a sharper point. CouchDB fixed family 8 by **adding** an `after`,
and hackney's family 35 bug **is** an `after`. The construct is identical; which side of the
line it falls on depends on whether the timer bounds the interval the code means to bound, and
nothing in the construct records that.
