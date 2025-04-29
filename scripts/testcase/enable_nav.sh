#!/bin/bash
source ~/airship/install/local_setup.bash
ros2 launch airship_localization airship_localization_gt_sim.launch.py &
ros2 launch airship_navigation airship_navigation_sim.launch.py

