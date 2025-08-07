#!/bin/bash
source ./env.sh

LOG_DIR=log/navigation
mkdir -p $LOG_DIR

# Start localization
ros2 launch airship_localization airship_localization_gt_sim.launch.py &
LOC_PID=$!
sleep 5

# Check if localization process is still running
if ! kill -0 $LOC_PID 2>/dev/null; then
  echo "localization startup failed or exited, skipping sampling."
else
  N=5  # Sampling interval in seconds
  echo "Starting perf stat tracking for process $LOC_PID every ${N} seconds..."
  (
      while kill -0 $LOC_PID 2>/dev/null; do
          sudo $PERF_BIN stat -e cycles,instructions,cache-references,cache-misses,branches,branch-misses,cpu-clock,task-clock,page-faults,context-switches,cpu-migrations -p $LOC_PID -o $LOG_DIR/perf_stat_localization_$(date +%Y%m%d_%H%M%S).log sleep $N
          sleep 0.1
      done
  ) &
fi

# Start navigation
ros2 launch airship_navigation airship_navigation_sim.launch.py &
NAV_PID=$!
sleep 5

# Check if navigation process is still running
if ! kill -0 $NAV_PID 2>/dev/null; then
  echo "navigation startup failed or exited, skipping sampling."
else
  echo "Starting perf stat tracking for process $NAV_PID every ${N} seconds..."
  (
      while kill -0 $NAV_PID 2>/dev/null; do
          sudo $PERF_BIN stat -e cycles,instructions,cache-references,cache-misses,branches,branch-misses,cpu-clock,task-clock,page-faults,context-switches,cpu-migrations -p $NAV_PID -o $LOG_DIR/perf_stat_navigation_$(date +%Y%m%d_%H%M%S).log sleep $N
          sleep 0.1
      done
  ) &
fi

echo "Sampling completed. Logs saved in $LOG_DIR."
