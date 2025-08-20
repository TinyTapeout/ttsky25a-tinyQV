<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

The peripheral index is the number TinyQV will use to select your peripheral.  You will pick a free
slot when raising the pull request against the main TinyQV repository, and can fill this in then.  You
also need to set this value as the PERIPHERAL_NUM in your test script.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

# PWL Synth

Author: Toivo Henningsson

Peripheral index: 33

## What it does

PWL Synth is a 4 channel synth with a superset of classic chiptune waveforms:
- Each channel has 3 parameters that can be used to morph the waveform between square, pulse, triangle, sawtooth-like, and other waveforms
	- Sweep rates for each parameter allows morphing in real time to bring out the synth character
- Volume per channel, with sweep rate and target value
- One channel can be switched to a noise waveform
- Detune function per channel: Plays two copies of the same waveform at slightly different pitches, for added depth.

### Note frequencies

The frequency of each channel is described by

	f_period[12:0] = {period_exp[2:0], mantissa[9:0]}

The period in samples is given by

	period = 2^(period_exp - 2) * (1024 + mantissa)

and goes from 256 to 65504 samples (only the top 8 bits of `mantissa` are used for the highest octave `period_exp = 0` and only the top 9 bits for the second to highest octave `period_exp = 1`).
`f_period` uses a quasi-logarithmic scale (it can also be seen as a floating point number) where `period_exp` sets the octave, and the period varies linearly with `mantissa` within each octave.

The actual note frequency is then given by

	f = fs / (2^period_exp * (1024 + mantissa))

where the sampling frequency `fs` is

	fs = f_clk / 64  # usually = 1 MHz

With a sampling frequency of `fs = 1 MHz`, the note frequency range is roughly 15 - 3900 Hz.

In noise mode (enabled when `lfsr_en = 1` for the channel), `f_period` controls the sampling period of the noise instead:

	noise_period = 8 * 2^period_exp * (1024 + mantissa)/1024

which gives a noise sampling period of 8 to 2047 samples.
With `fs = 1 MHz`, the range for the sampling frequency of the noise mode goes from 488 Hz to 125 kHz.

### Waveform shaping

The waveform for each channel is calculated in a number of steps. The input is `0 <= phase < 1` which varies in a rising sawtooth pattern with the given period. The calculations are

	y = phase
	# y = sawtooth wave, 0 <= y <= 1

	# Detune. The waveform is calculated once with detune_sign = +1,
	# and once with detune_sign = -1, and added.
	# detune_exp <= 8-period_exp should sound fine, higher values might start to sound off due to too much detuning.
	if detune_exp != 0:
		y = wrap(y + detune_sign * sample_counter * 2^(detune_exp - 25))
	# y = sawtooth wave, 0 <= y <= 1

	# Phase to triangle wave
	y = y * 2
	part = 0  # keeps track on if we are on the rising edge (0) or falling edge (1) of the waveform
	if y >= 1:
		y = 2 - y
		part = 1
	# y = triangle wave, 0 <= y <= 1
	y = y * 2 - 1
	# y = triangle wave, -1 <= y <= 1

	# Pulse width modulation offset
	y = min(y + pwm_offset_r, 1)  # 0 <= pwm_offset_r < 1
	# y = triangle wave with DC offset, clamped to y <= 1

	# Increase slope, clamp to -1 <= y <= 1. The slope value used depends on if we are on the rising or falling edge of the waveform.
	# Approximate formula, the actual waveform for fractional slopes is a little different.
	y = saturate(2^slope_r[part] * y)

	# Volume clamp
	y = clamp(y, -amp_r, amp_r)
	# y = output waveform, -1 <= y <= 1

where the output waveform is expressed in the range `-1 <= y <= 1`, `pwm_offset_r` and `slope_r` are in the range `0 - 1`, and `slope_r` is in the range `0 - 16`.
These rescaled values can be calculated from the integer values stored in the registers according to

	pwm_offset_r = pwm_offset / 256  # range 0 - almost 1
	slope_r[i]   = slope[i] / 16     # range 0 - almost 16
	amp_r        = amp / 64          # range 0 - almost 1

