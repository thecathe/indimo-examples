# Indimo Examples

Here are some examples of invariants.

> **Note:** I use `nix` to manage the packages for these examples. See the section [below](#requirements).

## Examples

### [Failure Families](./families/README.md)

Runnable distillations of a **taxonomy of failure classes** in BEAM systems, drawn from the confirmed real-world examples mined by [beam-bug-crawler](https://github.com/thecathe/beam-bug-crawler). Each family names a *symptom* and carries an `invariant_class` -- the property being violated -- which is what makes it checkable rather than merely descriptive.

Where the examples below start from an invariant and ask what it implies, these start from a family of real bugs and ask whether its invariant holds up: whether the symptom can be produced from several unrelated causes, and whether the family can be told apart from its neighbours by observation.

- [Awaited Message Never Arrives](./families/awaited-message-never-arrives/README.md) (family 8) -- *every wait on a peer either observes that peer's death or bounds itself*. Shows that the invariant's two escape hatches are **not** alternatives: a monitor rescues only the case where the peer dies. Also marks where observation runs out -- Mutual Blocking is indistinguishable from this family unless the waits were monitored.

### [FindAll](./findall/README.md)

Demonstrates how values passed as parameters to a function can sometimes indicate whether the function will deadlock or not.
Motivates **parametric invariants** over functions -- where invariant indicates "safe" values. 

> Julien's favourite ***Go*** example.

- [Go](./findall/go/run.go) -- (from proposal)
- [Erlang](./findall/erlang/README.md)-- Crude AI-translation of the ***Go*** code (implements FIFO channels)

### [Rates](./rates/README.md)

Attempt of framing the rates of interactions (e.g., Producer/Consumer) as an invariant -- i.e., *parametric rate-based invariant*.

- [Go](./rates/go/run.go)
- [Erlang](./rates/erlang/basic.erl)

### [Timed Rates](./rates-timed/erlang/README.md) (Erlang only)

A *producer/consumer* scenario where the *rates* of production and consumption are parameterized, as well as the *ratio* of producers per consumer. *(See the [config](./rates-timed/erlang/config/sys.config) for additional parameters, e.g., `tick` unit)*

- [`supervisor`](./rates-timed/erlang/src/rate_demo_sup.erl) starts everything using the [config](./rates-timed/erlang/config/sys.config) and [parameters](./rates-timed/erlang/makefile).
  - Spawns a single [`consumer`](./rates-timed/erlang/src/consumer.erl) process that can only consume at the rate specified by `consumer_rate`.
    - Implements `gen_statem` behaviour 
      - with states: `[waiting,consume]`
      - initially `waiting`
      - `handle_event` any `info` -> `postpone`
      - after timeout of `rate` -> `consume` 
      - `consume` -> receive one (possibly postponed) message -> `waiting`
  - Spawns number of [`producer`](./rates-timed/erlang/src/producer.erl) processes to match the `ratio`, eacn sends messages to `consumer` at the rate specified by `producer_rate`.
    - Implements `gen_server` behaviour
      - uses `send_after` to `self` to trigger itself sending next message
  - Spawns [`queue_monitor`](./rates-timed/erlang/src/queue_monitor.erl) process that periodically polls the number of items in the mailbox of `consumer` and measures the trend over a configurable sample window to determine if the mailbox is growing or stable.


### [SSA](./ssa/README.md)

> *Static Single Assignment* (SSA)

Experiment to see how ***Go*** and ***Erlang*** programs look after they have been compiled into a SSA encoding (i.e., similar to `let x = y in z`).

- Go (Claude generated) -- see [`jssa`](./ssa/go/jssa/jssa.go) and the output of [this test](./ssa/go/jssatest/jssatest.go)
- [Erlang](./ssa/erlang/README.md) -- explore different BEAM compiler options to obtain various forms of a given program. Tested on [this](./ssa/erlang/main.erl).

---

## Requirements

Ideally you have the following installed on your system:
- `nix` 
- `direnv`

### Installing `nix`

Follow instructions for ***package manager*** [here](https://nixos.org/download/).

### Installing `direnv`

#### Post-installation

Once installed, you will need to add a **hook** for direnv inside your `rc` file. E.g., if you are using `bash` then:
```
eval "$(direnv hook bash)"
```

Just swap out `bash` for whichever shell you use. E.g., `bash`, `zsh`, `fish`

#### Project setup

Run the following command in the project root:
```
direnv allow .
```

Now whenever you enter the directory in the shell it will automatically load `.envrc` which loads all the dependencies from `nix` into the shell environment. 

> ***Note:*** You may need to start a fresh terminal or re-enter the directory for it to take effect.
