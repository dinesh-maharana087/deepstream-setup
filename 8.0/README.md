# DeepStream 8.0 Installation - Ubuntu 24.04

Automated installer for NVIDIA DeepStream 8.0 on Ubuntu 24.04 LTS. Production-ready with comprehensive error handling, idempotency, and proper dependency management.

## Prerequisites

- **OS**: Ubuntu 24.04 LTS (strictly enforced)
- **GPU**: NVIDIA GPU with CUDA compute capability 5.0 or higher
- **Network**: Internet access to download packages
- **Sudo**: Passwordless sudo access required, OR run with `sudo bash install_all.sh`
- **Storage**: ~10GB free disk space
- **CUDA Driver**: NVIDIA GPU driver pre-installed

## Quick Start

```bash
# Clone the repository
git clone https://github.com/dinesh-maharana087/deepstream-setup.git
cd deepstream-setup/8.0

# Make scripts executable
chmod +x install_all.sh cleanup.sh
chmod +x install/*.sh utils/*.sh

# Run the installer
bash install_all.sh
```

## Installation Details

### What Gets Installed

1. **System Prerequisites** (01_prerequisites.sh)
   - Development tools: build-essential, cmake, meson, gcc, g++
   - GStreamer libraries and plugins
   - Development headers and libraries
   - Python 3 development packages
   - curl, wget, git

2. **CUDA 12.8** (02_cuda.sh)
   - Uses modern GPG keyring method (no deprecated apt-key)
   - Installs cuda-toolkit-12-8
   - Registers NVIDIA CUDA repository

3. **TensorRT 10.9.0.34** (03_tensorrt.sh)
   - All required TensorRT development and runtime libraries
   - Version-pinned for strict compatibility

4. **DeepStream 8.0** (04_deepstream.sh)
   - Official DeepStream runtime and tools
   - Installed to /opt/nvidia/deepstream
   - Downloaded from NVIDIA NGC

5. **Python Bindings** (05_python_apps.sh)
   - PyDS (Python DeepStream bindings)
   - CUDA Python 12.8
   - Installed in isolated virtualenv (no --break-system-packages)
   - Virtual environment: $HOME/deepstream-install/deepstream_venv

### Configuration

Edit `config/versions.env` to customize:
```bash
# Working directory (default: $HOME/deepstream-install)
export WORK_DIR="$HOME/deepstream-install"

# Versions (strictly pinned to 8.0)
export DEEPSTREAM_VERSION="8.0"
export CUDA_VERSION="12-8"
export TENSORRT_VERSION="10.9.0.34-1+cuda12.8"
export PYTHON_APPS_VERSION="v1.2.2"
```

### Environment Variables

```bash
# Skip GPU requirement check (for testing/CI, default: true)
GPU_REQUIRED=false bash install_all.sh

# Custom work directory
WORK_DIR=/opt/deepstream bash install_all.sh

# Continue on errors (testing only)
CONTINUE_ON_ERROR=true bash install_all.sh
```

## Advanced Usage

### Run Individual Scripts

Each installation step can be run independently:

```bash
# Install only system prerequisites
bash install/01_prerequisites.sh

# Install only CUDA
bash install/02_cuda.sh

# Install only TensorRT
bash install/03_tensorrt.sh

# Install only DeepStream runtime
bash install/04_deepstream.sh

# Install only Python bindings
bash install/05_python_apps.sh
```

### Use Python Bindings

After installation, activate the virtual environment:

```bash
# Activate DeepStream Python environment
source $HOME/deepstream-install/deepstream_venv/bin/activate

# Now you can use PyDS
python3 -c "import pyds; print(f'PyDS: {pyds.__version__}')"

# Run Python DeepStream apps
cd $HOME/deepstream-install/deepstream_python_apps/
python3 apps/deepstream-test1/deepstream_test1.py

# Deactivate when done
deactivate
```

### Post-Installation Cleanup

Optional: Remove temporary files and clear apt cache (~500MB+)

```bash
bash cleanup.sh
```

## Verification

### Check Installation

View the system status report:

```bash
bash -c 'source config/versions.env; source utils/check.sh; system_summary'
```

### Verify Each Component

```bash
# Check CUDA
which nvcc
nvcc --version

# Check TensorRT
dpkg -l | grep libnvinfer

# Check DeepStream
ls /opt/nvidia/deepstream
/opt/nvidia/deepstream/tools/gst-launch-1.0 --version

# Check Python bindings
source $HOME/deepstream-install/deepstream_venv/bin/activate
python3 -c "import pyds; print(pyds.__version__)"
deactivate
```

## Troubleshooting