The steps can be summarized as

- The input is a sawtooth waveform with the the given period
- Detuning is applied to pull the frequency a bit higher or lower
- The sawtooth wave is converted to a triangle wave, but
	- `part` keeps track of if we are on the rising edge (0) or falling edge (1) of the waveform
- `pwm_offset` is added to the triangle wave (with saturation) to push the rising and falling edge apart
- The slope is increased, basically multiplying the value with `2^slope_r[part]` and saturating
- Finally, the waveform is clamped to a max amplitude of `amp`, to control the volume

Uses for the parameters:

- `pwm_offset `can be used to vary the pulse width.
- `slope` varies the steepness of the edges
	- A higher slope gives a sharper sound with more overtones
	- The effect of lowering the slope is similar to applying a lowpass filter
	- `pwm_offset = 0` and same slope for both edges gives a square-wave like sound (only odd harmonics)
	- Minium slope for one edge and higher for the other edge approximates a sawtooth wave (more like clamped sawtooth wave, but they sound quite similar)
- `amp` is used to control the volume

The simple clamping behavior for `amp` avoids rounding artifacts, but also causes the waveform to change as the amplitude is reduced. When `amp` becomes smaller, the slope has less and less influence on the waveform (the slope compared to the amplitude increases), while `pwm_offset_r` maintains its effect.

The detuning is approximately

	detune = +- (1.69 cents) * 2^(detune_exp - octave)

where `octave = 7 - period_exp`.

### Sweep values

Sweep values can be used to make different parameters increase or decrease at a steady rate.
The basic setup is the same for all parameters, but the details are a bit different.

All sweep values have a 4 bit rate. The swept parameter is increased or decreased by one step at a frequency given by

| `rate` | Frequency of parameter update |
|--------|-------------------------------|
| 0      | Never (off)                   |
| 1      | Maximum rate                  |
| 2 - 15 | Once every `2*2^rate` samples |

The maximum rate for period (`f_period`) parameter is once every 8 samples; the maximum rate for amplitude, slopes, and PWM offset parameters is once every 32 samples.
The maxiumem rate must be specified using `rate=1`. For `f_period`, the next lower rate (half as often) is given by `rate=3`, while for the other parameters, it is given by `rate=5`.

Most sweep parameters specify a sign: `0 = increase, 1 = decrease`. The parameter will sweep until the sweep is stopped by changing the sweep value, or the parameter is at its extreme value.
The amplitude sweep parameter includes a 3 bit `target` value instead, where the 6 bit target amplitude is given by `{target, target} = 9*target`.
The amplitude will sweep up or down until it reaches the target amplitude and then stop sweeping.

The rising and falling slope values `slope[0]` and `slope[1]` share a common sweep value, with an additional 2 bit `dir` value that specifies how to apply the sweep:

| `dir` | Behavior                                                                   |
|-------|----------------------------------------------------------------------------|
| 2'b11 | Sweep both slopes                                                          |
| 2'b01 | Sweep only `slope[0]`                                                      |
| 2'b10 | Sweep only `slope[1]`                                                      |
| 2'b00 | Sweep both slopes in opposite directions, flipping the sign for `slope[1]` |

#### Using the sweep values
It may be desired to sweep parameters at a rate that is somewhere in between the available rates. Unfortunately, there was no space for more bits to use for sweep values.
Some possible ways to handle such cases are:

- Update the sweep values at a regular rate, like 60 Hz.
	- Always choose the rate that would bring the parameter closest to the desired target value at the next update, possibly without overshooting the target.
	- The current values of the swept parameters can be read back to help calculate the desired sweep value.
