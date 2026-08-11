# FindAll Example

A ***Go*** example demonstrating a **parametric invariant** on the bounds of channels.

> **Note:** This example is an expanded version a snippet directly taken from the INDIMO project proposal (page 3). Since the type `P` was not specified, I've just set it to `int`.

## The Invariant

The main thread will spawn `k` number of *workers* to produce some data. The data may be returned along a channel `found` of bound `n`, but the number of *workers* that can exist at any time is to be limited to `m`. 

The implementation of `FindAll` (lines 20--38 of [`run.go`](./go/run.go)) features a channel `limit` (bounded by `m`) that functions as a "stack" for "tokens" representing workers to be pushed and popped from. Specifically, the main thread must be able to push a token to the stack (i.e., *send* to `limit`) in order to spawn a worker. After a worker as sent some data on `found`, they then "deallocate" themselves from the limit by receiving from `limit` and then terminate.

To summarise:

- workers cannot deallocate themselves if `found` is full
- the main thread must wait for workers to deallocate themselves if `limit` is full
- *and crucially:* the main thread cannot receive from `found` until they have finished spawning `k` number of workers.

Herein lies the crux of this example: a deadlock occurs if there are more workers `k` than the number of workers that are allowed to finish `n` and the number of workers allowed to work at the same time `m`. I.e.:

```
(n + m) >= k
```

## Run

> *Assuming you're in the each directory*

### Go

```shell
go run run.go safe   # 'safe' hardcoded preset
go run run.go unsafe # 'unsafe' hardcoded preset
go run run.go 3 2 1  # use n=1 m=2 k=3
```

### Erlang

```shell
make run safe   # 'safe' hardcoded preset
make run unsafe # 'unsafe' hardcoded preset
make run 3 2 1  # use n=1 m=2 k=3
```