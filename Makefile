BUILD_DIR  := .build
SCRIPTS    := scripts
PYTHON     := python3
VERILATOR  := verilator
VFLAGS     := --binary --timing -j 0 -Wno-fatal -Wno-IMPLICITSTATIC

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
	@echo "  make check TRACK=learn                run a whole track in order, stop at the first failure"
	@echo "  make check TRACK=sv"
	@echo "  make check TRACK=sv EX=cyclic_rand_constraint   start partway through a track"
	@echo "  make find TAG=multi-constraint         list exercises with a tag (see manifest.toml)"
	@echo "  make find TAG=multi-constraint TRACK=sv"
	@echo "  make list                              list every exercise in every track, with tags"
	@echo "  make clean                             remove build artifacts"

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
		echo "$${RED}--- compile failed ---$${RESET}"; \
		grep -A4 "%Error" $(BUILD_DIR)/$$name/build.log || tail -20 $(BUILD_DIR)/$$name/build.log; \
		exit 1; \
	fi; \
	out=$$($(BUILD_DIR)/$$name/sim 2>&1); \
	run_ok=$$?; \
	echo "$$out" | sed -E "s/^(PASS:.*)/$${GREEN}\1$${RESET}/; s/^(FAIL:.*|%Fatal.*|%Error.*)/$${RED}\1$${RESET}/"; \
	exit $$run_ok

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
	failed=0; \
	for f in $$($(PYTHON) $(SCRIPTS)/find_exercise.py --track $$track); do \
		if [ $$started -eq 0 ]; then \
			if [ "$$f" = "$$start_path" ]; then started=1; else continue; fi; \
		fi; \
		name=$$(basename $$f .sv); \
		mkdir -p $(BUILD_DIR)/$$name; \
		$(VERILATOR) $(VFLAGS) $$f --top-module top -o sim -Mdir $(BUILD_DIR)/$$name > $(BUILD_DIR)/$$name/build.log 2>&1; \
		if [ $$? -ne 0 ]; then \
			echo "$$name: $${RED}COMPILE ERROR$${RESET}"; \
			grep -A4 "%Error" $(BUILD_DIR)/$$name/build.log || tail -20 $(BUILD_DIR)/$$name/build.log; \
			failed=1; break; \
		fi; \
		out=$$($(BUILD_DIR)/$$name/sim 2>&1); \
		run_ok=$$?; \
		if [ $$run_ok -ne 0 ]; then \
			echo "$$name: $${RED}FAIL$${RESET}"; \
			echo "$$out" | grep -E "^FAIL|%Fatal|%Error"; \
			failed=1; break; \
		else \
			echo "$$name: $${GREEN}pass$${RESET}"; \
		fi; \
	done; \
	if [ $$failed -eq 0 ]; then echo ""; echo "$${GREEN}$${BOLD}All exercises in $$track pass.$${RESET}"; fi

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

clean:
	rm -rf $(BUILD_DIR)

.PHONY: help run check find list clean
