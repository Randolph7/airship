# AIRSHIP Full Local Deployment Guide (for Jetson AGX Orin)

## System Requirements

- **Hardware**: Nvidia Jetson AGX Orin
- **Operating System**: JetPack 6.0 (based on Ubuntu 22.04), bundled with CUDA 12.2
- **Python**: Use Python 3.10 across all environments (use conda to manage environment-specific versions)

------

## Source Code Acquisition

Flash the device using NVIDIA's official tools, selecting both CUDA and Linux options.

> ⚠️ Important: The username must be set to:

```
airsbot2
```

Otherwise, some paths in AIRSHIP packages may not align, causing debugging issues.

After flashing, run:

```
sudo apt-get update
sudo apt-get upgrade
```

Create the main project folder:

```
mkdir ~/airship
```

Add the following to the end of your `.bashrc` and source it:

```
export DIR_AIRSHIP=$HOME/airship
source ~/.bashrc
```

Clone the source code:

```
cd ~/airship
mkdir src
cd src
git clone https://github.com/airs-cuhk/airship.git
```

------

## Installing ROS2 Humble

Run the installation script:

```
bash ~/airship/src/airship/scripts/software_setup/install_ros_humble.sh
```

Then source the environment and add it to `.bashrc`:

```
source /opt/ros/humble/setup.bash
echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc
```

> ⚠️ Tip: Installation errors are often caused by network issues. Carefully check the logs.

------

## Sensor Drivers Installation

Create a separate folder for sensor drivers:

```
mkdir ~/sensors
cd ~/sensors
```

### ZED Camera

```
# Download and install ZED SDK
wget https://download.stereolabs.com/zedsdk/4.1/l4t36.3/jetsons
chmod +x ZED_SDK_Tegra_L4T36.3_v4.1.4.zstd.run
./ZED_SDK_Tegra_L4T36.3_v4.1.4.zstd.run silent runtime_only skip_drivers

# ROS2 Wrapper
mkdir -p ~/sensors/zed_ws/src && cd ~/sensors/zed_ws/src
git clone https://github.com/stereolabs/zed-ros2-wrapper.git
git checkout da7f6ac
git switch -c 4.1.4
git submodule update --init --recursive

cd ~/sensors/zed_ws
rosdep update
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install --cmake-args=-DCMAKE_BUILD_TYPE=Release
```

------

### RoboSense LiDAR

```
mkdir -p ~/sensors/rslidar_ws/src && cd ~/sensors/rslidar_ws/src
git clone https://github.com/RoboSense-LiDAR/rslidar_sdk.git
cd rslidar_sdk && git submodule update --init
cd ..
git clone https://github.com/RoboSense-LiDAR/rslidar_msg.git
sudo apt-get install libpcap-dev
colcon build --packages-up-to rslidar_sdk
```

------

### HiPNUC IMU

```
mkdir -p ~/sensors/imu_ws/src && cd ~/sensors/imu_ws/src
git clone https://github.com/hipnuc/products.git
cd products/examples/ROS2/hipnuc_ws
sudo apt install ros-humble-gps-msgs
colcon build
```

Check the directory layout:

```
tree ~/sensors -L 2
```

------

### Add to Environment

Append the following lines to your `.bashrc`:

```
source ~/sensors/rslidar_ws/install/local_setup.bash
source ~/sensors/imu_ws/src/products/examples/ROS2/hipnuc_ws/install/local_setup.bash
source ~/sensors/zed_ws/install/local_setup.bash
```

Test each driver:

```
ros2 launch zed_wrapper zed_camera.launch.py camera_model:=zed2
ros2 launch rslidar_sdk start.py
ros2 launch hipnuc_imu imu_spec_msg.launch.py
```

------

## Module Installation

### Install Conda

```
wget http://repo.continuum.io/miniconda/Miniconda3-py39_4.9.2-Linux-aarch64.sh
bash Miniconda3-py39_4.9.2-Linux-aarch64.sh
```

