#!/bin/bash

set -e                          # exit on error

#######################
# a script to test geneus
# it supports
#   * catkin
#   * one workspace/multiple workspaces
#   * several dependency situation

# dependency of msg packages
#    geneus
#    geneus_dep1 (depends on geneus)
#    geneus_dep2 (depends on geneus and geneus_dep1)
#    roseus
#    roseus_dep1 (depends on roseus and geneus_dep2)
#    roseus_dep2 (depends on roseus and roseus_dep1)


# parse arguments
MANIFEST=package.xml
WORKSPACE_TYPE=MULTI
ARGV=$@
PACKAGE=ALL
while [ $# -gt 0 ]; do
    case "$1" in 
        "--one-workspace")
            WORKSPACE_TYPE=ONE
            ;;
        "--package")
            shift
            PACKAGE=$1
            ;;
    esac
    shift
done


CATKIN_DIR=/tmp/test_genmsg_$$
GENEUS_DEP1=${CATKIN_DIR}/src/geneus_dep1
GENEUS_DEP2=${CATKIN_DIR}/src/geneus_dep2
ROSEUS_DEP1=${CATKIN_DIR}/src/roseus_dep1
ROSEUS_DEP2=${CATKIN_DIR}/src/roseus_dep2

mkdir -p ${GENEUS_DEP1}/{msg,srv,action}
mkdir -p ${GENEUS_DEP2}/{msg,srv,action}
mkdir -p ${ROSEUS_DEP1}/{msg,srv,action}
mkdir -p ${ROSEUS_DEP2}/{msg,srv,action}

#trap 'rm -fr ${CATKIN_DIR}; exit 1' 1 2 3 15

function add_package.xml() {
    pkg_path=$1
    pkg_name=$2
    shift
    shift
    cat <<EOF > $pkg_path/package.xml
<package> 
<name>$pkg_name</name>
<version>0.0.1</version>
<description> genmsg test for roseus</description>
<maintainer email="k-okada@jsk.t.u-tokyo.ac.jp">Kei Okada</maintainer>
<license>BSD</license>
<buildtool_depend>catkin</buildtool_depend>
<build_depend>roscpp</build_depend>
<build_depend>message_generation</build_depend>
<build_depend>sensor_msgs</build_depend>
<build_depend>actionlib_msgs</build_depend>
<build_depend>std_msgs</build_depend>
<build_depend>roseus</build_depend>
<run_depend>roscpp</run_depend>
<run_depend>message_generation</run_depend>
<run_depend>sensor_msgs</run_depend>
<run_depend>actionlib_msgs</run_depend>
<run_depend>std_msgs</run_depend>
<run_depend>roseus</run_depend>
$(for pkg in $@
do
  echo '<build_depend>'$pkg'</build_depend><run_depend>'$pkg'</run_depend>'
done)
<run_depend>message_runtime</run_depend>
</package>
EOF
}

function add_manifest.xml() {
    pkg_path=$1
    pkg_name=$2
    shift
    shift
    
    cat <<EOF > $pkg_path/manifest.xml
<package>
  <description breif="genmsg test for roseus">genmsg test for roseus</description>
  <author>Kei Okada (k-okada@jsk.t.u-tokyo.ac.jp)</author>

  <license>BSD</license>

  <depend package="roseus"/>
  <depend package="roscpp"/>
  <depend package="actionlib_msgs"/>
  <depend package="sensor_msgs"/>
$(for pkg in $@
do
  echo '<depend package="'$pkg'"/>'
done)
</package>
EOF

}

