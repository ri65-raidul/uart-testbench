REPO_ROOT := $(shell git rev-parse --show-toplevel)
SV_UTILS  := $(REPO_ROOT)/verif_ip/sv_utils

UART_TEST_DIR := $(REPO_ROOT)/ip/uart/verif/test_sv/top_test
MODULES_FILE  := ip/uart/verif/test_sv/top_test/build/modules.f
TEST_TOP      := uart_test_top
EXECUTABLE    := simv_$(TEST_TOP)_RTL

GEN_WAVES    ?= True
GEN_COVERAGE ?= True
SIM_ARGS     ?=

DIRECTED_TESTS := 1 2 3 4 5 6 7 8 9 10 11
COVERAGE_TYPES := line+cond+tgl+fsm+branch+assert

ifeq ($(GEN_COVERAGE),True)
COVERAGE_ARGS := -cm $(COVERAGE_TYPES)
endif

.DEFAULT_GOAL := test

.PHONY: compile uart_test test directed coverage coverage_reports clean

compile:
	$(MAKE) -f $(SV_UTILS)/run_vcs.mk compile \
		TEST_TOP=$(TEST_TOP) \
		MODULES_FILE=$(MODULES_FILE) \
		GEN_WAVES=$(GEN_WAVES) \
		GEN_COVERAGE=$(GEN_COVERAGE) \
		SPECIFIC_COMPILE_ARGS="+incdir+$(REPO_ROOT)+$(UART_TEST_DIR)"

uart_test: compile

test: compile
	./$(EXECUTABLE) \
		$(COVERAGE_ARGS) \
		$(SIM_ARGS)

directed: compile
	@set -e; \
	for test_id in $(DIRECTED_TESTS); do \
		echo "Running UART directed test $$test_id"; \
		./$(EXECUTABLE) \
			$(COVERAGE_ARGS) \
			$(if $(COVERAGE_ARGS),-cm_name uart_test_$$test_id) \
			$(SIM_ARGS) \
			+test-case=$$test_id; \
	done

coverage:
	$(MAKE) directed GEN_COVERAGE=True
	$(MAKE) coverage_reports

coverage_reports:
	$(MAKE) -f $(SV_UTILS)/run_vcs.mk coverage_reports

clean:
	$(MAKE) -f $(SV_UTILS)/run_vcs.mk clean