Set the installation path to:

```
/home/airsbot2/miniconda3
```

------

### Install Dependencies

```
sudo pip install vcstool
cd ${DIR_AIRSHIP}/src
vcs-import < airship/dependencies.yaml
sudo apt install libcudnn8 libcudnn8-dev
```

------

### AIRSHIP Perception Module

```
conda create -n airship_perception python=3.10
conda activate airship_perception
```

Install PyTorch (for JetPack 6.0):

```
wget https://download.pytorch.org/whl/torch-2.3.0-cp310-cp310-linux_aarch64.whl
wget https://download.pytorch.org/whl/torchaudio-2.3.0+952ea74-cp310-cp310-linux_aarch64.whl
wget https://download.pytorch.org/whl/torchvision-0.18.0a0+6043bc2-cp310-cp310-linux_aarch64.whl

pip install torch*.whl torchaudio*.whl torchvision*.whl
```

Install perception libraries:

```
cp -r ${DIR_AIRSHIP}/src/Grounded-Segment-Anything/* ${DIR_AIRSHIP}/src/airship/airship_perception/lib/
cd ${DIR_AIRSHIP}/src/airship/airship_perception/lib/
pip install --no-build-isolation -e GroundingDINO
pip install -e segment-anything
pip install --upgrade diffusers[torch]
pip install -r requirements.txt
pip install --upgrade transformers
```

Download pretrained weights:

```
cd models
git lfs install
GIT_LFS_SKIP_SMUDGE=1 git clone https://hf-mirror.com/google-bert/bert-base-uncased
cd bert-base-uncased && git lfs pull && cd ..
wget https://github.com/IDEA-Research/GroundingDINO/releases/download/v0.1.0-alpha/groundingdino_swint_ogc.pth
wget https://dl.fbaipublicfiles.com/segment_anything/sam_vit_h_4b8939.pth
```

Build the module:

```
cd ${DIR_AIRSHIP}
conda activate airship_perception
colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release --symlink-install --packages-up-to airship_perception
```

------

### AIRSHIP Grasp Module

```
conda create -n airship_grasp python=3.10.12
conda activate airship_grasp
```

Install PyTorch:

```
pip install torch-2.3.0-cp310-cp310-linux_aarch64.whl
pip install torchaudio-2.3.0+952ea74-cp310-cp310-linux_aarch64.whl
pip install torchvision-0.18.0a0+6043bc2-cp310-cp310-linux_aarch64.whl
```

Install Realsense SDK:

```
sudo apt install ros-humble-librealsense2*
sudo apt install ros-humble-realsense2-*
```

Download & configure Scale-Balanced-Grasp:

```
cd ${DIR_AIRSHIP}/src/airship/airship_grasp/lib
git clone https://github.com/mahaoxiang822/Scale-Balanced-Grasp
mv Scale-Balanced-Grasp Scale_Balanced_Grasp
cd Scale_Balanced_Grasp
cp ${DIR_AIRSHIP}/src/airship/airship_grasp/doc/3rd_party/requirements.txt requirements.txt
pip install -r requirements.txt
```

Download & extract tolerance labels:

```
mkdir logs
mv tolerance.tar logs/
cd logs
tar -xvf tolerance.tar
```

Install PointNet2, KNN, GraspNet API:

```
cd pointnet2
pip install .

cd ../knn
cp ${DIR_AIRSHIP}/src/airship/airship_grasp/doc/3rd_party/knn.h src/knn.h 
cp ${DIR_AIRSHIP}/src/airship/airship_grasp/doc/3rd_party/vision.h src/cuda/vision.h
pip install .

cd ..
git clone https://github.com/graspnet/graspnetAPI
cd graspnetAPI
cp ${DIR_AIRSHIP}/src/airship/airship_grasp/doc/3rd_party/setup.py setup.py
pip install .
```

Build Grasp Module:

