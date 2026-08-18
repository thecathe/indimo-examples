# Awaited Message Never Arrives

> Failure family **8**, under `Progress Failure > Blocking`.
> **Invariant:** *every wait on a peer either observes that peer's death or bounds itself.*

A process waits for a message that will never come. The sender died before sending it, or is
alive and simply never sends, or only ever sends messages of a shape the receive does not
match. The process stays alive, consumes no CPU, and never returns — and anything that calls
into it inherits the stall, so one blocked process can present as a wholly unresponsive
subsystem.

This directory distils that family from the [beam-bug-crawler](https://github.com/thecathe/beam-bug-crawler)
survey corpus into something you can run. See [`provenance.yaml`](./provenance.yaml) for the
exact examples, commits and grades, and [`erlang/`](./erlang/README.md) to run it.

## The two confirmed examples

The family rests on a pair of fixes that are *structurally identical* and were fixed
*differently*. Both are a selective receive on messages from exactly one peer, with no monitor
and no bound:

```erlang
%% erlang/otp  lib/ssl/src/inet_tls_dist.erl  do_accept/7        (GH-5332)
receive
    {AcceptPid, controller} -> ...;
    {AcceptPid, exit}       -> ?shutdown2(MyNode, connection_setup_failed)
end.

%% apache/couchdb  src/fabric_doc_attachments.erl  write_chunks/2
receive
    {MiddleMan, ChunkRecord} -> ChunkFun(ChunkRecord, ok), write_chunks(MiddleMan, ChunkFun)
end.
```

OTP added a monitor and a `{'DOWN', ...}` clause. CouchDB added `after 600000 -> exit(timeout)`.
The invariant offers those two escape hatches joined by *or*, which invites reading them as
alternatives.

## Finding 1 — the remedies are not alternatives

`make run matrix` crosses three causes with the two remedies:

|          | `none` — the bug | `r1` — monitor + `DOWN` | `r2` — `after` |
|----------|------------------|--------------------------|----------------|
| **a** peer dies before sending | stuck | **escaped** `peer_down` | **escaped** `timeout` |
| **b** peer alive, never sends  | stuck | stuck | **escaped** `timeout` |
| **c** peer sends unmatched shape | stuck `q=1` | stuck `q=1` | **escaped** `timeout` |

**A monitor rescues only the case where the peer dies.** A bound rescues all three. So OTP's
fix is strictly weaker than CouchDB's — correct for GH-5332, where the peer really did crash,
but it would not have saved CouchDB's chunk writer from a middle man that merely went quiet.

The invariant's *or* is therefore not symmetric. Stated precisely: bounding the wait discharges
the obligation unconditionally, while observing the peer's death discharges it only under the
assumption that failure to send implies death. That assumption is what fails in causes b and c.

## Finding 2 — the mailbox does not discriminate against starvation

The family's current text distinguishes itself from Selective Receive Starvation on the
grounds that *"nothing is burying the wanted message — the mailbox is typically empty"*.

That test does not hold up. Under cause **c** the mailbox holds the unmatched message
(`q=1`), and the starvation look-alike in `boundary.erl` also sits at `q=1`. Mailbox length
separates neither.

What does separate them is whether the process **runs at all**: a starved process is working
hard on the wrong messages, while a family 8 process makes literally zero progress.
*Suggested amendment to `families.yaml`: replace the mailbox-emptiness clause with a
no-progress clause.* Nothing has been changed in the corpus — this is a finding to weigh, not
an edit.

## Finding 3 — family 7 is not observably different, and that is not a defect of the tooling

`make run boundary` runs four look-alikes next to a family 8 reference. Every one of them is a
process that is alive and will never finish, which is what a user reports.

| Scenario | Separates from family 8? |
|---|---|
| 11 selective receive starvation | yes — it runs |
| 13 loop progress failure | yes — it runs |
| 35 timeout bounds the wrong interval | yes — it runs, in bursts |
| **7 mutual blocking (bare `receive`)** | **no — identical in every observable respect** |
| 7 mutual blocking (each side monitored) | yes — the wait-for edge is visible |

Two processes deadlocked on each other look exactly like two independent instances of family
8: alive, in a receive, empty mailbox, zero reductions. The difference is a property of the
*relation between* the processes, and a bare `receive` records no relation — the runtime cannot
tell you what a process is waiting for, because it was never told.

It becomes visible the moment each side monitors the other, which is what `gen_server:call`
does on your behalf: the edge appears in `process_info(Pid, monitors)`, and an observer can
walk it and find the cycle.

**So the wait-for graph is recoverable exactly when the waiter arranged to observe its peer —
the first clause of this family's own invariant.** Code that satisfies the invariant is also
code you can diagnose from outside. The two are the same act.

## Finding 4 — two of the separations are weaker than the table suggests

- **Family 35** separates only because the observation window outlasts the re-arm interval.
  Nothing reveals that interval to an observer, so under a short enough window a family 35 bug
  reads as family 8. Shorten `?WINDOW_MS` in `boundary.erl` and the row flips.
  [Family 35's own directory](../timeout-bounds-the-wrong-interval/README.md) sweeps this rather
  than asserting it, and the measured threshold is worse than stated here: the window must be
  **twice** the re-arm interval, because one wakeup is not an interval. It also finds a direction
  of family 35 — a timer discarded rather than re-armed — that never separates from family 8 at
  all, since a discarded timer leaves precisely a bare unbounded receive.
- **`stuck` is always relative to a window.** CouchDB's real bound was ten minutes; a
  ten-minute window would have called the *fixed* version stuck too. There is no window-free
  version of the question.

## Finding 5 — the oracle perturbs what it measures

`process_info/2` charges the *observed* process exactly one reduction per call, whatever it
asks for — measured on OTP 28.5 as 1, 10, 100 and 1000 polls moving a blocked process by
exactly 1, 10, 100 and 1000, against zero drift when left alone.

A naive reductions delta therefore reports the observer's own footprint as the target's
progress, and **every blocked process reads as busy** — which is exactly what the first
version of this example did. `observe.erl` subtracts a floor of `K-1` for `K` readings and
reports both figures, so the correction stays visible.

## Relation to `findall`

[`findall/erlang/sup.erl`](../../findall/erlang/sup.erl) already solved a piece of this: a Go
program can detect its own deadlock, an Erlang one cannot, so `sup.erl` demanded a heartbeat
and declared the main process stuck when one failed to arrive.

A heartbeat tells you *that* progress stopped. It cannot tell you *which* failure stopped it,
because a starved process, a deadlocked process and a spinning process all fail to send one
alike. [`observe.erl`](./erlang/observe.erl) generalises it — and Finding 3 marks the limit of
how far that generalisation can go.
