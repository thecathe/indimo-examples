# Timeout Bounds the Wrong Interval — Erlang

Runnable distillation of failure family 35. See [../README.md](../README.md) for what the family
is and what running this establishes; this file is about the code.

## Run

```shell
make run              # every table, about 45s
make run ledger       # the five scenarios, with both intervals
make run cross        # direction x remedy
make run otp          # gen_server's own timeout, on this runtime
make run boundary     # the look-alikes
make run sweep        # the observation window, swept
make run defs         # what each scenario is
make run suspended_abs   # one scenario in full
make shell            # erl -pa . , for poking at scenarios by hand
make clean
```

The two to run first are `make run cross` and `make run otp`. The first shows that the remedy
for one direction of this family is the cause of the other; the second shows that happening for
real, in stdlib, on the runtime you are on.

## Poking at it

```erlang
1> S = tbwi:scenario(rearmed).      % leaves the waiter and its peer running
2> observe:gaps(observe:pulses(maps:get(watch, S), 1200)).
[204,204,204,204,204]
3> tbwi:cleanup(S).
```

Those 204s are the measured interval, recovered from outside with no cooperation from the
process. Nothing anywhere will tell you what they were supposed to be measuring — which is
finding 4, and is most of the point.

Things worth trying:

- `observe:pulses(Pid, 200)` on the same scenario — a window equal to the whole re-arm interval
  reads as an empty list, and an empty list is family 8. `boundary:sweep/0` does this properly.
- Raise `?DRIBBLE_MS` in `tbwi.erl` above `?BOUND_MS`. The peer now misses each deadline, the
  bound fires, and the bug disappears — the defect was never in the timer, it was in the
  relationship between the timer and a rate the code does not control.
- `tbwi:run(suspended)` against `tbwi:run(suspended_abs)`. Same suspension, same responsive
  peer, opposite outcomes.
- Raise `?POLL_MS` in `otp_timeout.erl` above `?BOUND_MS` and the gen_server flaw stops
  reproducing. It needs polling *faster* than the bound — which is exactly what an ordinary
  monitoring agent does to a server whose timeout is shorter than its scrape interval.

## The modules

| Module | Role |
|---|---|
| `observe.erl` | The symptom oracle. Family 8's copy plus `pulses/2,3`. Knows nothing about families. |
| `tbwi.erl` | The subject: five scenarios, each declaring both its intervals; the ledger and the cross. |
| `otp_timeout.erl` | Id 114 run for real against the host runtime, rather than distilled. |
| `boundary.erl` | The look-alikes — families 8 and 31, and a healthy process — and the window sweep. |
| `run.erl` | Argument parsing for `make run`, after `findall/erlang/run.erl`. |

### What `observe.erl` gained, and why it is a copy

The layout note in [`../../README.md`](../../README.md) argues that `observe.erl` should be
copied into each family directory rather than shared, on the grounds that a copy is free to gain
an observation its family needs. This is that case.

Family 8's question is whether a process advanced *at all*, so `watch/2` collapses a whole window
into one bit, `ever_ran`. That is not enough here. A process whose timer is re-armed by every
chunk wakes, works briefly and blocks again, over and over, and the **spacing** of those wakeups
is the interval its timer is actually measuring. `pulses/2,3` keeps the timestamps instead of
collapsing them; `gaps/1` turns them into intervals.

Everything else is verbatim, including the `process_info/2` correction — see below.

### Two things carried over unchanged from family 8

**Reductions, not `status`.** A snapshot of a busy process often reads `running`, and one caught
between reschedules reads `runnable`. Progress is only observable as a difference.

**The observer is charged to the observed.** `process_info/2` costs the *target* exactly one
reduction per call, whatever it asks for — measured on OTP 28.5 as 1, 10, 100 and 1000 polls
moving a blocked process by exactly 1, 10, 100 and 1000, against zero drift when left alone. So
a naive delta reports the observer's own footprint as the target's progress and every blocked
process reads as busy. `net/2` subtracts a floor of `K-1` for `K` readings.

`pulses/3` inherits the same problem in a different shape: between two consecutive polls the
observer's own contribution is exactly one reduction, so a wakeup counts only if the target
moved by **more than one**. A wakeup that costs a single reduction is invisible, and the
resolution of a gap is one poll interval. Both limits are noted at the function.

## Timings

| Constant | Where | Meaning |
|---|---|---|
| `?BOUND_MS` 300 | `tbwi.erl` | the timeout under test. hackney's was 30s; the magnitude is arbitrary, its relationship to `?DRIBBLE_MS` is not. |
| `?DRIBBLE_MS` 200 | `tbwi.erl` | one chunk just inside every deadline. Under `?BOUND_MS`, so the timer is always re-armed before it can fire. |
| `?WINDOW_MS` 1200 | `tbwi.erl`, `boundary.erl` | how long to watch before conceding a timeout never fired. Four times `?BOUND_MS`. |
| `?SUSPEND_MS` 900 | `tbwi.erl` | id 44's suspension. Longer than `?BOUND_MS`, so a wall-clock timer expires entirely while the process is not running. |
| `?SETTLE_MS` 200 | both | startup costs reductions; measuring from t=0 would count it as progress. |
| `?POLL_MS` 120 | `otp_timeout.erl` | how often a system message arrives. Under `?BOUND_MS` there, which is the whole condition for finding 2. |

## Stability and what depends on the runtime

Five consecutive runs of `ledger`, `cross`, `otp` and `boundary` gave identical verdicts and
identical observable classes, with only raw millisecond counts varying. `sweep` is deliberately
not stable at the threshold row and reports a fraction of five attempts for that reason.

Findings 2 and 3 are properties of the host runtime, not of the code here, so both tables
measure rather than assert. `otp_timeout:table/0` prints the OTP release and stdlib version it
ran against and derives its conclusion from the readings — if a future OTP closes the documented
flaw, the conclusion line changes to say so rather than the example quietly meaning something
else. Developed against **OTP 28 / ERTS 16.4.0.3 / stdlib 7.3**, recorded in
[`../provenance.yaml`](../provenance.yaml).