### GPU Not Detected

```bash
# Verify GPU driver
nvidia-smi

# Check CUDA paths
nvcc --version

# Install GPU driver if needed
sudo apt-get install nvidia-driver-XXX
```

### Ubuntu Version Mismatch

This installer **only works with Ubuntu 24.04 LTS**. Other versions are rejected outright.

```bash
# Check your version
lsb_release -a

# See expected version
cat config/versions.env
```

### Permission Errors

Ensure passwordless sudo or run with sudo:

```bash
# Method 1: Add to sudoers (run without password)
sudo visudo
# Add: your_user ALL=(ALL) NOPASSWD: ALL

# Method 2: Run installer with sudo
sudo bash install_all.sh
```

### Installation Logs

Logs are saved to: `$WORK_DIR/logs/install.log`

```bash
# View installation log
cat $HOME/deepstream-install/logs/install.log

# Follow log in real-time
tail -f $HOME/deepstream-install/logs/install.log
```

### Idempotent Re-runs

All scripts are idempotent—safe to run multiple times:

```bash
# First run
bash install_all.sh

# Subsequent runs skip already-installed components
bash install_all.sh   # Second run completes quickly
```

## File Structure

```
8.0/
├── install_all.sh                # Main orchestrator (entry point)
├── cleanup.sh                      # Post-install cleanup
├── config/
│   └── versions.env               # Version configuration
├── install/
│   ├── 01_prerequisites.sh        # System packages
│   ├── 02_cuda.sh                 # CUDA 12.8 toolkit
│   ├── 03_tensorrt.sh             # TensorRT 10.9.0.34
│   ├── 04_deepstream.sh           # DeepStream 8.0
│   └── 05_python_apps.sh          # Python bindings
├── utils/
│   ├── logger.sh                  # Logging with colors and timestamps
│   └── check.sh                   # System validation functions
├── logs/                          # Installation logs directory
└── README.md                      # This file
```

## Testing & Validation

### Idempotency Test

Verify scripts are safe to re-run:

```bash
# First installation
bash install_all.sh

# Second run—should skip already-installed components
bash install_all.sh
```

### GPU Optional Test

Skip GPU requirement for CI/testing:

```bash
GPU_REQUIRED=false bash install_all.sh
```

### Custom Work Directory Test

Install to custom location:

```bash
WORK_DIR=/tmp/deepstream-test bash install_all.sh
```

## Key Features

✅ **Production-Ready**
- Comprehensive error handling with line-number reporting
- All apt operations use `-y` for non-interactive automation
- Idempotent: safe to re-run without duplication

✅ **Modern & Secure**
- Replaces deprecated `apt-key` with GPG keyring method
- Python packages use isolated virtualenv (no `--break-system-packages`)
- No unnecessary sudo usage; sudo only where required

✅ **Ubuntu 24.04 Exclusive**
- Strict validation of Ubuntu version
- All packages optimized for 24.04
- No legacy version compatibility code

✅ **Comprehensive Logging**
- Color-coded log levels (INFO, SUCCESS, WARN, ERROR)
- Timestamps on all log entries
- Clean separation of stdout/stderr to log file and console
- Full session logs in `$WORK_DIR/logs/install.log`

✅ **Developer-Friendly**
- Modular script structure: run individually or all at once
- Clear variable naming and code comments
- Environment variable overrides for testing

## Known Limitations

- **SSH Sessions**: May require `sudo -S` for password input in non-interactive SSH
- **Network**: Download speeds depend on internet connection to NVIDIA CDN
- **Disk Space**: Requires ~10GB free for CUDA and TensorRT downloads
- **First-Time CUDA**: Initial CUDA setup downloads ~2GB of packages

## Support & Issues

- **Official Docs**: https://docs.nvidia.com/deepstream/
- **NVIDIA DeepStream Forum**: https://forums.developer.nvidia.com/c/deep-learning/deepstream/
- **NGC DeepStream**: https://ngc.nvidia.com/catalog/resources/nvidia_deepstream

## License

This installation automation scripts are provided as-is. DeepStream, CUDA, and TensorRT are subject to NVIDIA's licensing terms.

## Changelog

### Version 8.0 (Refactored - Production Ready)
- ✨ Modern GPG keyring method (replaces deprecated apt-key)
- ✨ Virtualenv for Python packages (no --break-system-packages)
- ✨ Comprehensive error handling and validation
- ✨ Color-coded logging with timestamps
- ✨ Full idempotency support
- ✨ Ubuntu 24.04 exclusive validation
- ✨ Cleaner code with better comments
- ✨ GPU requirement configurable
