# Awaited Message Never Arrives — Erlang

Runnable distillation of failure family 8. See [../README.md](../README.md) for what the family
is and what running this establishes; this file is about the code.

## Run

```shell
make run              # both tables
make run matrix       # the cause x remedy matrix
make run boundary     # the look-alike comparison
make run defs         # what each cause and remedy means
make run b r1         # one cell, with the waiter's symptom vector
make shell            # erl -pa . , for poking at scenarios by hand
make clean
```

The interesting single cell is `make run b r1` — a peer that is alive and simply never sends,
against the monitor-based fix. It stays stuck, and the `waits-for=[<0.84.0>]` in the output is
the monitor doing its job on a peer that is never going to die.

## Poking at it

```erlang
1> S = amna:run(b, r1).            % leaves the waiter and peer running
2> observe:format(observe:vector(maps:get(waiter, S))).
"waiting  q=0   dr=0       amna:wait_r1/2  waits-for=[<0.91.0>]"
3> observe:watch(maps:get(waiter, S), 2000).
#{alive => true, ever_ran => false, total_reductions => 0, ...}
4> amna:cleanup(S).
```

Things worth trying:

- `amna:verdict(Pid, 100)` — a short window. `stuck` is always relative to the window, and a
  short enough one calls a healthy slow process stuck.
- Shorten `?WINDOW_MS` in `boundary.erl` below `?REARM_MS` and re-run `boundary:table/0`. The
  family 35 row flips to "looks exactly like family 8".
- `boundary:mutual/0` vs `boundary:mutual_monitored/0` — the same deadlock, with and without
  the wait-for edge being recorded anywhere an observer can see it.
- Raise `?BOUND_MS` in `amna.erl` above `?WINDOW_MS`. Every `r2` cell now reads `stuck`,
  because a bound longer than you are willing to wait is indistinguishable from no bound.

## The modules

| Module | Role |
|---|---|
| `observe.erl` | The symptom oracle. Reports what a process is doing; knows nothing about families. |
| `amna.erl` | The subject: the distilled shape, three causes, two remedies, the matrix. |
| `boundary.erl` | The look-alikes — families 11, 13, 35 and 7 — next to a family 8 reference. |
| `run.erl` | Argument parsing for `make run`, after `findall/erlang/run.erl`. |

### Why `observe.erl` does not classify

It reports a fixed vector — status, mailbox length, reductions delta, current function,
monitors — and stops there. Deciding that a given vector *means* family 8 lives in
`amna:verdict/1`.

That split is deliberate: the vector is a property of BEAM processes and does not grow, while
a classifier would gain a clause per family and become a file that every family directory
depended on. Adding a family should touch that family's directory and nothing else. If a
future family needs an observation this vector lacks — ETS ownership, port counts — it adds it
to its own copy, and copies are free to diverge.

### Two things in `observe.erl` that are less obvious than they look

**Reductions, not `status`.** A snapshot of a busy process often reads `running`, and one
caught between reschedules reads `runnable`. Progress is only observable as a difference, so
every reading takes two samples.

**The observer is charged to the observed.** `process_info/2` costs the *target* exactly one
reduction per call, whatever it asks for. Measured on OTP 28.5:

```
     1 list-form polls -> delta 1
    10 list-form polls -> delta 10
   100 list-form polls -> delta 100
  1000 list-form polls -> delta 1000
  500ms with NO polling  -> delta 0
```

So a naive delta reports the observer's own footprint as the target's progress, and every
blocked process reads as busy. `net/2` subtracts a floor of `K-1` for `K` readings;
`raw_reductions` keeps the uncorrected figure so the correction is visible rather than hidden.

## Timings

| Constant | Where | Meaning |
|---|---|---|
| `?BOUND_MS` 500 | `amna.erl` | remedy r2's `after`. CouchDB used ten minutes; the interval is arbitrary, the existence of one is not. |
| `?WINDOW_MS` 1200 | `amna.erl`, `boundary.erl` | how long zero progress must persist before `stuck` |
| `?SETTLE_MS` 200 | both | startup costs reductions; measuring from t=0 would count it as progress |
| `?REARM_MS` 300 | `boundary.erl` | family 35's bound, deliberately well under `?WINDOW_MS` |

Verdicts are stable — five consecutive runs of both tables gave identical classifications,
with only raw reduction counts varying.
