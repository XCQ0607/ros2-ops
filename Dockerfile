# -------------------------------------------
# Image B: Jetson 部署专用 (ARM64) - Modified
# -------------------------------------------
FROM ros:humble-ros-base

LABEL org.opencontainers.image.source=https://github.com/XCQ0607/dockerimage
LABEL org.opencontainers.image.description="ROS2 Development Image"
LABEL org.opencontainers.image.licenses=MIT

ENV DEBIAN_FRONTEND=noninteractive

# 1. 安装编译工具、Agent 依赖和 sudo
# [修改]: 在这里统一安装 'sudo'，避免后面重复 apt-get update
RUN apt-get update && apt-get install -y \
    ros-humble-rmw-cyclonedds-cpp \
    ros-humble-foxglove-bridge \
    ros-humble-cv-bridge \
    ros-humble-vision-msgs \
    build-essential \
    cmake \
    git \
    python3-pip \
    python3-opencv \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# 2. 安装必要的 Python 库
RUN pip3 install --no-cache-dir \
    transforms3d \
    pyserial \
    pymavlink

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

# -------------------------------------------------------
# 【新增步骤】创建与 Jetson 宿主机 UID 一致的用户并配置 sudo
# -------------------------------------------------------
ARG USERNAME=ros2
ARG USER_UID=1000
ARG USER_GID=1000

# 创建用户组和用户，并将用户加入 sudo 组
# [修改]: 增加了 -s /bin/bash 确保用户 shell 正常
# [修改]: 这里的 echo 配置赋予了完全的无密码 sudo 权限
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME -s /bin/bash \
    && usermod -aG sudo $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# 4. 环境变量
ENV RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# 5. 修正权限和切换用户
# 将 ROS 环境 source 脚本加到新用户的 .bashrc 里
RUN echo "source /opt/ros/humble/setup.bash" >> /home/$USERNAME/.bashrc

# 创建工作空间目录并修正权限
WORKDIR /home/$USERNAME/workspace
RUN chown -R $USERNAME:$USERNAME /home/$USERNAME

# 切换到非 root 用户
USER $USERNAME

CMD ["/bin/bash"]
