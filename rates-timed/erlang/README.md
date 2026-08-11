# Demo: Parametric Rate-based Invariant

An Erlang/OTP example demonstrating a **parametric rate-based invariant** that can be detected at runtime. 

> **Note**: This example was refined from an AI generated draft (located in `.claude/`, see [`here`](.claude/README.md)). *Discussed later in [#AI](#ai).*

## The Invariant

A *producer/consumer* scenario where the *rates* of production and consumption are parameterized, as well as the *ratio* of producers per consumer. *(See the [config](./config/sys.config) for additional parameters, e.g., `tick` unit)*

```
(ratio * producer_rate) <= consumer_rate
```

## Build & Run

### Using `makefile`

```shell
make run                                              # uses sys.config defaults
make run RATIO=4                                      # override just ratio parameter
make run RATIO=4 PRODUCER_RATE=3 CONSUMER_RATE=10    # override all three
```

### Using `rebar3`

*See the [AI generated instructions](.claude/README.md#build--run).*

---

## AI

The main use of the AI was to just setup the broad shape and structure of the example. The prompt used to generate the files is located in [`.claude/PROMPT.md`](.claude/PROMPT.md) (see the entire prompt/chat [here](https://claude.ai/share/9c203f1d-2a9a-438c-8ead-1fb8eecb97c0)).

Much of the [`src/consumer.erl`](src/consumer.erl) has been rewritten by hand (including switching behaviour from `gen_server` to `gen_statem`), followed by the necessary changes to [`src/queue_monitor.erl`](src/queue_monitor.erl).

*Noteworthy bits in the [`AI generated README.md`](.claude/README.md):*

- [Scenarios](.claude/README.md#scenarios)
- [What to watch](.claude/README.md#what-to-watch)