- Given an initial value and a desired final value at a final time, choose two sweep rates and calculate exactly when to switch between them in order to arrive at the desired final value.
	- Use a timer interrupt to trigger the change in sweep rate.

The slowest sweep rate is once every 2^16 cycles. With a sample rate of `fs = 1 MHz`, this results in an update rate of rougly 15 times per second.
If you need a slower sweep rate, update the parameters directly instead.

## Register map

**NOTE: Additional bit fields and registers may be added. Unused bits should be set to zero for forward compatibility.**

| Address | Name          | Access | Description                                                 |
|---------|---------------|--------|-------------------------------------------------------------|
| 0x00    | f_period[0]   | RW     | Period for channel 0, 13 bits                               |
| 0x02    | amp[0]        | RW     | Amplitude for channel 0, 6 bits                             |
| 0x04    | slope[0][0]   | RW     | Rising slope for channel 0, 8 bits                          |
| 0x06    | slope[1][0]   | RW     | Falling slope for channel 0, 8 bits                         |
| 0x08    | pwm_offset[0] | RW     | PWM offset for channel 0, 8 bits                            |
| 0x0a    | mode[0]       | RW     | Mode bits for channel 0, 4 bits                             |
| 0x0c    | sweep_pa[0]   | W      | Period and amplitude sweep for channel 0                    |
| 0x0e    | sweep_ws[0]   | W      | PWM offset and slope sweep for channel 0                    |
| 0x10    | f_period[1]   | RW     | Period for channel 1, 13 bits                               |
| 0x12    | amp[1]        | RW     | Amplitude for channel 1, 6 bits                             |
| 0x14    | slope[0][1]   | RW     | Rising slope for channel 1, 8 bits                          |
| 0x16    | slope[1][1]   | RW     | Falling slope for channel 1, 8 bits                         |
| 0x18    | pwm_offset[1] | RW     | PWM offset for channel 1, 8 bits                            |
| 0x1a    | mode[1]       | RW     | Mode bits for channel 1, 4 bits                             |
| 0x1c    | sweep_pa[1]   | W      | Period and amplitude sweep for channel 1                    |
| 0x1e    | sweep_ws[1]   | W      | PWM offset and slope sweep for channel 1                    |
| 0x20    | f_period[2]   | RW     | Period for channel 2, 13 bits                               |
| 0x22    | amp[2]        | RW     | Amplitude for channel 2, 6 bits                             |
| 0x24    | slope[0][2]   | RW     | Rising slope for channel 2, 8 bits                          |
| 0x26    | slope[1][2]   | RW     | Falling slope for channel 2, 8 bits                         |
| 0x28    | pwm_offset[2] | RW     | PWM offset for channel 2, 8 bits                            |
| 0x2a    | mode[2]       | RW     | Mode bits for channel 2, 4 bits                             |
| 0x2c    | sweep_pa[2]   | W      | Period and amplitude sweep for channel 2                    |
| 0x2e    | sweep_ws[2]   | W      | PWM offset and slope sweep for channel 2                    |
| 0x30    | f_period[3]   | RW     | Period for channel 3, 13 bits                               |
| 0x32    | amp[3]        | RW     | Amplitude for channel 3, 6 bits                             |
| 0x34    | slope[0][3]   | RW     | Rising slope for channel 3, 8 bits                          |
| 0x36    | slope[1][3]   | RW     | Falling slope for channel 3, 8 bits                         |
| 0x38    | pwm_offset[3] | RW     | PWM offset for channel 3, 8 bits                            |
| 0x3a    | mode[3]       | RW     | Mode bits for channel 3, 4 bits                             |
| 0x3c    | sweep_pa[3]   | W      | Period and amplitude sweep for channel 3                    |
| 0x3e    | sweep_ws[3]   | W      | PWM offset and slope sweep for channel 3                    |

All registers must be written with 16 bit writes at the given addresses, and have zero intial value.

The layouts of the mode and sweep registers are

