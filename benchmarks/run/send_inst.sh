#!/bin/bash

source ~/airship/install/local_setup.bash  # 如果你用的是自定义 workspace

echo "Enter your instrucitons："
read -r MSG

if [ -z "$MSG" ]; then
  echo "❌ No input, please enter a message."
  exit 1
fi

echo "✅ Send: \"$MSG\""
ros2 service call /airship_planner/planner_server airship_interface/srv/AirshipInstruct "{msg: \"$MSG\"}"

