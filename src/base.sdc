read_sdc $::env(SCRIPTS_DIR)/base.sdc

# Add duty cycle uncertainty - due to the high capacitance of the TT mux 
# we're pretty uncertain about the duty cycle
set_clock_uncertainty 2.5 -rise_from clk -fall_to clk
set_clock_uncertainty 2 -fall_from clk -rise_to clk

# Fix reset delay
set_input_delay 1.5 -clock [get_clocks $::env(CLOCK_PORT)] {rst_n}

# Longer delays for input IOs as we expect to drive them on clock falling edge
# Note "setup" is actually 1 clock cycle minus setup, so this requires a setup
# period of 35% of the clock cycle
set input_setup_delay_value [expr $::env(CLOCK_PERIOD) * 0.65]
set input_hold_delay_value [expr $::env(CLOCK_PERIOD) * 0.24]
set_input_delay -clock [get_clocks $::env(CLOCK_PORT)] -max $input_setup_delay_value {uio_in ui_in}
set_input_delay -clock [get_clocks $::env(CLOCK_PORT)] -min $input_hold_delay_value {uio_in ui_in}

# Longer output delay on bidi IOs to improve coherence
set output_setup_delay_value [expr $::env(CLOCK_PERIOD) * 0.65]
set output_hold_delay_value 1
set_output_delay -clock [get_clocks $::env(CLOCK_PORT)] -max $output_setup_delay_value {uio_out[7] uio_out[6] uio_out[5] uio_out[4] uio_out[2] uio_out[1] uio_out[0] uio_oe}
set_output_delay -clock [get_clocks $::env(CLOCK_PORT)] -min $output_hold_delay_value {uio_out uio_oe}

# Lower delay on SPI clock output because it can be driven at negedge for timing tweaking
set spi_clk_setup_delay_value [expr $::env(CLOCK_PERIOD) * 0.2]
set_output_delay -clock [get_clocks $::env(CLOCK_PORT)] -max $spi_clk_setup_delay_value {uio_out[3]}

# Delays on user outputs
set_output_delay -clock [get_clocks $::env(CLOCK_PORT)] -min 1 {uo_out}
set_output_delay -clock [get_clocks $::env(CLOCK_PORT)] -max 2 {uo_out}

# User peripheral SDC files
read_sdc src/user_peripherals/pwl_synth/pwl_synth.sdc
