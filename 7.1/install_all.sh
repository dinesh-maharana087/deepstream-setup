#!/bin/bash

cd install

bash 01_prerequisites.sh
bash 02_cuda.sh
bash 03_tensorrt.sh
bash 04_deepstream.sh
bash 05_python_apps.sh

echo "✅ Installation Completed!"