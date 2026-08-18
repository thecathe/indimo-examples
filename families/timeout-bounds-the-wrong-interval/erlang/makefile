MODULES = observe tbwi otp_timeout boundary run
BEAMS   = $(MODULES:%=%.beam)
ERLC    = erlc
ERL     = erl

# Default target: compile all modules
.PHONY: all
all: $(BEAMS)

# Compile each .erl to a .beam; any module change triggers its own recompile
%.beam: %.erl
	$(ERLC) $<

# Extra words after 'make run' are forwarded directly as args.
# e.g.  make run cross
#       make run suspended_abs
# 'all' rather than empty: erl -s run main with no args calls run:main/0.
_RUN_ARGS := $(filter-out run, $(MAKECMDGOALS))
ARGS      ?= $(if $(_RUN_ARGS), $(_RUN_ARGS), all)

# Run: pass all args after 'make run ARGS="..."'
.PHONY: run
run: all
	$(ERL) -noshell -s run main $(ARGS) -s init stop

# Drop into a shell with everything loaded, for poking at scenarios by hand.
# e.g.  S = tbwi:scenario(rearmed), observe:gaps(observe:pulses(maps:get(watch, S), 1200)).
.PHONY: shell
shell: all
	$(ERL) -pa .

# Silently absorb the extra words so Make doesn't treat them as targets
%:
	@:

.PHONY: clean
clean:
	rm -f $(BEAMS)
