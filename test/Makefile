USER_PERIPHERALS = \
	edge_counter \
	pwm_sk \
	uart \
	spi \
	game_pmod \
	matt_encoder.test \
	ledstrip.test \
	vgaconsole.test \
	impostor_ws2812b.test \
	matt_pwm.test \
    test_spike  \
	fpu.test \
	baby_vga.test \
	prism.test \
	pwl_synth.test \
	wdt.test \
	RV2A03.test \
	tqvp_laurie_dwarf_line_table_accelerator.test \
	pulse_transmitter.test \
	crc32 \
	prng.test \
	hardware_utf8.test \
	waveforms.test \
	pdm.test \
	ubcd.test \
	analog_toolkit.test \

.PHONY: all core prog peri $(USER_PERIPHERALS)

%-results.xml:
	@make -f test_$*.mk clean
	make -f test_$*.mk
	@mv results.xml $@
	@mv sim_build/rtl/tb*.fst $*-rtl.fst || true
	@mv sim_build/gl/tb*.fst $*-gl.fst || true

peri-%.xml:
	@make -f test_basic.mk clean
	MODULE=user_peripherals.$* make -f test_basic.mk || true
	@if [ ! -f results.xml ]; then echo '<failure message="$* failed (crashed)" />' > results.xml; fi
	@mv results.xml $@
	@mv sim_build/rtl/tb.fst $*-rtl.fst || true
	@mv sim_build/gl/tb.fst $*-gl.fst || true

all: clean basic-results.xml prog-results.xml $(USER_PERIPHERALS:%=peri-%.xml)
	@cat *results.xml peri-*.xml > results.xml

core: clean basic-results.xml
	@cat *results.xml > results.xml

prog: clean prog-results.xml
	@cat *results.xml > results.xml

peri: clean $(USER_PERIPHERALS:%=peri-%.xml)
	@cat peri-*.xml > results.xml

$(USER_PERIPHERALS): %: peri-%.xml

clean:
	rm *results.xml peri-*.xml *.fst sim_build/rtl/tb.fst sim_build/gl/tb.fst || true
