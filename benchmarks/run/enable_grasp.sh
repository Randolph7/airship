#!/bin/bash
PERF_BIN=~/perf
source ~/miniconda3/etc/profile.d/conda.sh
source ~/airship/install/local_setup.bash
conda activate airship_grasp

LOG_DIR=log
mkdir -p $LOG_DIR

# 启动 ros2 launch 并获取其PID
ros2 launch airship_grasp grasp_sim.launch.py use_isaac_sim:=true &
TARGET_PID=$!
sleep 5  # 等待进程和线程全部启动

echo "开始 perf record 跟踪进程 $TARGET_PID 的所有线程..."
sudo $PERF_BIN record -g -p $TARGET_PID

echo "采样结束。可用如下命令分析："
echo "  sudo $PERF_BIN report"
