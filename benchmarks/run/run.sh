#!/bin/bash

PERF_BIN=~/perf

if tmux has-session -t benchmark 2>/dev/null; then
    tmux kill-session -t benchmark
fi

mkdir -p log

# Start tegrastats to collect CPU/GPU/memory data in background
tegrastats --logfile log/tegrastats.log &
TEGRA_PID=$!

# Automatically open jtop interactive interface in new tmux session (kill existing one first if exists)
if tmux has-session -t jtop 2>/dev/null; then
    tmux kill-session -t jtop
fi
tmux new-session -d -s jtop 'jtop'

# Automatically stop collection and analyze performance logs when script exits
trap "kill $TEGRA_PID; python3 analyze_tegrastats.py" EXIT


tmux new-session -d -s benchmark
tmux split-window -v -t benchmark:0.0
tmux split-window -h -t benchmark:0.0
tmux split-window -v -t benchmark:0.0
tmux split-window -v -t benchmark:0.2

tmux send-keys -t benchmark:0.0 "cd ~/airship/src/airship/benchmarks/run && bash enable_nav.sh" C-m
tmux send-keys -t benchmark:0.1 "cd ~/airship/src/airship/benchmarks/run && bash enable_perception.sh" C-m
tmux send-keys -t benchmark:0.2 "cd ~/airship/src/airship/benchmarks/run && bash enable_grasp.sh" C-m
tmux send-keys -t benchmark:0.4 "cd ~/airship/src/airship/benchmarks/run && bash send_inst.sh" C-m
tmux send-keys -t benchmark:0.3 "cd ~/airship/src/airship/benchmarks/run && bash enable_planner.sh" C-m

# Wait for all node processes to start (adjust time as needed)
sleep 10

# Get all ros2 launch related process PIDs
PIDS=$(pgrep -d, -f "ros2 launch")

echo "Collecting performance data for the following processes: $PIDS"
mkdir -p log

# Run perf statistics in background, output to log/perf_stat.log
# "$PERF_BIN" stat -I 1000 -e cycles,instructions,cache-references,cache-misses,branches,branch-misses,cpu-clock,task-clock,page-faults,context-switches,cpu-migrations -p $PIDS > log/perf_stat.log 2>&1 &
# PERF_PID=$!

# Automatically stop perf when exiting
# trap "kill $TEGRA_PID 2>/dev/null; kill $PERF_PID 2>/dev/null; python3 analyze_tegrastats.py" EXIT

tmux select-pane -t benchmark:0.4
tmux attach-session -t benchmark

# Background monitoring of tmux session, kill all ros2 launch and perf stat sampling processes when detach
(
    SESSION_NAME="benchmark"
    while true; do
        sleep 1
        # Check if session exists and has no attached clients
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            # Check if there are clients connected to this session
            if ! tmux list-clients -t "$SESSION_NAME" 2>/dev/null | grep -q .; then
                echo "[Monitor] tmux session $SESSION_NAME has been detached, automatically killing all ros2 launch and perf stat sampling processes..."
                # kill ros2 launch
                pkill -f "ros2 launch"
                # kill perf stat
                pkill -f "perf stat"
                # kill tegrastats
                pkill -f "tegrastats"
                # Exit monitoring loop
                break
            fi
        else
            # Session doesn't exist, also kill processes
            echo "[Monitor] tmux session $SESSION_NAME doesn't exist, automatically killing all ros2 launch and perf stat sampling processes..."
            pkill -f "ros2 launch"
            pkill -f "perf stat"
            pkill -f "tegrastats"
            break
        fi
    done
) &