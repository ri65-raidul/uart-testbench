REPO_ROOT := $(shell git rev-parse --show-toplevel)
SV_UTILS  := $(REPO_ROOT)/verif_ip/sv_utils

MODULES_FILE := ip/uart/verif/test_sv/baud_gen_test/modules.f
TEST_TOP     := uart_baud_gen_test_top
EXECUTABLE   := simv_$(TEST_TOP)_RTL

.PHONY: compile baud_gen_test test clean

compile:
	$(MAKE) -f $(SV_UTILS)/run_vcs.mk compile \
		TEST_TOP=$(TEST_TOP) \
		MODULES_FILE=$(MODULES_FILE) \
		GEN_WAVES=True \

baud_gen_test: compile

test: compile
	./$(EXECUTABLE) $(COVERAGE_ARGS) $(SIM_ARGS)

clean:
	$(MAKE) -f $(SV_UTILS)/run_vcs.mk clean
