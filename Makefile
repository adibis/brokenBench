BUILD_DIR      := .build
SCRIPTS        := scripts
PYTHON         := python3
VERILATOR      := verilator
VERIBLE_FORMAT := verible-verilog-format
VFLAGS         := --binary --timing -j 0 -Wno-fatal -Wno-IMPLICITSTATIC
# z3's default invocation has no timeout: proving a genuinely-unsatisfiable
# constraint set (several unpatched exercises are unsatisfiable by design)
# can take far longer than finding a satisfying assignment does, and can
# leave `make run`/`make check` hanging with no feedback. Bound it -- a
# solver timeout makes randomize() return 0, the same outcome an unsolved
# constraint set already produces.
SOLVER_ENV := VERILATOR_SOLVER="z3 -t:10000 --in"

# ANSI colors, ziglings/rustlings-style: respect NO_COLOR (https://no-color.org/)
# and skip colorizing when stdout isn't a real terminal (piped to a file, a
# CI log capture that won't render escape codes usefully). Set up as a shell
# snippet run at the *start of each recipe*, not a $(shell ...)-computed Make
# variable: $(shell ...) captures its command's stdout into a pipe to build
# the variable's value, so `[ -t 1 ]` run that way can never see the real
# terminal -- it always sees the capture pipe. Recipes don't have that
# problem; their stdout is make's own, so the check is meaningful there.
define setup_colors
RED=""; GREEN=""; BOLD=""; RESET=""; \
if [ -z "$$NO_COLOR" ] && [ -t 1 ]; then \
	RED=$$(printf '\033[31m'); GREEN=$$(printf '\033[32m'); \
	BOLD=$$(printf '\033[1m'); RESET=$$(printf '\033[0m'); \
fi
endef

help:
	@echo "brokenbench -- fix the broken SystemVerilog, make it pass."
	@echo ""
	@echo "learn/          never touched SV before? start here."
	@echo "exercises/sv/   interview-prep, real constrained-random gotchas."
	@echo "exercises/uvm/  UVM component bugs (scoreboards, config_db, phasing)."
	@echo "exercises/csr/  uvm_reg / register-map exercises."
	@echo ""
	@echo "  make run EX=missing_rand              compile and run one exercise by slug"
	@echo "  make run EX=and_instead_of_implies"
	@echo "  make watch EX=missing_rand            re-run automatically every time you save the file"
	@echo "  make check TRACK=learn                run a whole track in order, stop at the first failure"
	@echo "  make check TRACK=sv"
	@echo "  make check TRACK=sv EX=cyclic_rand_constraint   start partway through a track"
	@echo "  make find TAG=multi-constraint         list exercises with a tag (see manifest.toml)"
	@echo "  make find TAG=multi-constraint TRACK=sv"
	@echo "  make list                              list every exercise in every track, with tags"
	@echo "  make format                            reformat learn/ and exercises/ with verible"
	@echo "  make format-check                      check formatting without changing anything (what CI runs)"
	@echo "  make selftest                          prove the checker scripts reject bad input (see tests/ci-selftest/)"
	@echo "  make clean                             remove build artifacts"

# A quiet ASCII rule, not Unicode box-drawing -- has to read fine as plain
# monochrome text in a CI log, a pipe, or NO_COLOR, none of which is
# hypothetical here (all three are real, tested paths for this Makefile).
define fail_compile_banner
echo ""; \
echo "----------------------------------------------------------------------"; \
echo "$${BOLD}$${RED}FAILED TO COMPILE$${RESET}"; \
echo ""; \
echo "  Fix the syntax error above, then run this again:"; \
echo ""; \
echo "    $${BOLD}make run EX=$$name$${RESET}"; \
echo "----------------------------------------------------------------------"
endef

define fail_run_banner
echo ""; \
echo "----------------------------------------------------------------------"; \
echo "$${BOLD}$${RED}EXERCISE FAILED$${RESET}"; \
echo ""; \
echo "  Open the file, fix the logic, then run this again:"; \
echo ""; \
echo "    $$f"; \
echo ""; \
echo "    $${BOLD}make run EX=$$name$${RESET}"; \
echo "----------------------------------------------------------------------"
endef

