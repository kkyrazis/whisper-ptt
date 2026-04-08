# Whisper PTT – AI Assistant Context

## Overview

Local push-to-talk speech-to-text tool for GNOME Wayland. Captures audio via sox, transcribes via whisper.cpp (Intel iGPU SYCL acceleration), and types into the focused app via ydotool.

## Architecture

```
Hotkey (Ctrl+Alt+V) → whisper-ptt (bash)
  ├── whisper-ptt-indicator (Python, tray icon)
  ├── rec (sox, silence detection) → audio clip
  │     ↓ (background)
  ├── curl → whisper-server (port 8178) → text
  │     ↓
  └── ydotool type → focused app
```

## Key Files

| File | Purpose |
|------|---------|
| `whisper-ptt` | Main script. Toggles listening on/off. Handles recording, transcription, voice commands, typing. |
| `whisper-ptt-indicator` | Python AppIndicator3 script. Shows microphone icon in GNOME top bar while active. |
| `install.sh` | Full install: packages, whisper.cpp SYCL build, systemd services, shortcut. |
| `prompt.txt` | Whisper prompt for biasing recognition toward coding vocabulary. |
| `systemd/whisper-server.service` | Template for the whisper.cpp HTTP server. Placeholders filled by install.sh. |
| `systemd/ydotoold.service` | User service for ydotool's virtual keyboard daemon. |
| `whisper.cpp/` | Git submodule. The speech-to-text engine. |

## Modifying the Service

### Changing the whisper model

1. Download the new model:
   ```bash
   cd whisper.cpp && bash models/download-ggml-model.sh small.en
   ```
2. Update the installed service file (not the template):
   ```bash
   vim ~/.config/systemd/user/whisper-server.service
   # Change the -m flag to point to the new model
   ```
3. Restart:
   ```bash
   systemctl --user daemon-reload
   systemctl --user restart whisper-server
   ```

### Changing the coding vocabulary prompt

1. Edit `prompt.txt` with new terms in natural sentences.
2. Restart the server:
   ```bash
   systemctl --user restart whisper-server
   ```

### Changing the server port

1. Update the port in `~/.config/systemd/user/whisper-server.service` (`--port` flag).
2. Update the `SERVER` variable in `whisper-ptt`.
3. Restart the server:
   ```bash
   systemctl --user daemon-reload
   systemctl --user restart whisper-server
   ```

### Adding voice commands

Voice commands are matched in `whisper-ptt` inside `process_audio()`. The pattern is:
```bash
elif [[ "$LOWER" =~ ^(word|phrase)$ ]]; then
    ydotool key <keycode>:1 <keycode>:0
```
Keycodes are Linux input event codes from `/usr/include/linux/input-event-codes.h`.

### Rebuilding whisper.cpp

After updating the submodule or changing build flags:
```bash
cd whisper.cpp
source /opt/intel/oneapi/setvars.sh --force
rm -rf build
cmake -B build -DGGML_SYCL=ON -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx
cmake --build build --config Release -j$(nproc)
systemctl --user restart whisper-server
```

## Troubleshooting

- **gsd-media-keys crashes**: Custom shortcuts stop working. Restart with `/usr/libexec/gsd-media-keys &`.
- **Orphaned processes**: If toggle doesn't work, `pkill -f whisper-ptt` to clean up.
- **Server not running**: `systemctl --user status whisper-server` to check. Logs: `journalctl --user -u whisper-server`.
- **ydotool socket errors**: Ensure ydotoold user service is running: `systemctl --user status ydotoold`.

## Dependencies

System packages: `sox`, `ydotool`, `intel-compute-runtime`, `oneapi-level-zero`, `cmake`, `intel-oneapi-base-toolkit`, `libappindicator-gtk3`
