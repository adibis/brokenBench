BUILD_DIR  := .build
SCRIPTS    := scripts
PYTHON     := python3
VERILATOR  := verilator
VFLAGS     := --binary --timing -j 0 -Wno-fatal -Wno-IMPLICITSTATIC

help:
	@echo "brokenbench -- fix the broken SystemVerilog, make it pass."
	@echo ""
	@echo "Two tracks:"
	@echo "  learn/      never touched SV before? start here."
	@echo "  exercises/  interview-prep, real constrained-random gotchas."
	@echo ""
	@echo "  make run EX=missing_rand              compile and run one exercise by slug"
	@echo "  make run EX=and_instead_of_implies"
	@echo "  make check TRACK=learn                run a whole track in order, stop at the first failure"
	@echo "  make check TRACK=exercises"
	@echo "  make check TRACK=exercises EX=cyclic_rand_constraint   start partway through a track"
	@echo "  make find TAG=multi-constraint         list exercises with a tag (see manifest.toml)"
	@echo "  make find TAG=multi-constraint TRACK=exercises"
	@echo "  make list                              list every exercise in both tracks, with tags"
	@echo "  make clean                             remove build artifacts"

run:
	@test -n "$(EX)" || (echo "usage: make run EX=missing_rand  (or EX=and_instead_of_implies)" && exit 1); \
	f=$$($(PYTHON) $(SCRIPTS)/find_exercise.py --slug "$(EX)") || exit 1; \
	name=$$(basename $$f .sv); \
	mkdir -p $(BUILD_DIR)/$$name; \
	echo "=== $$name ==="; \
	$(VERILATOR) $(VFLAGS) $$f --top-module top -o sim -Mdir $(BUILD_DIR)/$$name > $(BUILD_DIR)/$$name/build.log 2>&1; \
	build_ok=$$?; \
	if [ $$build_ok -ne 0 ]; then \
		echo "--- compile failed ---"; \
		grep -A4 "%Error" $(BUILD_DIR)/$$name/build.log || tail -20 $(BUILD_DIR)/$$name/build.log; \
		exit 1; \
	fi; \
	$(BUILD_DIR)/$$name/sim; \
	exit $$?

check:
	@track="$(TRACK)"; \
	if [ -z "$$track" ]; then echo "usage: make check TRACK=learn  (or TRACK=exercises)"; exit 1; fi; \
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
			echo "$$name: COMPILE ERROR"; \
			grep -A4 "%Error" $(BUILD_DIR)/$$name/build.log || tail -20 $(BUILD_DIR)/$$name/build.log; \
			failed=1; break; \
		fi; \
		out=$$($(BUILD_DIR)/$$name/sim 2>&1); \
		run_ok=$$?; \
		if [ $$run_ok -ne 0 ]; then \
			echo "$$name: FAIL"; \
			echo "$$out" | grep -E "^FAIL|%Fatal|%Error"; \
			failed=1; break; \
		else \
			echo "$$name: pass"; \
		fi; \
	done; \
	if [ $$failed -eq 0 ]; then echo ""; echo "All exercises in $$track pass."; fi

find:
	@args=""; \
	for t in $(TAG); do args="$$args --tag $$t"; done; \
	if [ -n "$(TRACK)" ]; then args="$$args --track $(TRACK)"; fi; \
	if [ -z "$$args" ]; then echo "usage: make find TAG=multi-constraint  (optionally + TRACK=learn or TRACK=exercises)"; exit 1; fi; \
	$(PYTHON) $(SCRIPTS)/find_exercise.py $$args

list:
	@echo "learn/ -- never touched SV before? start here:"
	@$(PYTHON) $(SCRIPTS)/find_exercise.py --list --track learn
	@echo ""
	@echo "exercises/ -- interview-prep, real constrained-random gotchas:"
	@$(PYTHON) $(SCRIPTS)/find_exercise.py --list --track exercises

clean:
	rm -rf $(BUILD_DIR)

.PHONY: help run check find list clean
