# [Prompt](https://claude.ai/share/9c203f1d-2a9a-438c-8ead-1fb8eecb97c0)

**You said**: setting up erlang OTP example showcasing parametric rate-based invariant. the entry-point will start a supervisor for a consumer and potentially multiple producers. both the consumer and producers will be parameterized by a rate of which they may send/receive messages. the supervisor will be parameterized by the ratio of producers to consumers it will spawn. my desire here is to create an example that is idiomatic of erlang OTP code that features an invariant that appears tangible (i.e., could be expressed by a condition over the numerical parameters). any notes?
11:11

---

**Claude responded**: Good setup.

Good setup. A few notes worth addressing before writing any code:
The Invariant

The natural invariant here is:

ratio * producer_rate =< consumer_rate

When satisfied, the consumer's mailbox is stable (bounded). When violated, it grows without bound. This is essentially a discrete-time application of Little's Law, and it's directly observable at runtime via process_info(ConsumerPid, message_queue_len) — which makes it unusually tangible for a demo.
Rate Implementation

The idiomatic Erlang pattern is a self-tick loop using erlang:send_after:
erlang

handle_info(tick, State) ->
    do_work(State),
    erlang:send_after(interval(State#state.rate), self(), tick),
    {noreply, State}.

where interval(Rate) -> trunc(1000 / Rate). Kick it off in init/1. Avoid timer:send_interval/2 — it accumulates drift and isn't cancellable cleanly on terminate.
Supervision Structure

A few design choices to nail down:

Child startup order matters. The consumer must be started before producers so its PID (or registered name) is available when producers initialize. one_for_one with ordered child specs in init/1 handles this naturally. If you use rest_for_one, a consumer crash restarts producers too — which is arguably correct behavior (producers sending to a dead consumer would just queue up or crash).

Producer-to-consumer wiring. Register the consumer under a local name (e.g., rate_consumer). Producers reference it by name rather than PID — this survives consumer restarts transparently and is far more idiomatic than passing a PID through the supervisor args.

Spawning N producers. Two options:

    Start all ratio producers statically in Supervisor:init/1 — simpler, fine for a fixed ratio
    Use a simple_one_for_one supervisor for producers with a separate producer_sup — more OTP-correct if you want dynamic scaling, but adds a layer

For an invariant demo, static startup in init/1 is cleaner and keeps the parametrization visible.
Making the Invariant Observable

Add a lightweight monitor process (a plain gen_server or even a proc_lib loop) that periodically samples:
erlang

process_info(whereis(rate_consumer), message_queue_len)

and logs/emits the trend. This makes the invariant violation tangible at runtime — run it with ratio * producer_rate > consumer_rate and watch the queue grow linearly. This is the clearest possible demonstration.
Parametrization Approach

Pass all three parameters (ProducerRate, ConsumerRate, Ratio) into the top-level supervisor via start_link/3. The supervisor propagates ConsumerRate to the consumer child spec and ProducerRate to each producer child spec. Keep them in supervisor state so you can inspect them from the shell.

One thing to be careful of: Ratio as an integer (producers per consumer) is unambiguous. If you want to allow fractional ratios (e.g., 0.5 = one producer per two consumers), the design gets more complex — probably not worth it for a demo.
Application Wrapper

Wrap the whole thing as an OTP application (my_app_app.erl implementing application behaviour). This lets you start it cleanly with application:start(my_app) and pass parameters via application:get_env/2 or sys.config, which is the production-idiomatic way to inject the rate/ratio parameters.

Want me to write the full implementation? I'd structure it as:

```
src/
  rate_demo_app.erl     % application
  rate_demo_sup.erl     % top supervisor (ratio, rates)
  consumer.erl          % gen_server, consumer_rate
  producer.erl          % gen_server, producer_rate
  queue_monitor.erl     % samples consumer queue depth
```

---

**You said**: sure
11:16

---

**Claude responded**: Here's a walkthrough of the key design decisions baked into the implementation:
Created 9 files, ran 3 commands, viewed a file

Here's a walkthrough of the key design decisions baked into the implementation:
Supervision (rate_demo_sup)

rest_for_one is used rather than one_for_one. The child ordering is:

consumer → queue_monitor → producer_1 … producer_N

If the consumer crashes, everything to its right restarts. This matters because producers hold a reference to rate_consumer by name — restarting them ensures they resolve the name fresh after the consumer re-registers. one_for_one would leave producers silently dropping messages to a gone PID.
Rate mechanism (consumer, producer)

Both use erlang:send_after in a self-rescheduling loop rather than timer:send_interval. The critical difference: send_after is always relative to the current moment, so jitter doesn't accumulate. send_interval fires from a fixed origin and can pile up if the process falls behind.

interval(Rate) -> trunc(1000 / Rate) is the single conversion point — easy to audit.
Consumer mailbox discipline

The consumer does not process messages in handle_info as they arrive. Instead, it pulls exactly one message per tick using receive ... after 0 — the after-0 pattern is the idiomatic non-blocking mailbox drain. This enforces the consumer_rate ceiling strictly. Anything beyond one-per-tick accumulates as backpressure, which is exactly the quantity the invariant is about.
Monitor (queue_monitor)

Samples process_info(Pid, message_queue_len) every second and maintains a 5-sample sliding window to compute a simple linear slope. The slope sign is the invariant detector:

    slope ≈ 0 → stable, invariant holds
    slope > 0.5 → growing, invariant violated

Trying scenarios live
```erlang
%% Violate the invariant without restarting the node:
application:stop(rate_demo),
application:set_env(rate_demo, ratio, 4),
application:start(rate_demo).
```

The monitor output will shift from stable to GROWING within a few seconds.

---
