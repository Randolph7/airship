#!/bin/bash
set -e

# Step 1: Load conda first
eval "$(conda shell.bash hook)"
conda activate airship_perception

# Step 2: Set PYTHONPATH (确认 python 版本一致)
export PYTHONPATH=/home/airsbot2/miniconda3/envs/airship_perception/lib/python3.10/site-packages:$PYTHONPATH

# Step 3: Source ROS 2 & workspace 环境
source /opt/ros/humble/setup.bash
source ~/airship/install/setup.bash  # 确保这是你安装的 ROS 2 workspace

# Step 4: Launch
LOG_DIR=log
mkdir -p $LOG_DIR

ros2 launch airship_perception run_airship_perception_node.launch.py &
TARGET_PID=$!
sleep 5

N=5
echo "Starting perf stat tracking for process $TARGET_PID every ${N} seconds ..."
while kill -0 $TARGET_PID 2>/dev/null; do
    sudo $PERF_BIN stat -e cycles,instructions,cache-references,cache-misses,branches,branch-misses,cpu-clock,task-clock,page-faults,context-switches,cpu-migrations -p $TARGET_PID -o $LOG_DIR/perf_stat_$(date +%Y%m%d_%H%M%S).log sleep $N
    sleep 0.1
done

echo "Sampling finished. Logs are saved in $LOG_DIR."
