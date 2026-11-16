# Compile-check every card's module, and run a card's demo.
#   make check            compile all modules (warnings on) into _build/
#   make demo M=<module>  run <module>:demo/0, e.g. make demo M=queued_not_applied
#   make demos            run every demo (restart_budget takes a couple of seconds)
ERLC ?= erlc
SRC  := $(wildcard [0-9][0-9]-*/*.erl)
MODS := $(basename $(notdir $(SRC)))

check:
	@mkdir -p _build
	@for f in $(SRC); do $(ERLC) -Wall -o _build $$f || exit 1; done
	@echo "compiled $(words $(SRC)) modules"

demo: check
	@erl -noshell -pa _build -eval 'io:format("~p~n", [$(M):demo()]), halt().' </dev/null

demos: check
	@for m in $(MODS); do echo "== $$m"; erl -noshell -pa _build -eval "io:format(\"~p~n\", [$$m:demo()]), halt()." </dev/null; done

.PHONY: check demo demos
