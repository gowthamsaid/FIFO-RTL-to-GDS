# Paired research configuration: 8x16 decoder
# Use only within a matched ORFS checkout; READPATH_REPO_ROOT set by run_orfs_stage.sh
ifeq ($(strip $(READPATH_REPO_ROOT)),)
$(error READPATH_REPO_ROOT is missing. Run research/readpath/scripts/run_orfs_stage.sh)
endif

export DESIGN_NAME = fifo_sync_onehot
export DESIGN_NICKNAME = fifo_readpath_8x16_decoder
export PLATFORM = nangate45

export VERILOG_FILES = $(READPATH_REPO_ROOT)/research/readpath/rtl/fifo_sync_onehot.v
export SDC_FILE = $(READPATH_REPO_ROOT)/research/readpath/orfs/constraint.sdc

export VERILOG_TOP_PARAMS = DATA_WIDTH 8 DEPTH 16
export CORE_UTILIZATION = 40
export PLACE_DENSITY = 0.60
