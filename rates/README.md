# Basic Rates

> This is a _simplified_ version of the [timed-rates-based demo](../rates-timed/README.md), where the Producer/Consumer are completely _time unaware_.

Similar to [timed-rates-based demo](../rates-timed/README.md), this example has also been extended with a minimal, lightweight monitor function that periodically samples the message backlog of the consumer, reporting its change.

## The Invariant

It is not clear for this example. While it is reasonable to assume that you just need to leave the number of producers to be 1 so that the consumer can keep up. However, in reality it fluctuates regardless.

In a more realistic example, we would require additional information on the behaviour of the producer and consumer (e.g., how long does it typically take to produce/consume, what are the rates, etc). Given such information, it would then not be infeasible to transform a program like [`basic.erl`](./erlang/basic.erl) into a setup more similar to the [timed-rates-based demo](../rates-timed/README.md).

## Build & Run

> *Assuming you're in the each directory*

### Go

```shell
go run run.go 1 2 3 4
## yields:
##   number of producers:  1
##   rate of producers:    2
##   rate of consumer:     3
##   bound of return chan: 4
```

### Erlang

#### Using `makefile`

```bash
make run                 # spawns 1 producer
make run NUM_PRODUCERS=1 # spawns 1 producer
make run NUM_PRODUCERS=2 # spawns 2 producers
```

#### Using `erl`/`erlc`

```bash
erlc basic.erl && erl -noshell -s basic start   # spawns 1 producer
erlc basic.erl && erl -noshell -s basic start 1 # spawns 1 producer
erlc basic.erl && erl -noshell -s basic start 2 # spawns 2 producers
```

