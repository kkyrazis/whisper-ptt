#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL="${WHISPER_MODEL:-base.en}"

echo "=== Whisper PTT Install ==="

# Install system packages
echo "Installing system packages..."
sudo dnf install -y sox ydotool intel-compute-runtime oneapi-level-zero cmake

# Check for Intel oneAPI
if [ ! -f /opt/intel/oneapi/setvars.sh ]; then
    echo "Intel oneAPI Base Toolkit not found."
    echo "Install it with:"
    echo "  sudo dnf config-manager --add-repo https://yum.repos.intel.com/oneapi"
    echo "  sudo rpm --import https://yum.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB"
    echo "  sudo dnf install intel-oneapi-base-toolkit"
    exit 1
fi

# Setup udev rule for ydotool
echo "Setting up udev rules..."
echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' | \
    sudo tee /etc/udev/rules.d/70-uinput.rules > /dev/null
sudo udevadm control --reload-rules && sudo udevadm trigger

# Add user to required groups
echo "Adding user to input, render, video groups..."
sudo usermod -aG input,render,video "$USER"

# Init and build whisper.cpp
echo "Building whisper.cpp with SYCL..."
cd "$SCRIPT_DIR"
git submodule update --init --recursive

cd "$SCRIPT_DIR/whisper.cpp"
source /opt/intel/oneapi/setvars.sh --force 2>/dev/null
rm -rf build
cmake -B build -DGGML_SYCL=ON -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx
cmake --build build --config Release -j"$(nproc)"

# Download model
echo "Downloading ${MODEL} model..."
bash models/download-ggml-model.sh "$MODEL"

# Install systemd services
echo "Installing systemd services..."
mkdir -p ~/.config/systemd/user

WHISPER_SERVER="$SCRIPT_DIR/whisper.cpp/build/bin/whisper-server"
WHISPER_MODEL_PATH="$SCRIPT_DIR/whisper.cpp/models/ggml-${MODEL}.bin"
PROMPT_FILE="$SCRIPT_DIR/prompt.txt"

sed -e "s|__WHISPER_SERVER__|${WHISPER_SERVER}|g" \
    -e "s|__WHISPER_MODEL__|${WHISPER_MODEL_PATH}|g" \
    -e "s|__PROMPT_FILE__|${PROMPT_FILE}|g" \
    "$SCRIPT_DIR/systemd/whisper-server.service" > ~/.config/systemd/user/whisper-server.service

cp "$SCRIPT_DIR/systemd/ydotoold.service" ~/.config/systemd/user/ydotoold.service

systemctl --user daemon-reload
systemctl --user enable --now ydotoold
systemctl --user enable --now whisper-server

# Symlink scripts
echo "Installing scripts..."
mkdir -p ~/.local/bin
ln -sf "$SCRIPT_DIR/whisper-ptt" ~/.local/bin/whisper-ptt
ln -sf "$SCRIPT_DIR/whisper-ptt-indicator" ~/.local/bin/whisper-ptt-indicator

# Setup keyboard shortcut
echo "Setting up Ctrl+Alt+V shortcut..."
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
    "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ \
    name "Whisper PTT"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ \
    command "$SCRIPT_DIR/whisper-ptt"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ \
    binding '<Ctrl><Alt>v'

echo ""
echo "=== Install complete ==="
echo "  Shortcut: Ctrl+Alt+V (toggle listening)"
echo "  Model: ${MODEL}"
echo "  Logs: cat /tmp/whisper-ptt.log"
echo ""
echo "NOTE: Log out and back in for group changes (input, render, video) to take effect."
echo "NOTE: If gsd-media-keys is not running, start it with: /usr/libexec/gsd-media-keys &"
