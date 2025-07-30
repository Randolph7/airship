#!/bin/bash
PERF_BIN=~/perf
source ~/miniconda3/etc/profile.d/conda.sh
source ~/airship/install/local_setup.bash
conda activate airship_planner

LOG_DIR=log
mkdir -p $LOG_DIR

ros2 launch airship_planner airship_planner_launch.py &
TARGET_PID=$!
sleep 5

echo "开始 perf record 跟踪进程 $TARGET_PID 的所有线程..."
sudo $PERF_BIN record -g -p $TARGET_PID

echo "采样结束。可用如下命令分析："
echo "  sudo $PERF_BIN report"
