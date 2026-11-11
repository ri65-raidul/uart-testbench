REPO_ROOT := $(shell git rev-parse --show-toplevel)
SV_UTILS  := $(REPO_ROOT)/verif_ip/sv_utils

RX_TEST_DIR  := $(REPO_ROOT)/ip/uart/verif/test_sv/receiver_test
MODULES_FILE := ip/uart/verif/test_sv/receiver_test/modules.f
TEST_TOP     := uart_rx_test_top
EXECUTABLE   := simv_$(TEST_TOP)_RTL

.PHONY: compile uart_rx_test test coverage coverage_reports clean

compile:
	$(MAKE) -f $(SV_UTILS)/run_vcs.mk compile \
		TEST_TOP=$(TEST_TOP) \
		MODULES_FILE=$(MODULES_FILE) \
		GEN_WAVES=True \
		GEN_COVERAGE=True \
		SPECIFIC_COMPILE_ARGS=+incdir+$(REPO_ROOT)+$(RX_TEST_DIR)/tests

uart_rx_test: compile

test: compile
	./$(EXECUTABLE) \
		-cm line+cond+tgl+fsm+branch+assert \
		$(SIM_ARGS)

coverage: test coverage_reports

coverage_reports:
	$(MAKE) -f $(SV_UTILS)/run_vcs.mk coverage_reports

clean:
	$(MAKE) -f $(SV_UTILS)/run_vcs.mk clean