function add_cmake() {
    pkg_path=$1
    shift
    cat <<EOF >$pkg_path/CMakeLists.txt
    cmake_minimum_required(VERSION 2.8.3)
project($(basename $pkg_path))

find_package(catkin REQUIRED COMPONENTS message_generation roscpp sensor_msgs actionlib_msgs
$(for pkg in $1
do
  echo $pkg
done)
)

add_service_files(
  FILES Empty.srv
)
add_message_files(
  FILES String.msg String2.msg
)
add_action_files(
  FILES Foo.action
)
generate_messages(
  DEPENDENCIES sensor_msgs std_msgs actionlib_msgs
$(for pkg in $2
do
  echo $pkg
done)
)
catkin_package(
    CATKIN_DEPENDS message_runtime roscpp sensor_msgs std_msgs actionlib_msgs
$(for pkg in $2
do
  echo $pkg
done)
)


add_executable(\${PROJECT_NAME} \${PROJECT_NAME}.cpp)
target_link_libraries(\${PROJECT_NAME} \${catkin_LIBRARIES})
add_dependencies(\${PROJECT_NAME} \${PROJECT_NAME}_generate_messages_cpp)

EOF
}

function add_cpp() {
    pkg_path=$1
    pkg_name=$2
    cat <<EOF > $pkg_path/$pkg_name.cpp
#include <ros/ros.h>
#include <std_msgs/String.h>
#include <$pkg_name/String.h>
#include <$pkg_name/Empty.h>

bool empty($pkg_name::EmptyRequest  &req,
           $pkg_name::EmptyResponse &res){
    return true;
}
int main(int argc, char **argv) {
    ros::init(argc, argv, "roseus_test_genmsg");
    ros::NodeHandle n;

    ros::Publisher pub = n.advertise<$pkg_name::String>("talker2", 100);

    $pkg_name::EmptyRequest srv;
    ros::ServiceServer service = n.advertiseService("empty", empty);

    ros::Rate rate(10);
    while (ros::ok()) {

        $pkg_name::String msg;
        msg.data = "msg";

        pub.publish(msg);


        rate.sleep();

        ros::spinOnce();
    }

    return 0;
}

EOF
}

function add_lisp() {
    pkg_path=$1
    pkg_name=$2
    cat <<EOF > $pkg_path/$pkg_name.l
(require :unittest "lib/llib/unittest.l")

(init-unit-test)

(ros::roseus "roseus_test_genmsg")

(deftest test-msg-instance
  (assert (ros::load-ros-manifest "$pkg_name")
          "load-ros-manifest")

  (assert (eval (read-from-string "(instance sensor_msgs::imu :init)"))
          "instantiating msg message")

  (assert (eval (read-from-string "(instance $pkg_name::String :init)"))
          "instantiating msg message")

  )

(run-all-tests)

(exit)
EOF
}

function add_msg() {
    pkg_path=$1
    parent_pkg=$2
    cat <<EOF >$pkg_path/msg/String.msg
Header header
string data
$parent_pkg/String parent_data
EOF
    cat <<EOF >$pkg_path/msg/String2.msg
Header header
string data
$parent_pkg/String parent_data
EOF
}

function add_action() {
   pkg_path=$1
   parent_pkg=$2
   cat <<EOF >$pkg_path/action/Foo.action
#goal
Header header
string data
$parent_pkg/String parent_data
---
#result
---
#feedback

EOF
}

function add_srv() {
    pkg_path=$1
    cat <<EOF >$pkg_path/srv/Empty.srv
EOF
}

# makeup packages
add_${MANIFEST} ${GENEUS_DEP1} geneus_dep1 geneus
add_${MANIFEST} ${GENEUS_DEP2} geneus_dep2 geneus geneus_dep1
add_${MANIFEST} ${ROSEUS_DEP1} roseus_dep1 roseus geneus_dep2 geneus_dep1
add_${MANIFEST} ${ROSEUS_DEP2} roseus_dep2 roseus_dep1 roseus geneus_dep1 geneus_dep2

