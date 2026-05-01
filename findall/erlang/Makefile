MODULES = main sup run
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
# Falls back to ARGS="..." or the default if none are given.
# e.g.  make run 5000 a b
_RUN_ARGS := $(filter-out run, $(MAKECMDGOALS))
ARGS      ?= $(if $(_RUN_ARGS), $(_RUN_ARGS), no_args_given)
 
# Run: pass all args after 'make run ARGS="..."'
# e.g.  make run ARGS="5000 a b"
.PHONY: run
run: all
	$(ERL) -noshell -s run main $(ARGS)

# Silently absorb the extra words so Make doesn't treat them as targets
%:
	@:
 
.PHONY: clean
clean:
	rm -f $(BEAMS)