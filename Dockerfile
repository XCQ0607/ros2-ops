# -------------------------------------------
# Image B: Jetson 部署专用 (ARM64) - 适配 JetPack 6.2
# -------------------------------------------
FROM ros:humble-ros-base

LABEL org.opencontainers.image.source=https://github.com/XCQ0607/dockerimage
LABEL org.opencontainers.image.description="ROS2 Development Image for Jetson JetPack 6.2 (ARM64)"
LABEL org.opencontainers.image.licenses=MIT

ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_VISIBLE_DEVICES all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility,video,graphics,display

# 1. 安装基础编译工具和 ROS 通信/传感器组件
# 新增 libopenblas-dev，用于底层加速计算支持
RUN apt-get update && apt-get install -y \
    ros-humble-rmw-cyclonedds-cpp \
    ros-humble-foxglove-bridge \
    #ros-humble-cv-bridge \
    ros-humble-vision-msgs \
    ros-humble-actuator-msgs \
    ros-humble-gps-msgs \
    ros-humble-robot-localization \
    build-essential \
    cmake \
    git \
    nano \
    tmux \
    iputils-ping \
    net-tools \
    python3-pip \
    python3-opencv \
    sudo \
    libopenblas-dev \
    && rm -rf /var/lib/apt/lists/*

# ==============================================================================
# 2. Python 依赖分层安装 (AI 与硬件加速优化)
# ==============================================================================

# 2.1: 轻量级工具和通信依赖
RUN pip3 install --no-cache-dir  \
    jinja2 \
    kconfiglib \
    jsonschema \
    pyros-genmsg \
    pyserial \
    pymavlink \
    pyyaml \
    requests \
    tqdm \
    termcolor

# 2.2: 科学计算库
RUN pip3 install --no-cache-dir  \
     "numpy<2.0" \
    pandas \
    scipy \
    matplotlib \
    seaborn \
    transforms3d \
    shapely \
    scikit-learn

# 2.3: PyTorch 核心库 (【核心】专为 JetPack 6.2 / CUDA 12.6 优化)
# 使用 Nvidia Jetson AI Lab 官方源，确保安装的是 ARM64 GPU 版，避免后期推理缓慢
RUN pip3 install --no-cache-dir \
    torch torchvision torchaudio \
    --index-url https://pypi.jetson-ai-lab.io/jp6/cu126

# 2.4: 巨型 AI 视觉库
# 此时安装 Ultralytics，pip 会检测到上一层已安装的 GPU 版 torch，不会重复下载 CPU 版本
RUN pip3 install --no-cache-dir \
    lapx \
    supervision \
    ultralytics

# ==============================================================================

# 3. 编译安装 Micro-XRCE-DDS-Agent
WORKDIR /tmp
RUN git clone https://github.com/eProsima/Micro-XRCE-DDS-Agent.git && \
    cd Micro-XRCE-DDS-Agent && \
    mkdir build && cd build && \
    cmake .. && \
    make && \
    make install && \
    ldconfig /usr/local/lib/ && \
    rm -rf /tmp/Micro-XRCE-DDS-Agent

# 4. 源码编译核心通信库 (Overlay Workspace)
# 排除极占空间的 Gazebo (ros_gz) 仿真模块，仅保留 Jetson 实际所需的飞控消息体
WORKDIR /opt/overlay_ws/src
RUN git clone https://github.com/PX4/px4_msgs.git && \
    git clone https://github.com/PX4/px4_ros_com.git

WORKDIR /opt/overlay_ws
RUN apt-get update && \
    . /opt/ros/humble/setup.sh && \
    rosdep update && \
    rosdep install -r --from-paths src -i -y --rosdistro humble && \
    colcon build --merge-install --cmake-args -DCMAKE_BUILD_TYPE=Release && \
    rm -rf /var/lib/apt/lists/*

# 5. 设置环境变量
ENV RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# 6. 创建与宿主机一致的用户并配置无密码 sudo
ARG USERNAME=ros2
ARG USER_UID=1000
ARG USER_GID=1000

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME -s /bin/bash \
    && usermod -aG sudo $USERNAME \
    && usermod -aG video $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# 7. 配置用户 Bash 环境，自动 source ROS 环境
RUN echo "source /opt/ros/humble/setup.bash" >> /home/$USERNAME/.bashrc && \
    echo "source /opt/overlay_ws/install/setup.bash" >> /home/$USERNAME/.bashrc

# 8. 修正权限并设定工作目录
WORKDIR /home/$USERNAME/workspace
RUN chown -R $USERNAME:$USERNAME /home/$USERNAME

# 切换到普通用户
USER $USERNAME

CMD ["/bin/bash"]
