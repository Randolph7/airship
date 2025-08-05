#!/bin/bash
# Unified environment variable configuration for benchmark scripts

# Path to perf binary
export PERF_BIN=~/perf

# Conda initialization (if needed)
if [ -f ~/miniconda3/etc/profile.d/conda.sh ]; then
    source ~/miniconda3/etc/profile.d/conda.sh
fi

# ROS2 workspace setup
if [ -f ~/airship/install/local_setup.bash ]; then
    source ~/airship/install/local_setup.bash
fi
