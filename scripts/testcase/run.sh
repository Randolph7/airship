#!/bin/bash

tmux new-session -d -s benchmark
tmux split-window -v -t benchmark:0.0
tmux split-window -h -t benchmark:0.0
tmux split-window -v -t benchmark:0.0
tmux split-window -v -t benchmark:0.2

tmux send-keys -t benchmark:0.0 "cd ~/benchmark && bash enable_nav.sh" C-m

tmux send-keys -t benchmark:0.1 "cd ~/benchmark && bash enable_perception.sh" C-m

tmux send-keys -t benchmark:0.2 "cd ~/benchmark && bash enable_grasp.sh" C-m

tmux send-keys -t benchmark:0.4 "cd ~/benchmark && bash send_inst.sh" C-m

tmux send-keys -t benchmark:0.3 "cd ~/benchmark && bash enable_planner.sh" C-m

tmux select-pane -t benchmark:0.4


tmux attach-session -t benchmark


