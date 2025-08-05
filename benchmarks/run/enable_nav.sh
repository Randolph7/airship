#!/bin/bash
source ./env.sh

LOG_DIR=log
mkdir -p $LOG_DIR

# 启动 localization
ros2 launch airship_localization airship_localization_gt_sim.launch.py &
LOC_PID=$!
sleep 5

# 检查 localization 进程是否还在
if ! kill -0 $LOC_PID 2>/dev/null; then
  echo "localization 启动失败或已退出，跳过采样。"
else
  N=5  # 采样间隔秒数
  echo "开始每${N}秒 perf stat 跟踪进程 $LOC_PID ..."
  (
      while kill -0 $LOC_PID 2>/dev/null; do
          sudo $PERF_BIN stat -e cycles,instructions,cache-references,cache-misses,branches,branch-misses,cpu-clock,task-clock,page-faults,context-switches,cpu-migrations -p $LOC_PID -o $LOG_DIR/perf_stat_localization_$(date +%Y%m%d_%H%M%S).log sleep $N
          sleep 0.1
      done
  ) &
fi

# 启动 navigation
ros2 launch airship_navigation airship_navigation_sim.launch.py &
NAV_PID=$!
sleep 5

# 检查 navigation 进程是否还在
if ! kill -0 $NAV_PID 2>/dev/null; then
  echo "navigation 启动失败或已退出，跳过采样。"
else
  echo "开始每${N}秒 perf stat 跟踪进程 $NAV_PID ..."
  (
      while kill -0 $NAV_PID 2>/dev/null; do
          sudo $PERF_BIN stat -e cycles,instructions,cache-references,cache-misses,branches,branch-misses,cpu-clock,task-clock,page-faults,context-switches,cpu-migrations -p $NAV_PID -o $LOG_DIR/perf_stat_navigation_$(date +%Y%m%d_%H%M%S).log sleep $N
          sleep 0.1
      done
  ) &
fi

echo "采样结束。日志保存在 $LOG_DIR 下。"
