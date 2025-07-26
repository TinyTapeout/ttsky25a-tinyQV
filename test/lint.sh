#!/bin/bash

pushd ../src
~/oss-cad-suite/bin/verilator --lint-only --timing -DSIM -Wall -Wno-DECLFILENAME -Wno-MULTITOP project.v peri*.v tinyQV/cpu/*.v tinyQV/peri/uart/uart_tx.v user_peripherals/*/*.v user_peripherals/*.v
popd
