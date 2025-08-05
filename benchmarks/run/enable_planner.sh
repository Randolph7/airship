#!/bin/bash
source ./env.sh

# Activate conda environment
conda activate airship_planner

LOG_DIR=log
mkdir -p $LOG_DIR

ros2 launch airship_planner airship_planner_launch.py &
TARGET_PID=$!
sleep 5

N=5  # Sampling interval in seconds
echo "Starting perf stat tracking for process $TARGET_PID every ${N} seconds ..."
while kill -0 $TARGET_PID 2>/dev/null; do
    sudo $PERF_BIN stat -e cycles,instructions,cache-references,cache-misses,branches,branch-misses,cpu-clock,task-clock,page-faults,context-switches,cpu-migrations -p $TARGET_PID -o $LOG_DIR/perf_stat_$(date +%Y%m%d_%H%M%S).log sleep $N
    sleep 0.1  # Prevent time overlap
done

echo "Sampling finished. Logs are saved in $LOG_DIR."