```
cd ${DIR_AIRSHIP}
conda activate airship_grasp
colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release --symlink-install --packages-up-to airship_grasp
```

------

### Navigation & Planner (Base Environment)

Deactivate conda:

```
conda deactivate
```

Install dependencies:

```
sudo apt install ros-humble-nav2-core ros-humble-pcl-ros libasound-dev portaudio19-dev libportaudio2 libportaudiocpp0
pip install pyaudio openai pocketsphinx open3d
sudo apt install ros-humble-cartographer ros-humble-cartographer-ros
sudo apt install ros-humble-nav2-simple-commander ros-humble-navigation2
sudo apt install ros-humble-pointcloud-to-laserscan ros-humble-tf-transformations
sudo apt install libopenblas-dev
```

Build AIRSHIP base modules:

```
colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release --symlink-install --packages-up-to neo_local_planner2 airship_chat airship_description airship_interface airship_localization airship_navigation airship_object airship_planner
```

Rebuild in corresponding environments:

```
conda activate airship_perception
colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release --symlink-install --packages-up-to airship_perception

conda activate airship_grasp
colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release --symlink-install --packages-up-to airship_grasp
```

------

## Module Launching

```
# Localization & Navigation
ros2 launch airship_localization airship_localization_gt_sim.launch.py
ros2 launch airship_navigation airship_navigation_sim.launch.py
ros2 service call /airship_navigation/navigate_to_pose airship_interface/srv/AirshipNav "{x: 0.5, y: 0.0, theta: 0.0}"

# Perception
conda activate airship_perception
ros2 launch airship_perception run_airship_perception_node.launch.py

# Grasp
conda activate airship_grasp
ros2 launch airship_grasp grasp_sim.launch.py use_isaac_sim:=true
ros2 service call /airship_grasp/grasp_server airship_interface/srv/AirshipGrasp "{task: 'pick', obj: 'apple'}"
```

------

## LLM Integration (ChatGPT API)

Edit `airship_planner/config/airship_planner.yaml`:

```
semantic_map_file: "nav_goal.yaml"
llm_server_url: "https://your-llm-server/api/chat"
openai_api_key: "your-key"
openai_api_url: "https://pro.aiskt.com/v1"
```

Launch planner:

```
cd ${DIR_AIRSHIP}
source install/local_setup.bash
ros2 launch airship_planner airship_planner_launch.py
```

Test example:

```
ros2 service call /airship_planner/planner_server airship_interface/srv/AirshipInstruct "msg: Go to the table and pick up the sugar box"
```

And the it will output the planning results like:

```
[llm_planner-1] [INFO] [1744863322.650317661] [airship_planner]: Parsing users' instruction: Go to the table and pick up the sugar box
[llm_planner-1] [INFO] [1744863325.287019214] [airship_planner]: LLM planned task list: [['go_to', ['coordinate table', [1.3103794701759044, 3.852526931762695, 1.5703794701759044]]], ['pick_up', ['sugar box']], ['go_to', ['coordinate table', [1.3103794701759044, 3.852526931762695, 1.5703794701759044]]], ['place', ['sugar box']]]
[llm_planner-1] [INFO] [1744863325.288905759] [airship_planner]: Start LLM planner scheduling...
```



------

## Connecting to Isaac Sim

Install Isaac Sim 4.2.0 from [NVIDIA's official download page](https://docs.omniverse.nvidia.com/4.5.0/installation/download.html).

Ensure both Orin and the host have ROS 2 Humble installed.

Verify with:

```
source /opt/ros/humble/setup.bash
printenv | grep ROS
```

> Ensure both devices are in the same local network and share the same `ROS2_DOMAIN_ID`:

```
export ROS_DOMAIN_ID=1
echo $ROS_DOMAIN_ID
```

Test communication:

```
# On host
ros2 run demo_nodes_cpp listener

# On Orin
ros2 run demo_nodes_cpp talker
```

If you see "Hello World" messages arriving on the host, your network setup is successful.