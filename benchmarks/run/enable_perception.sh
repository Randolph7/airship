#!/bin/bash
PERF_BIN=~/perf
source ~/miniconda3/etc/profile.d/conda.sh
source ~/airship/install/local_setup.bash
conda activate airship_perception

LOG_DIR=log
mkdir -p $LOG_DIR

ros2 launch airship_perception run_airship_perception_node.launch.py &
TARGET_PID=$!
sleep 5

echo "开始 perf record 跟踪进程 $TARGET_PID"
sudo $PERF_BIN record -g -p $TARGET_PID

echo "采样结束。可用如下命令分析："
echo "  sudo $PERF_BIN report"
