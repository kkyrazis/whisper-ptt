# Whisper Push-to-Talk

Local speech-to-text that types into any focused application on GNOME Wayland.
Uses whisper.cpp with Intel Arc iGPU (SYCL) acceleration.

## Architecture

```
Hotkey (Ctrl+Alt+V) → whisper-ptt script
  ↓ toggles on/off
rec (sox) → silence detection → audio clip
  ↓ (background)
curl → whisper-server (SYCL GPU, port 8178) → transcribed text
  ↓
ydotool type → typed into focused app
```

## Components

| Component | Purpose | Location |
|-----------|---------|----------|
| whisper-ptt | Main toggle script | `~/.local/bin/whisper-ptt` |
| whisper-server | Persistent whisper.cpp HTTP server | systemd user service |
| ydotoold | Virtual keyboard daemon | systemd user service |
| whisper.cpp | Speech-to-text engine (SYCL build) | `~/projects/whisper.cpp/` |
| Model | ggml-base.en (142MB) | `~/projects/whisper.cpp/models/ggml-base.en.bin` |

## Installed Packages

```bash
# Core
sudo dnf install sox wtype ydotool intel-compute-runtime oneapi-level-zero cmake

# Intel oneAPI Base Toolkit (SYCL compiler + runtime)
sudo dnf install intel-oneapi-base-toolkit

# Build dependencies
sudo dnf install build-essential  # or gcc gcc-c++ make on Fedora
```

## Services

```bash
# whisper-server: keeps model loaded in memory for fast inference
systemctl --user status whisper-server
systemctl --user restart whisper-server

# ydotoold: virtual keyboard daemon (required for ydotool)
systemctl --user status ydotoold

# Service files
~/.config/systemd/user/whisper-server.service
~/.config/systemd/user/ydotoold.service
```

## Configuration

### Hotkey
Set via GNOME custom shortcuts (gsettings):
```bash
# View current binding
gsettings get org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding

# Change binding
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Ctrl><Alt>v'
```

### Voice Commands
| Say | Action | Keybinding |
|-----|--------|------------|
| "enter" / "press enter" / "submit" / "send it" | Press Enter, reset line | Enter |
| "new line" / "newline" | Press Enter | Enter |
| "tab" / "press tab" | Press Tab | Tab |
| "delete" / "undo" / "delete that" / "undo that" | Undo last input | Ctrl+_ |
| "delete line" / "clear line" | Clear entire line | Ctrl+E, Ctrl+U |

### Switching Models
```bash
# Edit the service to change the model path
vim ~/.config/systemd/user/whisper-server.service
# Available models: ggml-base.en.bin (142MB), ggml-small.en.bin (466MB)
systemctl --user daemon-reload
systemctl --user restart whisper-server
```

### Coding Prompt
The server uses `--prompt` to bias recognition toward coding terms.
Edit the prompt in `~/.config/systemd/user/whisper-server.service`.

## Logs / Metrics

```bash
# Current session log (overwritten each session)
cat /tmp/whisper-ptt.log

# Format: [TIME] audio=Xs latency=Yms text="..." cmd="..."
```

## Teardown

### Remove services
```bash
systemctl --user disable --now whisper-server ydotoold
rm ~/.config/systemd/user/whisper-server.service
rm ~/.config/systemd/user/ydotoold.service
systemctl --user daemon-reload
```

### Remove script and shortcut
```bash
rm ~/.local/bin/whisper-ptt
gsettings reset org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding
gsettings reset org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command
gsettings reset org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings '[]'
```

### Remove whisper.cpp
```bash
rm -rf ~/projects/whisper.cpp
```

### Remove udev rule
```bash
sudo rm /etc/udev/rules.d/70-uinput.rules
sudo udevadm control --reload-rules
```

### Uninstall packages
```bash
sudo dnf remove ydotool sox wtype intel-compute-runtime oneapi-level-zero intel-oneapi-base-toolkit cmake
# Remove user from groups
sudo gpasswd -d $USER input
sudo gpasswd -d $USER render
sudo gpasswd -d $USER video
```

## Troubleshooting

- **Segfault on Ctrl+C**: harmless, sox doesn't handle SIGINT cleanly. Use hotkey toggle instead.
- **"Compositor does not support virtual keyboard protocol"**: wtype doesn't work on GNOME. Use ydotool.
- **Shortcuts don't work**: `gsd-media-keys` may not be running or may have crashed. Fix:
  ```bash
  # Check if running
  ps aux | grep gsd-media-keys
  # Restart it
  kill $(pgrep gsd-media-keys) 2>/dev/null; sleep 1; /usr/libexec/gsd-media-keys &
  ```
  This is a known issue on GNOME 49 / Fedora 43 where `gsd-media-keys` crashes silently. If it happens frequently, add to autostart:
  ```bash
  mkdir -p ~/.config/autostart
  cat > ~/.config/autostart/gsd-media-keys.desktop << 'EOF'
  [Desktop Entry]
  Type=Application
  Name=GSD Media Keys
  Exec=/usr/libexec/gsd-media-keys
  X-GNOME-Autostart-Phase=Initialization
  NoDisplay=true
  EOF
  ```
- **Socket errors from ydotool**: ensure ydotoold user service is running and `YDOTOOL_SOCKET` is not set.
- **Slow first transcription**: SYCL kernel JIT compile. Subsequent calls are cached and fast.
