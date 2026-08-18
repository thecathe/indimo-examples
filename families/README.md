# Failure Families

Runnable distillations of a taxonomy of **failure classes** in BEAM systems.

The taxonomy and the confirmed real-world examples behind it live in
[beam-bug-crawler](https://github.com/thecathe/beam-bug-crawler), which mines GitHub for
deadlocks, races, mailbox overflow and grey failures in Erlang, Elixir and Gleam projects. That
repo holds the corpus; this directory holds the distillations.

The two are linked by data rather than by a submodule: each family carries a `provenance.yaml`
naming the family id, its invariant, and the confirmed examples it was drawn from, so a rename
or reparent upstream shows up as a mismatch instead of silently invalidating the prose.

## The rule the taxonomy is built on

> A family names a **symptom**, never a cause — *"processes accumulate without bound"*, not
> *"missing `terminate/2` clause"*.

Two things make that operational, and both come from the family definition rather than from any
one example:

- **`invariant_class`** — the property being violated. This is what makes a family checkable
  rather than merely descriptive.
- **`parameters`** — the axes along which instances vary.

Each directory here takes one family and asks whether its invariant actually holds up: whether
the symptom can be produced from several unrelated causes, and whether the family can be told
apart from its neighbours by observation rather than by assertion.

## Families

### [Awaited Message Never Arrives](./awaited-message-never-arrives/README.md) — family 8

*Every wait on a peer either observes that peer's death or bounds itself.*

Distilled from two structurally identical fixes — `erlang/otp`'s `inet_tls_dist:do_accept/7`
(GH-5332) and `apache/couchdb`'s `fabric_doc_attachments:write_chunks/2` — that were fixed
through *different* clauses of the same invariant. Crossing three causes against both remedies
shows the two are not alternatives: a monitor rescues only the case where the peer dies.

- [Erlang](./awaited-message-never-arrives/erlang/README.md) — `make run`

### [Timeout Bounds the Wrong Interval](./timeout-bounds-the-wrong-interval/README.md) — family 35

*Correspondence between a timer and the interval it bounds.*

Every timeout has two intervals: the one the code means to bound, and the one the timer
measures. This family is the difference between them, and the difference is **signed** — one
direction runs forever despite having a timeout, the other gives up without having waited. The
two remedies in the corpus turn out to be opposed rather than complementary, and one of the
family's own members is a fix that moved the bug from one direction to the other.

- [Erlang](./timeout-bounds-the-wrong-interval/erlang/README.md) — `make run`

## What running these has established so far

Findings that came out of building the examples rather than reading the definitions:

1. **The escape hatches in family 8's invariant are not symmetric.** Bounding a wait discharges
   the obligation unconditionally; observing the peer's death discharges it only if failure to
   send implies death.
2. **Family 8's stated discriminator against starvation does not work.** It appeals to an empty
   mailbox, but a shape-mismatched wait leaves a message sitting unmatched, and a starved
   process sits at the same queue length. Whether the process *runs at all* separates them;
   mailbox length does not.
3. **Mutual Blocking is not observably distinct from Awaited Message Never Arrives**, unless
   the waits were monitored. The difference is a property of the relation between processes,
   and a bare `receive` records no relation. It becomes visible under `gen_server:call`,
   which monitors on your behalf — so the wait-for graph is recoverable exactly when the waiter
   satisfied the first clause of the invariant.
4. **Observing a process is charged to the process being observed.** `process_info/2` costs the
   target one reduction per call, so an uncorrected reductions delta reports the observer's own
   footprint as progress and calls every blocked process busy.
5. **Not every invariant is checkable by observation.** Family 8's can be checked by watching a
   process. Family 35's compares what a timer measures against what the code meant it to
   measure, and the second of those is in a comment, a test name or an exit reason — never in
   the code and never in the runtime. An oracle recovers one operand and never the other.
6. **A fix can move a bug between two rows of one family rather than out of it.** OTP's repair
   for a discarded `gen_server` timeout re-arms it instead of resuming it, which is the other
   member of the same family; the residue is documented in stdlib as a known flaw.
7. **Harnesses phase-lock.** A sweep that settled for exactly one cycle before observing gave a
   sharp, stable and wrong threshold, five runs running. Randomising the offset moved it by a
   factor of two. Stability across runs is not evidence of an unbiased measurement.

## Requirements

`nix` and `direnv`, as for the rest of [examples](../README.md) — `cd` into the directory and
the flake provides `erlang`. Otherwise any Erlang/OTP with `erlc` and `make` will do; developed
against OTP 28.5.

## Adding a family

One directory per family, named after the family in kebab-case, self-contained:

```
<family-name>/
  README.md          -- the family, what running it establishes, and any findings
  provenance.yaml    -- family id, invariant, and the confirmed examples behind it
  erlang/
    README.md  makefile  run.erl  observe.erl  <family>.erl  boundary.erl
```

`observe.erl` is **copied**, not shared. It reports a fixed symptom vector and deliberately
does not classify, so it has no reason to grow as families are added — and a copy is free to
gain an observation its family needs without disturbing any other. A shared oracle would have
to serve everyone, which is the coupling this layout exists to avoid.

---

## Proposed classifications — work in progress

Distilling a family means reading every candidate's diff, which produces classification opinions
as a by-product. They are collected here so they are in one place rather than scattered across
`provenance.yaml` files.

**Nothing here has been written to the database.** `example_families` is still empty and these
are proposals for a human pass to accept, reject or ignore. Each family's own
`provenance.yaml` carries the full reasoning; this is the index.

Grades follow the classify prompt's vocabulary: *certain* / *tentative* / *forced*.

### Assignments

| example | key | → family | grade | basis |
|---|---|---|---|---|
| 23 | `erlang/otp#5490` | **8** Awaited Message Never Arrives | certain | `do_accept/7`, one peer, no monitor, no bound; fixed with a monitor |
| 96 | `apache/couchdb@483fb33b` | **8** | certain | `write_chunks/2`, structurally identical to 23, fixed with `after` |
| 14 | `erlang/otp@8c9a5f3b` | **8** | tentative | only 1 of 3 hunks; test-only. Also **31** |
| 26 | `benoitc/hackney@3d25f9fe` | **35** Timeout Bounds the Wrong Interval | certain | per-chunk timer, GHSA-jq4m. Also **19** — the uncapped `AccBody` is the other half of the same commit |
| 114 | `erlang/otp#9615` | **35** | certain | plain timeout discarded by a `system` message |
| 44 | `erlang/otp#8670` | **35** | certain | symptom only; the fix is in C |

### Reparents — checked against the diff while looking for something else

These were pulled up as candidates for family 8, rejected, and a better home suggested. None
were examined for their own sake, so the destination is weaker evidence than the rejection.

| example | key | not family 8 because | → suggested |
|---|---|---|---|
| 6 | `erlang/otp@8b5cc9bf` | no `receive` at all; adds a `_ ->` fall-through to a `case` | **27** Check-Then-Act on Shared State |
| 70 | `benoitc/hackney#440` | the wait *was* bounded and did time out; what remains is pool state for a departed owner | **22** Abandoned Request State |
| 110 | `emqx/emqx#17184` | the call bounded itself (5000ms) and returned; `{error,{timeout,_}}` had no clause | **31** Transient Failure Treated as Permanent |
| 2 | `erlang/otp@85ef200f` | the `receive` has a catch-all `Msg ->`, so it fails rather than blocks | **24** Interleaving Race |

### Count roots, not examples

53 of the 116 examples carry a `linked_to_candidate_key` pointing at another example — the same
fix recorded twice, once as a PR and once as its commit (23 and 24 are one such pair, both
family 8). `roots` = 63 is the deduplicated figure and it is what family counts should be
computed against; assigning by `examples.id` would inflate every family by roughly 1.8×.

---

## Examples that want another look

Reading diffs for distillation is a second pass over decisions a human already made, so it
occasionally disagrees with one. Those disagreements are logged here rather than acted on — the
human pass remains the decision.

Two kinds appear so far: candidates that fix no failure at all, and one relation the schema
cannot currently express.

### Confirmed as examples, but no failure is fixed

| example | key | what the diff actually is | how sure |
|---|---|---|---|
| **102** | `doorgan/sourceror#208` | *"fix: clear all sourceror compilation warnings"* — unreachable `with/else` clauses and a `mix.exs` deprecation. A warnings cleanup. **Also recorded as `language=erlang` when sourceror is Elixir** — the only such mismatch found among the repos checked. | certain — read in full during the family 8 pass |
| **113** | `atomvm/AtomVM#1961` | adds OTP-28 timeout tuple return actions to AtomVM's `gen_server`; listed under **"Added"** in the project's own CHANGELOG | certain — read in full during the family 35 pass |
| **115** | `erlang/otp#9287` | *"Augment `gen_server` timeout handling"* — feature work that **introduced** the regression fixed by 114. Recorded as a fix; it is the opposite | certain — see the relation below |
| 104 | `sneako/finch#299` | adds a new public API, `Finch.stop_pool/2`. `+93/-1`, and the single removed line is a `case Registry.lookup(...)` being rewritten. Matched on the keyword *process leak*; no leak is fixed | likely — diff structure only, not read in full |
| 54 | `atomvm/AtomVM#2348` | adds a `posix_kill/2` NIF so the **test suite** stops leaking `socat` processes. A real symptom, but the change is a feature and the leak is in the harness | borderline — judgement call, flagged not asserted |

For contrast, 27 (`vernemq/vernemq#1890`, *"Improve BCrypt"*) has a feature-shaped title and is a
genuine fix — a missing `max(N - 1, 1)` causing starvation. Title shape alone is not the test.

### One relation the schema cannot hold: 114 ← 115

Example **115 introduced the bug that example 114 fixes**. This is verified, not inferred: 114's
pre-image is byte-identical to 115's post-image at `system_continue/3` and `decode_msg/6`, and
`a70082ceae2c` — the *first* commit of PR #9287 — is the change that replaced `Time` with
`TRef, Hib` in the `sys` state, dropping the pending timeout.

The database already records the causal fact and cannot show it:

- `114.intro_commit_sha` = `343e7c940ad2`, which **is** a commit of PR #9287, so SZZ found the
  right change. It named *"Changes after review"* rather than the originating commit, because
  blame attributes a line to whatever last touched it — a known SZZ weakness, and worth knowing
  that it bit here.
- `linked_to_candidate_key` cannot carry it. Everywhere else it means *"the same fix, recorded
  twice"*; 114 and 115 are different events, and overloading it would corrupt the dedup signal
  that `roots` is computed from.
- So nothing joins `114.intro_commit_sha` back to `examples.id = 115`, and the pair reads as two
  unrelated `gen_server` timeout examples nine days apart.

`bug_lifespan_days` for 114 is currently 24.0, measured from a commit that lived on a branch.
The bug was on master for 9 days (2025-03-12 → 2025-03-21). Which of those the corpus means is a
policy question the field does not currently distinguish.
