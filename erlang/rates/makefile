REBAR3 = rebar3

# Scenario parameters — override any of these on the command line:
#   make run RATIO=4 PRODUCER_RATE=3 CONSUMER_RATE=10
PRODUCER_RATE ?= 3
CONSUMER_RATE ?= 10
RATIO         ?= 2

.PHONY: all run clean

all:
	$(REBAR3) compile

# sys.config is loaded first (via rebar3's {shell, [{config, ...}]} setting),
# then the --eval overrides replace individual keys before the app boots.
run: all
	$(REBAR3) shell --eval \
	    "application:stop(rate_demo), \
			 application:set_env(rate_demo, producer_rate, $(PRODUCER_RATE)), \
	     application:set_env(rate_demo, consumer_rate, $(CONSUMER_RATE)), \
	     application:set_env(rate_demo, ratio,         $(RATIO)), \
			 application:start(rate_demo)."

clean:
	$(REBAR3) clean