add_cmake ${GENEUS_DEP1} 
add_cmake ${GENEUS_DEP2} "geneus_dep1" "geneus_dep1"
add_cmake ${ROSEUS_DEP1} "geneus_dep1 roseus geneus_dep2" "geneus_dep1 roseus geneus_dep2"
add_cmake ${ROSEUS_DEP2} "geneus_dep1 roseus geneus_dep2 roseus_dep1" "geneus_dep1 roseus geneus_dep2 roseus_dep1"
add_cpp ${GENEUS_DEP1} geneus_dep1
add_cpp ${GENEUS_DEP2} geneus_dep2
add_cpp ${ROSEUS_DEP1} roseus_dep1
add_cpp ${ROSEUS_DEP2} roseus_dep2
add_lisp ${GENEUS_DEP1} geneus_dep1
add_lisp ${GENEUS_DEP2} geneus_dep2
add_lisp ${ROSEUS_DEP1} roseus_dep1
add_lisp ${ROSEUS_DEP2} roseus_dep2

add_msg ${GENEUS_DEP1} std_msgs
add_msg ${GENEUS_DEP2} geneus_dep1
add_msg ${ROSEUS_DEP1} geneus_dep2
add_msg ${ROSEUS_DEP2} roseus_dep1

add_action ${GENEUS_DEP1} std_msgs
add_action ${GENEUS_DEP2} geneus_dep1
add_action ${ROSEUS_DEP1} geneus_dep2
add_action ${ROSEUS_DEP2} roseus_dep1


add_srv ${GENEUS_DEP1} std_msgs
add_srv ${GENEUS_DEP2} geneus_dep1
add_srv ${ROSEUS_DEP1} geneus_dep2
add_srv ${ROSEUS_DEP2} roseus_dep1


if [ $WORKSPACE_TYPE = ONE -a ! -e ${CATKIN_DIR}/src/jsk_roseus ]; then
    if [ ! -e `rospack find roseus`/CMakeLists.txt ]; then
        echo "$0: Could not found roseus source directory so quitting..."
        exit 0
    fi
    cp -r `rospack find roseus`/.. ${CATKIN_DIR}/src/jsk_roseus
fi

if [ $WORKSPACE_TYPE = ONE ]; then
    # reset environmental variables by sousing
    source /opt/ros/${ROS_DISTRO}/setup.bash
fi

cd ${CATKIN_DIR}
# always call twice catkin_make
if [ $PACKAGE = ALL ]; then
    catkin build --make-args VERBOSE=1
    catkin build --force-cmake --make-args VERBOSE=1
else
    catkin build --start-with $PACKAGE $PACKAGE --make-args VERBOSE=1
fi
source ${CATKIN_DIR}/devel/setup.bash

# # try to run roseus sample program
EUSLISP_DIR=`rospack find euslisp`
EUSLISP_EXE=`find $ROSEUS_DIR -type f -name irteusgl`
if [ ! "$EUSLISP_EXE" ]; then
    EUSLISP_EXE="rosrun euslisp irteusgl"
fi

ROSEUS_DIR=`rospack find roseus`
ROSEUS_EXE=`find $ROSEUS_DIR -type f -name roseus`
if [ ! "$ROSEUS_EXE" ]; then
    ROSEUS_EXE="rosrun roseus roseus"
fi

if [ $PACKAGE = ALL ]; then
    ${ROSEUS_EXE} ${CATKIN_DIR}/src/geneus_dep1/geneus_dep1.l $ARGV
    ${ROSEUS_EXE} ${CATKIN_DIR}/src/geneus_dep2/geneus_dep2.l $ARGV
    ${ROSEUS_EXE} ${CATKIN_DIR}/src/roseus_dep1/roseus_dep1.l $ARGV
    ${ROSEUS_EXE} ${CATKIN_DIR}/src/roseus_dep2/roseus_dep2.l $ARGV
else
    ${EUSLISP_EXE} ${ROSEUS_DIR}/euslisp/roseus.l ${CATKIN_DIR}/src/$PACKAGE/$PACKAGE.l $ARGV
fi

rm -rf ${CATKIN_DIR}

exit 0
