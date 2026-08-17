MODULES = observe amna boundary run
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
# e.g.  make run matrix
#       make run b r1
# 'all' rather than empty: erl -s run main with no args calls run:main/0.
_RUN_ARGS := $(filter-out run, $(MAKECMDGOALS))
ARGS      ?= $(if $(_RUN_ARGS), $(_RUN_ARGS), all)

# Run: pass all args after 'make run ARGS="..."'
.PHONY: run
run: all
	$(ERL) -noshell -s run main $(ARGS) -s init stop

# Drop into a shell with everything loaded, for poking at scenarios by hand.
# e.g.  S = amna:run(b, r1), observe:format(observe:vector(maps:get(waiter, S))).
.PHONY: shell
shell: all
	$(ERL) -pa .

# Silently absorb the extra words so Make doesn't treat them as targets
%:
	@:

.PHONY: clean
clean:
	rm -f $(BEAMS)
