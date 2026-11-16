# 02 — The barrier by order

> *AI-generated: Claude Sonnet 5.5, effort unrecorded; first generated 2026-11-16, last edited 2026-11-16. Source readings are summaries of survey fixes; see "Sources" for what was read.*

**Verdict:** helps avoid (separate the worlds, using the channel's order as the source of information).
**Topics:** asynchronous effect visibility, ordering.

## Scenario
A test asserted something that depends on a message from another node having been handled. It assumed that sending is instant. It is
not, so the test failed intermittently. The fix does not wait a fixed time. It asks each *other* node to call the local server on
the test's behalf. The other node's earlier message and its later call travel on the same channel and arrive in order, so when the reply
comes the earlier message has already been handled.

## Interaction
```
 test            local server s            other node b
  |                                         | (has a notice for s, will send it late)
  | --- ping_via(s) ----------------------> |
  |                      <-- check_for_updates (b's earlier message) --- |
  |                      <-- ping (b's later call) ------------------- |
  |                      handles check, then ping, replies pong
  | <-------------------------- pong(1) via b ------------------------- |
```
Asking *s directly* from the test can return before `check_for_updates` arrives (the buggy barrier): `direct = 0`, `via b = 1`.

## Erlang
[`order_as_barrier.erl`](order_as_barrier.erl). `make demo M=order_as_barrier`.

## The layer in four lines
- **View.** The test holds a reply from s.
- **Worlds.** W1: b's earlier message has been handled. W2: it is still in flight.
- **What the code does.** The direct ping treats the reply as evidence for W1; a direct reply says nothing about b's message.
- **What is missing.** A reply is evidence about the earlier message only if it travels the same FIFO channel as that message. Knowledge is
  obtained by *ordering*, not by content.

## What helps
- **Avoid:** the via-b barrier. The assumption is explicit: per-channel FIFO and the same sender. A reply that took another route proves nothing.
- **Detect:** a monitor that knows the channel structure (which messages share a channel) can derive the happens-before fact and check
  that a test's synchronisation point is on the right channel. Static, from the structure; no run needed.
- **Caveat to check:** this model uses one sender process, where the language guarantees order. The real fix calls through the other node's
  RPC server, which relies on the single distribution connection's order, an implementation property that the reviewers read as sufficient. Not verified here.

## Needs
Per-pair FIFO in the calculus (it has it); a counter in the server (data).

## Sources
`esl/MongooseIM#4072`, fix `017a1b5894ae57e4a151ee47aa131ec7644f15b5`, accepted in all three passes under Asynchronous Effect Visibility;
the diff was read in part (the printed diff was truncated).
