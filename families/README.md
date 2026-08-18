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
| 54 | `atomvm/AtomVM#2348` | **16** Non-Process Resource Cardinality | tentative | socat subprocess and its pty pair released only on the happy path, and the release did not release. Test-only, hence tentative — as with 14 |

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

The criterion applied is the corpus's own: **an example is a concurrency bug of interest, whose
diff shows the bug before and how it was fixed after.** Both halves matter. A candidate can fail
by not being a failure, or by being one the diff does not exhibit. See
[how to judge a candidate](#how-to-judge-a-candidate) for what applying it turned out to require.

### Confirmed as examples, but no failure is fixed

Each row below was read in full, not skimmed for shape.

| example | key | what the diff actually is |
|---|---|---|
| **102** | `doorgan/sourceror#208` | *"fix: clear all sourceror compilation warnings"* — unreachable `with/else` clauses and a `mix.exs` deprecation. A warnings cleanup, not a failure. **Also recorded as `language=erlang` when sourceror is Elixir** — the only such mismatch found among the repos checked. |
| **113** | `atomvm/AtomVM#1961` | adds OTP-28 timeout tuple return actions to AtomVM's `gen_server`; listed under **"Added"** in the project's own CHANGELOG. Nothing is broken before. |
| **115** | `erlang/otp#9287` | *"Augment `gen_server` timeout handling"* — feature work that **introduced** the regression fixed by 114. Recorded as a fix; it is the opposite. See the relation below. |
| **104** | `sneako/finch#299` | adds `Finch.stop_pool/2`. The only non-test change to existing code is `Registry.lookup(registry, key)` → `all_pool_instances(registry, key)`, where that function is *defined as* `Registry.lookup(registry, key)` — an extract-method with identical behaviour. Nothing was leaking; the pools simply had no manual termination entry point. Matched on the keyword *process leak*. Worth noting the direction of travel: the new function's own docstring warns it "is not safe with respect to concurrent requests", so the change **adds** a documented race rather than removing one. |

### Corrections to earlier entries in this log

- **54** `atomvm/AtomVM#2348` was listed here as borderline feature work on the strength of its
  title and CHANGELOG line. That was wrong, and a full read shows two real defects: the socat
  subprocess and its pty pair were released only on the happy path (no `try ... after`, so a
  crashing body leaked them), and the release did not actually release — closing the stdout pipe
  leaves socat running and holding both ptys, which is why the new NIF was needed at all, along
  with an `exec` so the signal reaches socat rather than the wrapping shell. Leaked ptys
  accumulate until the system pool is exhausted. Moved to the assignments table as **16**,
  tentative. The `posix_kill/2` NIF is the means; the fix is the `try ... after`.

For contrast, 27 (`vernemq/vernemq#1890`, *"Improve BCrypt"*) also has a feature-shaped title and
is a genuine fix — a missing `max(N - 1, 1)` causing starvation. **Title and CHANGELOG shape are
not evidence in either direction**; 54 and 27 both read as features and are both fixes, while 113
and 115 read as features and are.

### A screen that does not work, recorded so it is not tried again

`intro_method` already flags diffs with no non-trivial removed lines — *"likely a pure addition,
not a modification of buggy code"* — which looks like a ready-made test for the second half of
the criterion. It is not one, in either direction:

- 9 roots carry that flag, and most are unambiguous failures: 23 and 96 (both *certain* family 8),
  45 a livelock, 67 an infinite loop, 72 a process leak. A fix can be a pure addition because
  **the bug was what the code lacked** — OTP fixed 23 by adding a monitor and a `DOWN` clause,
  and nothing needed removing.
- None of 102, 113, 115 or 104 carry it. All four contain refactors, so they have removed lines
  and the screen passes them.

The flag is useful for what it says about SZZ's confidence in an intro commit. It says nothing
about whether a diff exhibits a bug.

### The relation the schema now holds: 114 ← 115

Example **115 introduced the bug that example 114 fixes**. This is verified, not inferred: 114's
pre-image is byte-identical to 115's post-image at `system_continue/3` and `decode_msg/6`, and
`a70082ceae2c` — the *first* commit of PR #9287 — is the change that replaced `Time` with
`TRef, Hib` in the `sys` state, dropping the pending timeout.

The database used to record the causal fact and be unable to show it. `114.intro_commit_sha` was
a commit of PR #9287, so SZZ had found the right change, but nothing joined an `intro_commit_sha`
back to an `examples` row and the pair read as two unrelated `gen_server` timeout examples nine
days apart. Schema **7** adds an `example_relations` table, and the pair is now data:

```
example_relations: erlang/otp#9615 --introduced_by--> erlang/otp#9287
```

Three things about how it is stored, all of which follow from 115's status being unsettled:

- **It keys on `candidate_key`, not `examples.id`, and has no foreign key.** 115 is feature work
  that introduced a failure, so it is a candidate for the `rejected` table — and the provenance
  it gives 114 is the only reason to keep a record of it at all. An `ON DELETE CASCADE` would
  destroy that provenance at exactly the moment it becomes most valuable. Rejecting 115 now
  leaves the relation intact, with its `other_id` honestly reading `null`.
- **It is not `linked_to_candidate_key`.** That column means *"the same fix, recorded twice"* in
  all 53 of its uses and is what `roots` is computed from; 114 and 115 are different events, and
  overloading it would have merged two genuine examples and shrunk the root count. `roots` is
  still 63.
- **The evidence lives on the row.** The relation's `note` carries `a70082ceae2c`, the
  byte-identity finding, and the two dates — so the argument travels with the claim rather than
  sitting only here.

`114.intro_commit_sha` has also been corrected to `a70082ceae2c6ef09ae00f145ec0a3e006049d30`.
SZZ had named *"Changes after review"*, a later commit in the same PR, because blame attributes a
line to whatever last touched it — the standard SZZ weakness, and worth knowing that it bit here.
The correction is marked `hand-corrected:` in `intro_method` rather than dressed up as a blame
result, and that marker makes a bare `rebacktrace` skip the row instead of overwriting it. Both
shas were rebased in one operation and share committer date `2025-02-25T08:49:45Z`, so the
correction moved the sha without moving `intro_commit_date` or `bug_lifespan_days`.

That last point is what forced the remaining question to be settled. `bug_lifespan_days` for 114
is 24.0, measured from a commit that lived on a branch for fifteen of those days; the bug was on
master for 8.71 (2025-03-12 → 2025-03-21). The corpus now **states** which it means — fix minus
intro on committer dates, branch time included — and the export carries the master figure
separately as `days_on_master`, derived from an `introduced_by` relation where the originating
example is a PR, since its `fix_commit_sha` is then the merge commit that put the bug on master.
A `days_on_master_basis` string travels beside it naming what produced it, because the derivation
is gated: 67 of the 116 examples are `commit` kind, where `fix_commit_date` has no merge
semantics at all.

---

## How to judge a candidate

Rules that came out of getting one wrong, each with the case that produced it. They are about
reading candidates, not about running examples — the numbered findings near the top of this file
are the latter.

**1. Read the whole diff before judging. Shape is not evidence.**
`atomvm/AtomVM#2348` (54) was logged here as feature work because its title added a NIF and its
CHANGELOG line said *"Added"*. A full read found two real defects: a resource released only on
the happy path, and a release that did not release. The verdict flipped from *reject* to *family
16*. Nothing about the diff's shape distinguished it from `sneako/finch#299` (104), which is
genuinely a pure feature — only the contents did.

**2. Title and CHANGELOG are not evidence in either direction.**
54 and 27 both read as features and are fixes. 113 and 115 both read as features and are
features. Four cases, both errors available, no correlation.

**3. Separate the means from the fix.**
54's `posix_kill/2` NIF is the mechanism; the fix is the `try ... after`. 26's absolute deadline
is the fix; the 512 MiB body cap is compensation for a property the fix gave up. A diff's
largest or most novel hunk is frequently neither the bug nor the repair.

**4. "Is a fix" and "fixes a failure" are different questions.**
115 is a well-made change that *introduced* a failure. 114 is a fix that moved its bug from one
row of family 35 to another rather than out of the family. Being a competent commit by a core
team says nothing about whether it belongs in a corpus of failures.

**5. Cheap screens do not work here.** The one that looks most promising —
`intro_method`'s pure-addition flag — fails in both directions, for reasons written up above. If
a screen is wanted, it can only narrow what gets read, never decide it.

**6. Count roots, not examples.** 53 of 116 rows are a second copy of a fix already present.

**7. Record the disagreement, do not act on it.** Everything in this file is a proposal. The
human pass is the decision, and the value of a second pass is lost if it quietly overwrites the
first.
