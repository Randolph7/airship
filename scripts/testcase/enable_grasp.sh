#!/bin/bash
source ~/miniconda3/etc/profile.d/conda.sh
source ~/airship/install/local_setup.bash
conda activate airship_grasp
ros2 launch airship_grasp grasp_sim.launch.py use_isaac_sim:=true

