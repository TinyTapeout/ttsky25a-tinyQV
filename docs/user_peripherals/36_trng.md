<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

# True Random Number Generator RO Based - 20RO7_FF

Author: Pedro Correia

Peripheral index: 36

## What it does

This Peripheral implements a True Random Number Generator (TRNG) based on jitter noise from Ring Oscilators (ROs).
The choosen architecture was sampling flip-flop with 20 ROs in parallel, each with 7 inverters.
TRNG based on best performer from https://ieeexplore.ieee.org/document/10209326 , for more info regarding the article contact me.


## Register map

The Peripheral Constantly streams data from the generator, to retrieve it just access the output register for the pheripheral and extract the data.

| Address | Name  | Access | Description                                                         |
|---------|-------|--------|---------------------------------------------------------------------|
| 0x00    | out   | R      | 8bit True random number                                             |


## How to test

consequent reads to the register, should yield diferent results.
Use NIST SP800-22R, to test data.

## External hardware

No external hardware required.
