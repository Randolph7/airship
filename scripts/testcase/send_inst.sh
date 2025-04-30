#!/bin/bash

source ~/airship/install/local_setup.bash 

# Input
echo "Enter your instrucitons:"
read -r MSG

# Check empty
if [ -z "$MSG" ]; then
  echo "❌ No input, please enter a message."
  exit 1
fi

# Call ROS 2 service
echo "✅ Send: \"$MSG\""
ros2 service call /airship_planner/planner_server airship_interface/srv/AirshipInstruct "{msg: \"$MSG\"}"


