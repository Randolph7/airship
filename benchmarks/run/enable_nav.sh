#!/bin/bash
PERF_BIN=~/perf
source ~/airship/install/local_setup.bash

LOG_DIR=log
mkdir -p $LOG_DIR

# 启动 localization
ros2 launch airship_localization airship_localization_gt_sim.launch.py &
LOC_PID=$!
sleep 5

# 跟踪 localization 进程
echo "开始 perf record 跟踪进程 $LOC_PID"
sudo $PERF_BIN record -g -p $LOC_PID -o $LOG_DIR/perf_localization.data &
PERF_LOC_PID=$!

# 启动 navigation
ros2 launch airship_navigation airship_navigation_sim.launch.py &
NAV_PID=$!
sleep 5

# 跟踪 navigation 进程
echo "开始 perf record 跟踪进程 $NAV_PID"
sudo $PERF_BIN record -g -p $NAV_PID -o $LOG_DIR/perf_navigation.data &
PERF_NAV_PID=$!

# 等待 perf 跟踪完成（可选）
wait $PERF_LOC_PID
wait $PERF_NAV_PID

echo "采样结束。你可以分别使用如下命令查看报告："
echo "  sudo $PERF_BIN report -i $LOG_DIR/perf_localization.data"
echo "  sudo $PERF_BIN report -i $LOG_DIR/perf_navigation.data"
