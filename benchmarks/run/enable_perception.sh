#!/bin/bash
set -e

# Step 1: Load shared env (perf path, conda init, ROS setup)
source ./env.sh

# Step 2: Activate conda environment
eval "$(conda shell.bash hook)"
conda activate airship_perception

# Step 3: Set correct PYTHONPATH for conda environment
export PYTHONPATH=$CONDA_PREFIX/lib/python3.10/site-packages:$PYTHONPATH
export PYTHONPATH=/home/airsbot2/airship/src/airship/airship_perception/lib/GroundingDINO:$PYTHONPATH

# Step 4: Launch node
LOG_DIR=log/perception
mkdir -p $LOG_DIR

ros2 launch airship_perception run_airship_perception_node.launch.py &
TARGET_PID=$!
sleep 5

# Step 5: Start perf tracking
N=5
echo "Starting perf stat tracking for process $TARGET_PID every ${N} seconds ..."
while kill -0 $TARGET_PID 2>/dev/null; do
    sudo $PERF_BIN stat \
        -e cycles,instructions,cache-references,cache-misses,branches,branch-misses,cpu-clock,task-clock,page-faults,context-switches,cpu-migrations \
        -p $TARGET_PID \
        -o $LOG_DIR/perf_stat_perception_$(date +%Y%m%d_%H%M%S).log sleep $N
    sleep 0.1
done

echo "Sampling finished. Logs are saved in $LOG_DIR."
