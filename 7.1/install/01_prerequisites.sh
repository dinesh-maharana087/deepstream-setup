#!/bin/bash
set -e

source ../config/versions.env
source ../utils/logger.sh

echo "Installing prerequisites..."

sudo apt update

sudo apt install -y \
libssl3 libssl-dev libgles2-mesa-dev \
libgstreamer1.0-0 gstreamer1.0-tools \
gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
gstreamer1.0-plugins-ugly gstreamer1.0-libav \
libgstreamer-plugins-base1.0-dev \
libgstrtspserver-1.0-0 libjansson4 \
libyaml-cpp-dev libjsoncpp-dev \
protobuf-compiler gcc make git python3 curl