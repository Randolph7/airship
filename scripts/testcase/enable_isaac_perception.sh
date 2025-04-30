#!/bin/bash
source ~/miniconda3/etc/profile.d/conda.sh
source ~/airship/install/local_setup.bash
conda activate airship_perception
ros2 launch airship_perception run_airship_perception_node.launch.py