run:
	@$(setup_colors); \
	test -n "$(EX)" || (echo "usage: make run EX=missing_rand  (or EX=and_instead_of_implies)" && exit 1); \
	f=$$($(PYTHON) $(SCRIPTS)/find_exercise.py --slug "$(EX)") || exit 1; \
	name=$$(basename $$f .sv); \
	mkdir -p $(BUILD_DIR)/$$name; \
	echo "=== $$name ==="; \
	$(VERILATOR) $(VFLAGS) $$f --top-module top -o sim -Mdir $(BUILD_DIR)/$$name > $(BUILD_DIR)/$$name/build.log 2>&1; \
	build_ok=$$?; \
	if [ $$build_ok -ne 0 ]; then \
		grep -A4 "%Error" $(BUILD_DIR)/$$name/build.log || tail -20 $(BUILD_DIR)/$$name/build.log; \
		$(fail_compile_banner); \
		exit 1; \
	fi; \
	out=$$($(SOLVER_ENV) $(BUILD_DIR)/$$name/sim 2>&1); \
	run_ok=$$?; \
	echo "$$out" | grep -Ev '^\[.*\] %Fatal|^%Error|^Aborting\.\.\.|^- ' \
		| sed -E "s/^(PASS:.*)/$${GREEN}\1$${RESET}/; s/^(FAIL:.*)/$${RED}\1$${RESET}/"; \
	if [ $$run_ok -eq 0 ]; then \
		next_path=$$($(PYTHON) $(SCRIPTS)/find_exercise.py --after "$(EX)"); \
		echo ""; \
		echo "----------------------------------------------------------------------"; \
		echo "$${BOLD}$${GREEN}PASSED$${RESET}"; \
		echo ""; \
		if [ -n "$$next_path" ]; then \
			next_name=$$(basename $$next_path .sv); \
			echo "  Nice work. Next up:"; \
			echo ""; \
			echo "    $${BOLD}make run EX=$$next_name$${RESET}"; \
			echo ""; \
			echo "  OR to get a list of all available exercises:"; \
			echo ""; \
			echo "    $${BOLD}make list$${RESET}"; \
		else \
			echo "  Nice work -- that's the last one in this track. To pick another:"; \
			echo ""; \
			echo "    $${BOLD}make list$${RESET}"; \
		fi; \
		echo "----------------------------------------------------------------------"; \
	else \
		$(fail_run_banner); \
	fi; \
	exit $$run_ok

# Poll-based, not inotify/fswatch -- neither is a dependency this repo wants
# (macOS has no inotify at all, and fswatch isn't preinstalled anywhere).
# `stat`'s mtime flag differs between GNU and BSD, and they don't fail the
# same way: GNU's `-f` silently means something else entirely (filesystem
# status, not file status) rather than erroring, so trying it first and
# falling back on failure isn't safe. BSD's `-c` errors hard (confirmed
# directly: "illegal option -- c", exit 1) so trying GNU's `-c %Y` first
# and falling back to BSD's `-f %m` only on a genuine failure is the safe
# order -- the reverse order risks reading a mount point as a timestamp.
#
# Auto-advances on pass, same as rustlings' watch mode (confirmed directly
# against its source: on a passing test it moves to the next exercise and
# runs it immediately, rather than sitting on the now-solved file) -- the
# whole point of watch mode is cutting the edit/save/rerun loop, and
# re-typing `make watch EX=<next>` by hand for every exercise defeats that.
watch:
	@$(setup_colors); \
	test -n "$(EX)" || (echo "usage: make watch EX=missing_rand" && exit 1); \
	cur="$(EX)"; \
	f=$$($(PYTHON) $(SCRIPTS)/find_exercise.py --slug "$$cur") || exit 1; \
	trap 'echo ""; echo "stopped watching."; exit 0' INT; \
	last_mtime=""; \
	while true; do \
		mtime=$$(stat -c %Y "$$f" 2>/dev/null || stat -f %m "$$f" 2>/dev/null); \
		if [ "$$mtime" != "$$last_mtime" ]; then \
			last_mtime="$$mtime"; \
			[ -t 1 ] && clear; \
			$(MAKE) --no-print-directory run EX="$$cur"; \
			run_ok=$$?; \
			if [ $$run_ok -eq 0 ]; then \
				next_path=$$($(PYTHON) $(SCRIPTS)/find_exercise.py --after "$$cur"); \
				if [ -n "$$next_path" ]; then \
					cur=$$(basename $$next_path .sv); \
					f="$$next_path"; \
					last_mtime=""; \
					echo ""; \
					echo "$${BOLD}$${GREEN}--> moving on to $$cur$${RESET}"; \
					continue; \
				fi; \
				echo ""; \
				echo "======================================================================"; \
				echo "$${BOLD}$${GREEN}That was the last exercise in this track. Nice work!$${RESET}"; \
				echo "======================================================================"; \
				exit 0; \
			fi; \
			echo ""; \
			echo "watching $$f for changes -- Ctrl-C to stop"; \
		fi; \
		sleep 0.5; \
	done

