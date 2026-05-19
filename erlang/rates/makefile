ERLC = erlc
ERL = erl

NUM_PRODUCERS ?= 1

.PHONY: all run

all: 
	$(ERLC) basic.erl

run: all
	$(ERL) -noshell -s basic start $(NUM_PRODUCERS)