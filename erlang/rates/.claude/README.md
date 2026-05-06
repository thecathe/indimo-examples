# rate_demo

An Erlang/OTP example demonstrating a **parametric rate-based invariant**
observable at runtime via process mailbox depth.

## The Invariant

```
ratio × producer_rate  ≤  consumer_rate     % STABLE   — queue bounded
ratio × producer_rate  >  consumer_rate     % VIOLATED — queue grows
```

Each producer fires one `{work, Id, SeqNo}` message per tick.
The consumer drains one message per tick. When total offered load
exceeds the consumer's drain rate, messages accumulate.

## Project structure

```
src/
  rate_demo_app.erl     % application behaviour; reads env, logs invariant
  rate_demo_sup.erl     % rest_for_one supervisor; spawns N producers
  consumer.erl          % gen_server; drains mailbox at consumer_rate msg/s
  producer.erl          % gen_server; sends at producer_rate msg/s
  queue_monitor.erl     % gen_server; samples & trends consumer queue depth
config/
  sys.config            % runtime parameters with scenario presets
```

## Build & run

```bash
# requires rebar3 and Erlang/OTP 24+
rebar3 shell
```

This starts the application with the default parameters from `sys.config`
(Scenario A — stable).

## Changing scenarios at the shell

Scenarios can be switched live without recompiling:

```erlang
%% Scenario C — violated (4 * 3 = 12 > 10)
application:stop(rate_demo),
application:set_env(rate_demo, ratio, 4),
application:set_env(rate_demo, producer_rate, 3),
application:set_env(rate_demo, consumer_rate, 10),
application:start(rate_demo).
```

## What to watch

The monitor prints one line per second:

```
[monitor]  queue_depth=   0  slope=  0.00 msg/sample  stable   (invariant holds)
[monitor]  queue_depth=   7  slope=  2.00 msg/sample  GROWING  (invariant VIOLATED)
```

| `slope` | Meaning                          |
|---------|----------------------------------|
| ≈ 0     | Invariant holds; system stable   |
| > 0.5   | Invariant violated; queue grows  |
| < −0.5  | Queue draining (transient)       |

## Supervision strategy

`rest_for_one` is used so that a consumer crash restarts the monitor and
all producers. This ensures producers never accumulate messages to a stale
PID — they re-resolve `rate_consumer` after the consumer re-registers.

## Scenarios

| Scenario        | ratio | producer_rate | consumer_rate | Load | Stable? |
|-----------------|-------|---------------|---------------|------|---------|
| A — default     |   2   |       3       |      10       |  6   | ✓       |
| B — edge        |   2   |       5       |      10       | 10   | ✓ (tight)|
| C — violated    |   4   |       3       |      10       | 12   | ✗       |
| D — overloaded  |   3   |      10       |      10       | 30   | ✗       |
