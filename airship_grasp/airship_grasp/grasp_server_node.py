import threading
import nvtx
import datetime

from cv_bridge import CvBridge
from geometry_msgs.msg import TransformStamped
from rclpy.callback_groups import MutuallyExclusiveCallbackGroup
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node
from scipy.spatial.transform import Rotation as R
from sensor_msgs.msg import Image
from sensor_msgs.msg import JointState
from tf2_ros import Buffer, TransformListener, TransformBroadcaster
from visualization_msgs.msg import Marker
import message_filters
import numpy as np
import time
import rclpy


from airship_interface.srv import AirshipGrasp, SegmentationGrasping
from lib.utility_graspnet import UtilityGraspNet
from lib.utility_ik import UtilityIk

class GraspServer(Node):
    def __init__(self):
        super().__init__('grasp_server')
        # Declare and get config path
        self.tf_broadcaster = TransformBroadcaster(self)
        self.marker_pub = self.create_publisher(Marker, 'visualization_marker', 10)
        self.declare_parameter('config', 'airship_grasp_sim_config.yaml')
        self.declare_parameter('use_isaac_sim', False)
        self.config_path = self.get_parameter('config').get_parameter_value().string_value
        self.use_isaac_sim = self.get_parameter('use_isaac_sim').get_parameter_value().bool_value
        self.color_image = None
        self.depth_image = None
        self.last_grasp_pose = None
        self.tf_publish_timer = self.create_timer(0.1, self.publish_transforms) # 10 Hz
        # Grasp Server
        self.grasp_srv = self.create_service(
            AirshipGrasp, '/airship_grasp/grasp_server', self.grasp_callback, callback_group=MutuallyExclusiveCallbackGroup()
        )
        # Segmentation client
        self.seg_cli = self.create_client(
            SegmentationGrasping, '/airship_perception/SegmentationGrasping', callback_group=MutuallyExclusiveCallbackGroup()
        )
        while not self.seg_cli.wait_for_service(timeout_sec=1.0):
            self.get_logger().info('Seg service not available, waiting again...')
        self.get_logger().info('Initial Grasp_Server_node')  
        # Subscriptions
        self.color_sub = message_filters.Subscriber(self, Image, '/camera/camera/color/image_raw')
        self.depth_sub = message_filters.Subscriber(self, Image, '/camera/camera/aligned_depth_to_color/image_raw')
        self.img_sync = message_filters.ApproximateTimeSynchronizer([self.color_sub, self.depth_sub], 10, 0.1)
        self.img_sync.registerCallback(self.callback_img)
        if self.use_isaac_sim:
            self.joint_state_sub = self.create_subscription(JointState, 'joint_states', self.joint_states_callback, 10)
            # Publisher
            self.joint_command_pub = self.create_publisher(JointState, 'joint_command', 10)
            self.cur_joint_states = JointState()
        # Other variables
        self.cv_bridge = CvBridge()
        # Initialize submodule
        self.utility_graspnet = UtilityGraspNet(self.config_path)
        if not self.use_isaac_sim:
            from lib.utility_elephant_robot import UtilityElephantRobot
            self.utility_elephant_robot = UtilityElephantRobot(self.config_path)
        else:
            self.ik = UtilityIk(self.config_path)
            # Creat TF2 buffer & listener
            self.tf_buffer = Buffer()
            self.tf_listener = TransformListener(self.tf_buffer, self)
        
    def callback_img(self, msg_color, msg_depth):
        with nvtx.annotate("callback_img", color="blue"):
            self.color_image = msg_color
            self.depth_image = msg_depth
    
    def req_seg_sync(self, obj):
        request = SegmentationGrasping.Request()
        request.object = obj
        request.image = self.color_image
        result = self.seg_cli.call(request)
        mask = np.array(self.cv_bridge.imgmsg_to_cv2(result.mask, desired_encoding='mono8'), dtype=np.bool)
        rgb = np.array(self.cv_bridge.imgmsg_to_cv2(self.color_image, desired_encoding='bgr8'), dtype=np.float64) / 255.0
        if self.use_isaac_sim:
            depth = np.array(self.cv_bridge.imgmsg_to_cv2(self.depth_image, desired_encoding='32FC1'))
        else:
            depth = np.array(self.cv_bridge.imgmsg_to_cv2(self.depth_image, desired_encoding='16UC1'))
        return rgb, depth, mask
    
    def request_segmentaion_service(self, obj):
        result = {}
        def target():
            result['data'] = self.req_seg_sync(obj)
        client_thread = threading.Thread(target=target)
        client_thread.start()
        client_thread.join()
        return result.get('data', ([], [], []))
    
    def publish_transforms(self):
        if self.last_grasp_pose is None:
            return

        rot_mats = self.last_grasp_pose.rotation_matrices
        trans_vecs = self.last_grasp_pose.translations
        for i in range(len(rot_mats)):
            quat = R.from_matrix(rot_mats[i]).as_quat()
            trans = trans_vecs[i]

            t = TransformStamped()
            t.header.stamp = self.get_clock().now().to_msg()
            t.header.frame_id = "sensor_d435_color_optical_frame" 
            t.child_frame_id = f"grasp_{i}"
            t.transform.translation.x = float(trans[0])
            t.transform.translation.y = float(trans[1])
            t.transform.translation.z = float(trans[2])

            t.transform.rotation.x = float(quat[0])
            t.transform.rotation.y = float(quat[1])
            t.transform.rotation.z = float(quat[2])
            t.transform.rotation.w = float(quat[3])

            self.tf_broadcaster.sendTransform(t)
            self.publish_grasp_marker(trans, quat, i)

    def _handle_pick_task(self, obj, response):
        # Call segmentation service
        self.last_grasp_pose = None
        self._logger.info("Start grasping ...")
        self.set_arm_init_states()
        rgb, depth, mask = self.request_segmentaion_service(obj)
        self._logger.info("Thread Done ... Segmentation service completed")
        # Determine visibility
        if np.any(mask):
            if not self.use_isaac_sim:
                # Preparing for grasp
                self.utility_elephant_robot.prepare_for_grasp()
                arm_pose = self.utility_elephant_robot.get_arm_pose()
                trans_gripper2base = self.utility_elephant_robot.pose_to_transformation_matrix(arm_pose)
            else:
                # Preparing for grasp
                # self.prepare_for_grasp()
                # trans_link = [0.0, 0.0, -0.47, 0.0, -67.5, -90.0]
                trans_link = [0.0, 0.0, 0.0, 0.0, 0.0, -90.0]
                # trans_link = self.ik.pose_to_transformation_matrix(trans_link)
                #trans_gripper2base = self.get_ee_link_pose()
                trans_gripper2base = self.get_camera_link_pose()
                # trans_gripper2base = trans_link @ trans_gripper2base
                # trans_gripper2base = trans_link

            # calculate and select suitable grasp pose
            center_mask_point = self.utility_graspnet.get_3d_center_mask(mask, depth, self.use_isaac_sim)
            grasp_pose = self.utility_graspnet.grasp_pose_estimation(rgb, depth, mask)
            
            self.last_grasp_pose = grasp_pose
            
            if not self.use_isaac_sim:
                grasp_coords = self.utility_elephant_robot.select_best_grasp(grasp_pose, center_mask_point, trans_gripper2base)

                if self.utility_elephant_robot.execute_grasp(grasp_coords):
                    response.ret = AirshipGrasp.Response.SUCCESS
                    self.get_logger().info(f'Successfully grasped {obj}')
                else:
                    response.ret = AirshipGrasp.Response.FAILED_TO_REACH_OBJECT
                    response.x, response.y, response.z = grasp_coords[:3]
                    self.get_logger().info(f'Cannot reach {obj}')
            else:
                grasp_coords = self.ik.select_best_grasp(grasp_pose, center_mask_point, trans_gripper2base)
                if self.excute_grasp(grasp_coords):
                    response.ret = AirshipGrasp.Response.SUCCESS
                    self.get_logger().info(f'Successfully grasped {obj}')
                else:
                    response.ret = AirshipGrasp.Response.FAILED_TO_REACH_OBJECT
                    response.x, response.y, response.z = grasp_coords[:3]
                    self.get_logger().info(f'Cannot reach {obj}')
        else:
            response.ret = AirshipGrasp.Response.FAILED_TO_FIND_OBJECT
            self.get_logger().info(f'Cannot find {obj}')
    
    def _handle_place_task(self, response):
        self.last_grasp_pose = None
        self.get_logger().info("Starting place task...")
        self.get_logger().info("Set arm init...")
        if not self.use_isaac_sim:
            self.utility_elephant_robot.handle_place()
        else:
            self.set_gripper_action(0.2)
            while(self.is_gripper_inposition(0.2)):
                self.get_logger().info('Opening gripper ...')
                time.sleep(1)
        response.ret = AirshipGrasp.Response.SUCCESS
        self.get_logger().info(f'Already delivered to the location')
        
    def grasp_callback(self, request, response):
        start_time = time.time()
        start_time_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with nvtx.annotate("grasp_callback", color="green"):
            self.get_logger().info(f"Received request to {request.task} {request.obj}")
            if request.task == "pick":
                self._handle_pick_task(request.obj, response)
            elif request.task == "place":
                self._handle_place_task(response)
            end_time = time.time()
            delay_ms = (end_time - start_time) * 1000
            end_time_str = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_msg = f"[grasp_callback] start: {start_time_str}, end: {end_time_str}, latency: {delay_ms:.2f} ms"
            self.get_logger().info(log_msg)
            try:
                with open("/tmp/grasp_callback_delay.log", "a") as f:
                    f.write(f"{log_msg}\n")
            except Exception as e:
                self.get_logger().warn(f"Failed to write callback delay: {e}")
            return response

    def joint_states_callback(self, msg):
        with nvtx.annotate("joint_states_callback", color="red"):
            self.cur_joint_states = msg

    def excute_arm_pose(self, target_joint_states):
        joint_state_msg = JointState()

        joint_state_msg.name = [
            'joint_link1_to_base',
            'joint_link2_to_link1',
            'joint_link3_to_link2',
            'joint_link4_to_link3',
            'joint_link5_to_link4',
            'joint_link6_to_link5'
        ]

        # Set joint commands
        joint_state_msg.position = [
            target_joint_states.get('joint_link1_to_base', 0.0),
            target_joint_states.get('joint_link2_to_link1', -0.5),
            target_joint_states.get('joint_link3_to_link2', 0.7),
            target_joint_states.get('joint_link4_to_link3', -1.7),
            target_joint_states.get('joint_link5_to_link4', -1.57),
            target_joint_states.get('joint_link6_to_link5', 1.9)
        ]

        # Pub joint commands
        self.joint_command_pub.publish(joint_state_msg)

    def set_gripper_action(self, joint_position):
        # 0.2 for open, -0.4 for close
        joint_state_msg = JointState()
        joint_state_msg.name = ['gripper_controller']
        joint_state_msg.position = [joint_position]
        joint_state_msg.velocity = [0.0]
        joint_state_msg.effort = [0.0]
        self.joint_command_pub.publish(joint_state_msg)

    def is_arm_inpoition(self, target_position):
        self.get_logger().warn("is inposition check")
        joint_names = [
            'joint_link1_to_base',
            'joint_link2_to_link1',
            'joint_link3_to_link2',
            'joint_link4_to_link3',
            'joint_link5_to_link4',
            'joint_link6_to_link5'
        ]

        current_positions = []

        # Get target joints with names
        for name in joint_names:
            if name in self.cur_joint_states.name:
                idx = self.cur_joint_states.name.index(name)
                current_positions.append(self.cur_joint_states.position[idx])

        # Extract joint states
        target_positions_list = [target_position[name] for name in joint_names if name in target_position]
        self.get_logger().warn(f"current_positions: {np.array(current_positions)}")
        self.get_logger().warn(f"target_position: {np.array(target_positions_list)}")
        

        # Check num between joints and their states.
        if len(current_positions) != len(target_positions_list):
            self.get_logger().warn("error return")
            return True

        distance = np.linalg.norm(np.array(current_positions) - np.array(target_positions_list))

        

        # Is distance error under threshold?
        if distance < 0.05:
            return False
        else:
            return True

    def is_gripper_inposition(self, target_position):
        # Get gripper state
        current_gripper_position = self.cur_joint_states.position[self.cur_joint_states.name.index('gripper_controller')]

        # Compute distance error
        gripper_error = np.abs(current_gripper_position - target_position)

        # Set error threshold
        threshold = 0.05

        # Is distance error under threshold?
        if gripper_error < threshold:
            return False
        else:
            return True

    def get_ee_link_pose(self):
        """
        Get transformation between manipulator_base_link & ee_link.
        """
        try:
            self.tf_buffer.can_transform('manipulator_base_link', 'ee_link', rclpy.time.Time())

            transform: TransformStamped = self.tf_buffer.lookup_transform('base', 'ee_link', rclpy.time.Time())

            translation = transform.transform.translation
            rotation = transform.transform.rotation

            arm_pose = {
                'position': np.array([translation.x, translation.y, translation.z]),
                'orientation': R.from_quat([rotation.x, rotation.y, rotation.z, rotation.w])
            }

            trans_gripper2base = self.ik.tf_to_transformation_matrix(arm_pose)

            return trans_gripper2base

        except Exception as e:
            self.get_logger().warn(f"Could not get transform: {e}")
            return None, None

    def get_camera_link_pose(self):
        """
        Get transformation between manipulator_base_link & ee_link.
        """
        try:
            self.tf_buffer.can_transform('manipulator_base_link', 'sensor_d435_color_optical_frame', rclpy.time.Time())

            transform: TransformStamped = self.tf_buffer.lookup_transform('base', 'sensor_d435_color_optical_frame', rclpy.time.Time())

            translation = transform.transform.translation
            rotation = transform.transform.rotation

            arm_pose = {
                'position': np.array([translation.x, translation.y, translation.z]),
                'orientation': R.from_quat([rotation.x, rotation.y, rotation.z, rotation.w])
            }

            trans_gripper2base = self.ik.tf_to_transformation_matrix(arm_pose)

            return trans_gripper2base

        except Exception as e:
            self.get_logger().warn(f"Could not get transform: {e}")
            return None, None

    def prepare_for_grasp(self):
        # Set gripper open
        self.set_gripper_action(0.2)
        while(self.is_gripper_inposition(0.2)):
            self.get_logger().info("Opening gripper...")
            time.sleep(1)

    def excute_grasp(self, grasp_coords):
        x, y, z = (np.array(grasp_coords[:3]) / 1000.0)
        self.get_logger().info(f"Grasp target (x, y, z): {x}, {y}, {z}")
        # Determine Graspability
        start_time = time.time()
        if self.ik.is_out_of_reach(x, y, z):
            self.get_logger().info('The IK module cannot calculate the joint angles based on the target pose.')
            return False
        else:
            target_joint_states = self.ik.excute(x, y, z)
            self.excute_arm_pose(target_joint_states)
            self.get_logger().info("before while")
            while(self.is_arm_inpoition(target_joint_states)):
                self.get_logger().info('while check')
                time.sleep(1)
            self.set_gripper_action(-0.4)
            while(self.is_gripper_inposition(-0.4)):
                self.get_logger().info("Closing grasp.")
                current_time = time.time()
                if current_time - start_time <= 30:
                    self.get_logger().info("Closing grasp")
                    time.sleep(1)
                else:
                    raise_states = self.ik.get_raise_pose()
                    self.excute_arm_pose(raise_states)
                    self.get_logger().info('Successfully grasped')
                    return True
            return True

    def set_arm_init_states(self):
        init_joint_states = self.ik.get_init_pose()
        self.excute_arm_pose(init_joint_states)
        while(self.is_arm_inpoition(init_joint_states)):
            time.sleep(1)

    def publish_grasp_marker(self, translation, rotation_quat, marker_id):
        marker = Marker()
        marker.header.frame_id = "sensor_d435_color_optical_frame"
        marker.header.stamp = self.get_clock().now().to_msg()
        marker.ns = "grasp_poses"
        marker.id = marker_id
        marker.type = Marker.ARROW
        marker.action = Marker.ADD

        # 设置位置
        marker.pose.position.x = float(translation[0])
        marker.pose.position.y = float(translation[1])
        marker.pose.position.z = float(translation[2])

        # 设置方向（四元数）
        marker.pose.orientation.x = float(rotation_quat[0])
        marker.pose.orientation.y = float(rotation_quat[1])
        marker.pose.orientation.z = float(rotation_quat[2])
        marker.pose.orientation.w = float(rotation_quat[3])

        # 设置箭头大小，长度(x轴)和粗细(y,z轴)
        marker.scale.x = 0.1
        marker.scale.y = 0.02
        marker.scale.z = 0.02

        # 设置颜色，红色，完全不透明
        marker.color.r = 1.0
        marker.color.g = 0.0
        marker.color.b = 0.0
        marker.color.a = 1.0

        self.marker_pub.publish(marker)

def main(args=None):
    rclpy.init(args=args)
    grasp = GraspServer()
    executor = MultiThreadedExecutor()
    executor.add_node(grasp)
    try:
        grasp.get_logger().info('Beginning Grasp, shut down with CTRL-C')
        executor.spin()
    except KeyboardInterrupt:
        grasp.get_logger().info('Keyboard interrupt, shutting down.')
    finally:
        rclpy.shutdown()

if __name__ == '__main__':
    main()