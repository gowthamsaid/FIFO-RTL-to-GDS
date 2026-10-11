export DESIGN_NAME = fifo_sync
export DESIGN_NICKNAME = fifo_32x32
export PLATFORM = nangate45

export VERILOG_FILES = $(HOME)/projects/fifo-rtl-to-gds/rtl/fifo_sync.v
export SDC_FILE = $(DESIGN_HOME)/$(PLATFORM)/fifo_8x16/constraint.sdc

export VERILOG_TOP_PARAMS = DATA_WIDTH 32 DEPTH 32
export CORE_UTILIZATION = 40
export PLACE_DENSITY = 0.60
