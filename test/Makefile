USER_PERIPHERAL_2 = uart
USER_PERIPHERAL_3 = game_pmod
USER_PERIPHERAL_4 = npu.test
USER_PERIPHERAL_5 = baby_vga.test
USER_PERIPHERAL_6 = wdt.test
USER_PERIPHERAL_7 = CAN_test
USER_PERIPHERAL_8 = prism.test
USER_PERIPHERAL_9 = vga_gfx.test
USER_PERIPHERAL_10 = pdm.test
USER_PERIPHERAL_11 = pulse_transmitter.test
USER_PERIPHERAL_12 =
USER_PERIPHERAL_13 = vgaconsole.test
USER_PERIPHERAL_14 =
USER_PERIPHERAL_15 = tiny-tone.mkTinyTone_Peripheral
USER_PERIPHERAL_16 = matt_encoder.test
USER_PERIPHERAL_17 = edge_counter
USER_PERIPHERAL_18 = ledstrip.test
USER_PERIPHERAL_19 = impostor_ws2812b.test
USER_PERIPHERAL_20 = pwm_sk
USER_PERIPHERAL_21 = matt_pwm.test
USER_PERIPHERAL_22 = test_spike
USER_PERIPHERAL_23 = ubcd.test
USER_PERIPHERAL_24 = hardware_utf8.test
USER_PERIPHERAL_25 = waveforms.test
USER_PERIPHERAL_26 = analog_toolkit.test
USER_PERIPHERAL_27 = crc32
USER_PERIPHERAL_28 = vga_tester.test
USER_PERIPHERAL_29 = rsa.test
USER_PERIPHERAL_30 = spi
USER_PERIPHERAL_31 = hamming_7_4.test
USER_PERIPHERAL_32 = fpu.test
USER_PERIPHERAL_33 = pwl_synth.test
USER_PERIPHERAL_34 = tqvp_laurie_dwarf_line_table_accelerator.test
USER_PERIPHERAL_35 = prng.test
USER_PERIPHERAL_36 = trng.test
USER_PERIPHERAL_37 = intercal_alu.test
USER_PERIPHERAL_38 = CORDIC.test_trigonometric_simple \
					 CORDIC.test_linear_simple \
					 CORDIC.test_hyperbolic_vectoring_square_vis \
					 CORDIC.test_hyperbolic_vectoring_simple \
					 CORDIC.test_hyperbolic_rotating_sweep_and_vis \
					 CORDIC.test_hyperbolic_rotating_simple \
					 CORDIC.test_circular_rotating_sweep_and_vis
USER_PERIPHERAL_39 = affinex.test

expand_tests = $(foreach num,$(1),$(USER_PERIPHERAL_$(num)))
PERI_NUMBERS = $(shell seq 2 39)
ALL_TESTS = $(call expand_tests,$(PERI_NUMBERS))

.PHONY: clean core prog peri_test_% peri_num_% $(ALL_TESTS)

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

$(ALL_TESTS): %: peri-%.xml

clean:
	rm *results.xml peri-*.xml *.fst sim_build/rtl/tb.fst sim_build/gl/tb.fst || true

core: clean basic-results.xml
	@cat *results.xml > results.xml

prog: clean prog-results.xml
	@cat *results.xml > results.xml

.SECONDEXPANSION:
peri_num_%: clean $$(call expand_tests,%)
	@if [ "$(USER_PERIPHERAL_$*)" != "" ]; then cat peri-*.xml; else echo '<testsuites name="results" />'; fi > results.xml