check:
	@$(setup_colors); \
	track="$(TRACK)"; \
	if [ -z "$$track" ]; then echo "usage: make check TRACK=learn  (or TRACK=sv, uvm, csr)"; exit 1; fi; \
	started=1; \
	start_path=""; \
	if [ -n "$(EX)" ]; then \
		start_path=$$($(PYTHON) $(SCRIPTS)/find_exercise.py --slug "$(EX)") || exit 1; \
		started=0; \
	fi; \
	paths=$$($(PYTHON) $(SCRIPTS)/find_exercise.py --track $$track); \
	total=$$(echo "$$paths" | grep -c .); \
	idx=0; \
	failed=0; \
	for f in $$paths; do \
		idx=$$((idx + 1)); \
		if [ $$started -eq 0 ]; then \
			if [ "$$f" = "$$start_path" ]; then started=1; else continue; fi; \
		fi; \
		name=$$(basename $$f .sv); \
		mkdir -p $(BUILD_DIR)/$$name; \
		echo "=== [$$idx/$$total] $$name ==="; \
		$(VERILATOR) $(VFLAGS) $$f --top-module top -o sim -Mdir $(BUILD_DIR)/$$name > $(BUILD_DIR)/$$name/build.log 2>&1; \
		if [ $$? -ne 0 ]; then \
			grep -A4 "%Error" $(BUILD_DIR)/$$name/build.log || tail -20 $(BUILD_DIR)/$$name/build.log; \
			echo ""; \
			echo "----------------------------------------------------------------------"; \
			echo "$${BOLD}$${RED}TRACK STOPPED -- exercise $$idx of $$total failed to compile$${RESET}"; \
			echo ""; \
			echo "  Fix the syntax error above, then resume this exercise:"; \
			echo ""; \
			echo "    $${BOLD}make run EX=$$name$${RESET}"; \
			echo ""; \
			echo "  Once it passes, resume the whole track:"; \
			echo ""; \
			echo "    $${BOLD}make check TRACK=$$track EX=$$name$${RESET}"; \
			echo "----------------------------------------------------------------------"; \
			failed=1; break; \
		fi; \
		out=$$($(SOLVER_ENV) $(BUILD_DIR)/$$name/sim 2>&1); \
		run_ok=$$?; \
		if [ $$run_ok -ne 0 ]; then \
			echo "$$out" | grep -Ev '^\[.*\] %Fatal|^%Error|^Aborting\.\.\.|^- '; \
			echo ""; \
			echo "----------------------------------------------------------------------"; \
			echo "$${BOLD}$${RED}TRACK STOPPED -- exercise $$idx of $$total failed$${RESET}"; \
			echo ""; \
			echo "  Open the file, fix the logic, then resume this exercise:"; \
			echo ""; \
			echo "    $$f"; \
			echo ""; \
			echo "    $${BOLD}make run EX=$$name$${RESET}"; \
			echo ""; \
			echo "  Once it passes, resume the whole track:"; \
			echo ""; \
			echo "    $${BOLD}make check TRACK=$$track EX=$$name$${RESET}"; \
			echo "----------------------------------------------------------------------"; \
			failed=1; break; \
		else \
			echo "$$name: $${GREEN}pass$${RESET}"; \
		fi; \
	done; \
	if [ $$started -eq 0 ]; then \
		echo "EX=$(EX) is not in track $$track -- nothing was actually checked" >&2; \
		exit 1; \
	fi; \
	if [ $$failed -eq 0 ]; then \
		echo ""; \
		echo "======================================================================"; \
		echo "$${BOLD}$${GREEN}ALL $$total EXERCISES IN $$track PASSED$${RESET}"; \
		echo ""; \
		echo "  You're done with this track."; \
		echo "======================================================================"; \
	fi; \
	exit $$failed

find:
	@args=""; \
	for t in $(TAG); do args="$$args --tag $$t"; done; \
	if [ -n "$(TRACK)" ]; then args="$$args --track $(TRACK)"; fi; \
	if [ -z "$$args" ]; then echo "usage: make find TAG=multi-constraint  (optionally + TRACK=learn/sv/uvm/csr)"; exit 1; fi; \
	$(PYTHON) $(SCRIPTS)/find_exercise.py $$args

list:
	@echo "learn/ -- never touched SV before? start here:"
	@$(PYTHON) $(SCRIPTS)/find_exercise.py --list --track learn
	@echo ""
	@echo "exercises/sv/ -- interview-prep, real constrained-random gotchas:"
	@$(PYTHON) $(SCRIPTS)/find_exercise.py --list --track sv
	@echo ""
	@echo "exercises/uvm/ -- UVM component bugs:"
	@$(PYTHON) $(SCRIPTS)/find_exercise.py --list --track uvm
	@echo ""
	@echo "exercises/csr/ -- uvm_reg / register-map exercises:"
	@$(PYTHON) $(SCRIPTS)/find_exercise.py --list --track csr

format:
	@find learn exercises -name '*.sv' -exec $(VERIBLE_FORMAT) --inplace {} +
	@echo "formatted."

# --verify (unlike --inplace) only accepts one file per invocation, so this
# loops rather than batching with `find -exec ... +`.
format-check:
	@failed=0; \
	for f in $$(find learn exercises -name '*.sv'); do \
		$(VERIBLE_FORMAT) --verify "$$f" >/dev/null 2>&1 || { echo "not formatted: $$f"; failed=1; }; \
	done; \
	if [ $$failed -ne 0 ]; then echo "run 'make format' to fix"; exit 1; fi; \
	echo "already formatted."

selftest:
	@$(PYTHON) tests/ci-selftest/run_selftest.py --group all

clean:
	rm -rf $(BUILD_DIR)

.PHONY: help run watch check find list format format-check selftest clean
