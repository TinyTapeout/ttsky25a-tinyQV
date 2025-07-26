<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## What it does

Reads up to 4 rotary (incremental) encoder: https://en.wikipedia.org/wiki/Incremental_encoder

The a and b signals are first debounced at a configurable frequency.

The encoder counts from 0 to 255.

## Register map

| Address      | Name  | Access | Description                                                         |
|--------------|-------|--------|----------------------------------------------------------------------------------|
| 0x8000400    | ENC0  | R      | Value of Encoder 0                                                               |
| 0x8000401    | ENC1  | R      | Value of Encoder 1                                                               |
| 0x8000402    | ENC2  | R      | Value of Encoder 2                                                               |
| 0x8000403    | ENC3  | R      | Value of Encoder 3                                                               |
| 0x8000404    | DPER  | R/W    | Debounce period. Value is left shifted by 6. Default 128 (8192) clock cycles |

## How to test

Connect up to 4 incremental encoders to the input port (see pin mapping).

Use the test firmware to read the value of the encoder and print it out.

Default debounce period should be fine at 64MHz, but might need tuning if you have noisy encoders or run at a different frequency.

## External hardware

Rotary incremental encoders. Most encoder Pmod boards have pull-up / pull-down resistors. If you are
using a bare encoder, you will need to add your own pull-up / pull-down resistors.
