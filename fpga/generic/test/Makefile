# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
WAVES=1
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/..
PROJECT_SOURCES = top.v peripherals.v sim_qspi.v bram.v ../../src/tinyQV/cpu/*.v ../../src/tinyQV/peri/uart/*.v ../../src/peri_byte_example.v ../../src/peri_full_example.v ../../src/peri_full_empty.v ../../src/peri_byte_empty.v ../../src/user_peripherals/*.v ../../src/user_peripherals/*.sv ../../src/user_peripherals/*/*.v ../../src/user_peripherals/*/*.sv

PROG ?= ledstrip

# RTL simulation:
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
COMPILE_ARGS 		+= -I$(SRC_DIR)
COMPILE_ARGS 		+= -I$(addprefix $(SRC_DIR)/,../../src/user_peripherals/pwl_synth)
COMPILE_ARGS 		+= -DPROG_FILE=\"../$(PROG).hex\"

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v 
TOPLEVEL = tb

# MODULE is the basename of the Python test file
MODULE = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
