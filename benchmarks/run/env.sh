#!/bin/bash
# Unified environment variable configuration for benchmark scripts

# Path to perf binary
export PERF_BIN=~/perf

# Conda shell hook (for conda activate)
if [ -f ~/miniconda3/etc/profile.d/conda.sh ]; then
    source ~/miniconda3/etc/profile.d/conda.sh
fi

# ROS 2 system install
source /opt/ros/humble/setup.bash

# ROS 2 workspace overlay (if exists)
if [ -f ~/airship/install/local_setup.bash ]; then
    source ~/airship/install/local_setup.bash
fi
