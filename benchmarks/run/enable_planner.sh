#!/bin/bash

# Load environment shared config
source ./env.sh

# Step 1: Activate conda env
eval "$(conda shell.bash hook)"
conda activate airship_planner

# Step 2: Add correct Python site-packages to PYTHONPATH
export PYTHONPATH=$CONDA_PREFIX/lib/python3.10/site-packages:$PYTHONPATH

# Step 3: Load ROS base installation (this is critical!)
source /opt/ros/humble/setup.bash

# Step 4: Launch ROS node
LOG_DIR=log/planner
mkdir -p $LOG_DIR

ros2 launch airship_planner airship_planner_launch.py &
TARGET_PID=$!
sleep 5

# Step 5: Start perf tracking
N=5
echo "Starting perf stat tracking for process $TARGET_PID every ${N} seconds ..."
while kill -0 $TARGET_PID 2>/dev/null; do
    sudo $PERF_BIN stat -e cycles,instructions,cache-references,cache-misses,branches,branch-misses,cpu-clock,task-clock,page-faults,context-switches,cpu-migrations -p $TARGET_PID -o $LOG_DIR/perf_stat_planner_$(date +%Y%m%d_%H%M%S).log sleep $N
    sleep 0.1
done

echo "Sampling finished. Logs are saved in $LOG_DIR."
