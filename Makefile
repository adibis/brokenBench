BUILD_DIR := .build
VERILATOR := verilator
VFLAGS := --binary --timing -j 0 -Wno-fatal -Wno-IMPLICITSTATIC

help:
	@echo "brokenbench -- fix the broken SystemVerilog, make it pass."
	@echo ""
	@echo "Two tracks:"
	@echo "  learn/      never touched SV before? start here."
	@echo "  exercises/  interview-prep, real constrained-random gotchas."
	@echo ""
	@echo "  make run EX=LEARN_01     compile and run one exercise (learn or exercises)"
	@echo "  make run EX=EX_05"
	@echo "  make check TRACK=learn       run a whole track in order, stop at the first failure"
	@echo "  make check TRACK=exercises"
	@echo "  make list                    list every exercise in both tracks"
	@echo "  make clean                   remove build artifacts"

# resolves EX=LEARN_01 or EX=EX_05_and_instead_of_implies to the actual file,
# searching both tracks so the caller doesn't need to know which one it's in
define find_exercise
$(firstword $(wildcard learn/$(1)*.sv) $(wildcard exercises/$(1)*.sv))
endef

run:
	@test -n "$(EX)" || (echo "usage: make run EX=LEARN_01  (or EX=EX_05)" && exit 1)
	@f="$(call find_exercise,$(EX))"; \
	if [ -z "$$f" ]; then echo "no exercise matching '$(EX)' in learn/ or exercises/"; exit 1; fi; \
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
	start="$(EX)"; \
	failed=0; \
	for f in $(sort $(wildcard learn/*.sv)) $(sort $(wildcard exercises/*.sv)); do \
		case "$$f" in $$track/*) ;; *) continue ;; esac; \
		name=$$(basename $$f .sv); \
		if [ -n "$$start" ] && [ "$$name" \< "$$start" ]; then continue; fi; \
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

list:
	@echo "learn/ -- never touched SV before? start here:"
	@ls learn/*.sv | xargs -n1 basename
	@echo ""
	@echo "exercises/ -- interview-prep, real constrained-random gotchas:"
	@ls exercises/*.sv | xargs -n1 basename

clean:
	rm -rf $(BUILD_DIR)

.PHONY: help run check list clean
