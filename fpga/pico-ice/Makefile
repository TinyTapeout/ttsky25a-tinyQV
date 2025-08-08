# Project setup
PROJ      = tinyqv

# TinyQV program to run - the $PROG.bin file must be copied into the micropython sub-directory.
PROG ?= hello

# Files
FILES = pico_ice.v peripherals.v ../../src/tinyQV/cpu/*.v ../../src/tinyQV/peri/uart/*.v ../../src/peri_byte_example.v ../../src/peri_full_example.v ../../src/peri_full_empty.v ../../src/peri_byte_empty.v ../../src/user_peripherals/*.v ../../src/user_peripherals/*.sv ../../src/user_peripherals/*/*.v ../../src/user_peripherals/*/*.sv

.PHONY: clean burn run

$(PROJ).bin: $(FILES)
	# Lint
	#verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-MULTITOP $(FILES)

	# synthesize using Yosys
	yosys -p "read -sv $(FILES) ; synth_ice40 -abc9 -device u -top tinyQV_top -json $(PROJ).json" -DICE40 -DPURE_RTL -DSYNTH_FPGA  > yosys.log
	@grep Warn yosys.log || true
	@grep Error yosys.log || true
	@grep "   Number of cells" yosys.log
	@grep "     SB_DFF" yosys.log | awk '{sum+=$$2;}END{printf("     SB_DFF* %25d\n", sum);}'
	@grep "     SB_LUT" yosys.log
	@echo

	# Place and route using nextpnr
	./nextpnr.sh -r --up5k --json $(PROJ).json --package sg48 --asc $(PROJ).asc --opt-timing --pcf pico_ice.pcf
	@grep Warn nextpnr.log || true
	@grep Error nextpnr.log || true
	@grep "Max frequency.*clk" nextpnr.log | tail -1
	@echo

	# Convert to bitstream using IcePack
	icepack $(PROJ).asc $(PROJ).bin

stats:
	@grep Warn yosys.log | grep -v tri-state || true
	@grep Error yosys.log || true
	@grep Warn nextpnr.log || true
	@grep Error nextpnr.log || true
	@grep "Max frequency.*clk" nextpnr.log | tail -1
	@echo "| Item | Count |"
	@echo "| ---- | ----- |"
	@grep "   Number of cells" yosys.log | awk '{printf("| Cells | %s |\n", $$4);}'
	@grep "     SB_DFF" yosys.log | awk '{sum+=$$2;}END{printf("| SB_DFF* | %d |\n", sum);}'
	@grep "     SB_LUT" yosys.log | awk '{printf("| %s | %s |\n", $$1, $$2);}'
	@grep "     ICESTORM_LC" nextpnr.log | awk '{gsub(/\//, "", $$3);printf("| ICE40 LCs | %s |\n", $$3);}'

burn: $(PROJ).bin
	mpremote mount . + run micropython/fpga_flash_prog.py

run:
	mpremote mount micropython + exec "import run_tinyqv ; run_tinyqv.execute('$(PROG).bin')"

reset:
	mpremote mount micropython + exec "import run_tinyqv ; run_tinyqv.run(query=False, stop=False)"

clean:
	rm $(PROJ).asc $(PROJ).bin $(PROJ).json