|      |       3 |        2:0 |
|------|---------|------------|
| mode | lfsr_en | detune_exp |

|          |          12 |         11:8 | 7 |         6:4 |       3:0 |
|----------|-------------|--------------|---|-------------|-----------|
| sweep_pa |period: sign | period: rate | X | amp: target | amp: rate |

|          |              12 |             11:8 | 7 |        6:5 |           4 |         3:0 |
|----------|-----------------|------------------|---|------------|-------------|-------------|
| sweep_ws |pwm_offset: sign | pwm_offset: rate | X | slope: dir | slope: sign | slope: rate |

## IO pins

There is a single output signal `pwm_out`, which is a PWM signal representing the synth's output (pulse frequency = `fs`). It is connected to all the output pins `uo_out[7:0]`. The input pins are not used.

## How to test

All registers start at initial value 0, which means that the volume is zero and detuning is off. The synth always plays, and a sound will be output as soon as the volume of a waveform is increased from zero.

To make a sound, the amplitude has to be turned up. Start by setting it to 63 for the channels that you want to play.

The following mantissas make up an equal tempered scale:

	C    C#   D    D#   E    F    F#   G    G#   A    A#  B
	909, 801, 698, 601, 510, 424, 343, 266, 194, 125, 61, 0

Use `period_exp = 7 - octave`.

Here is a simple melody that you can try by writing these values in sequence to `f_period` of one channel: (make sure to set its `amp` to 63 first)

	f_period = 4096
	f_period = 3415
	f_period = 3133
	f_period = 3072

You can use `detune_exp` = 5 or 4 with these notes for some detuning.

You can also play a chord by setting up four different periods for the channels, such as

	f_period[0] = 4794
	f_period[1] = 4362
	f_period[2] = 3981
	f_period[3] = 3673

You can turn them on one at a time (maybe ramping up the amplitude for each new note from 0 to 63 before starting to ramp up the next one).
`detune_exp` = 5 or 4 works fine in this case.

The default waveform has `pwm_offset_r = slope_r[0] = slope_r[1] = 0`, which makes a triangle wave.
Some example waveforms:

	# Triangle wave
	pwm_offset_r = 0, slope_r[0] = 0, slope_r[1] = 0

	# Square wave. Reduce both slope_r values equally to make it smoother (eventually turning into a triangle wave)
	pwm_offset_r = 0, slope_r[0] = 12, slope_r[1] = 12

	# Sawtooth-like wave. Reduce slope_r[1] to make it smoother (eventually turning into a triangle wave)
	pwm_offset_r = 0, slope_r[0] = 0, slope_r[1] = 12

	# 25% duty pulse wave. Reduce both slope_r values equally to make it smoother. Amplitude starts to drop when slope_r < 1
	pwm_offset_r = 0.5, slope_r[0] = 12, slope_r[1] = 12

	# 12.5% duty pulse wave. Reduce both slope_r values equally to make it smoother. Amplitude starts to drop when slope_r < 2
	pwm_offset_r = 0.75, slope_r[0] = 12, slope_r[1] = 12

	# Noise, use only on one channel at a time
	pwm_offset_r = 0, slope_r[0] = 0, slope_r[1] = 0, lfsr_en = 1

`pwm_offset_r` can be varied in real time for pulse width modulation. This can be used on any waveform, not just the pulse waves.
The slopes can be varied in real time to make edges harder or smoother. Increasing the smoothness over time has a similar effect to applying a low pass filter with falling cutoff frequency. Other effects can be achieved by increasing one slope while decreasing the other, such as starting to introduce some even harmonics into a smoothed square wave.

## External hardware

This project needs something that can convert the PWM output into an audio signal, such as [Mike's audio Pmod](https://github.com/MichaelBell/tt-audio-pmod). Make sure to configure the system to output the synth's `pwm_out` signal on the appropriate pin (`uo_out`[7] for Mike's audio Pmod).
