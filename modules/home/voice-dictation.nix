{ pkgs, lib, ... }:
let
  # Push-to-talk voice dictation script using whisper-cpp + wtype
  # Press keybinding once to start recording, again to stop and transcribe.
  # Transcribed text is typed into the focused window via wtype.
  voiceDictation = pkgs.writeShellScriptBin "voice-dictation" ''
    set -euo pipefail

    MODEL_DIR="$HOME/.local/share/whisper-models"
    MODEL_NAME="ggml-base.en.bin"
    MODEL_PATH="$MODEL_DIR/$MODEL_NAME"
    RECORDING_DIR="/tmp/voice-dictation"
    PID_FILE="$RECORDING_DIR/recording.pid"
    AUDIO_FILE="$RECORDING_DIR/recording.wav"

    mkdir -p "$RECORDING_DIR" "$MODEL_DIR"

    # Download model on first use
    if [ ! -f "$MODEL_PATH" ]; then
      ${pkgs.libnotify}/bin/notify-send -u normal "Voice Dictation" "Downloading whisper model (base.en)... This only happens once."
      ${pkgs.whisper-cpp}/bin/whisper-cpp-download-ggml-model base.en "$MODEL_DIR"
      if [ ! -f "$MODEL_PATH" ]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Voice Dictation" "Failed to download model."
        exit 1
      fi
      ${pkgs.libnotify}/bin/notify-send -u normal "Voice Dictation" "Model downloaded successfully."
    fi

    if [ -f "$PID_FILE" ]; then
      # Stop recording
      RECORD_PID=$(cat "$PID_FILE")
      rm -f "$PID_FILE"

      if kill -0 "$RECORD_PID" 2>/dev/null; then
        kill "$RECORD_PID" 2>/dev/null || true
        wait "$RECORD_PID" 2>/dev/null || true
      fi

      ${pkgs.libnotify}/bin/notify-send -t 1500 "Voice Dictation" "Transcribing..."

      if [ ! -f "$AUDIO_FILE" ]; then
        ${pkgs.libnotify}/bin/notify-send -u critical "Voice Dictation" "No audio recorded."
        exit 1
      fi

      # Transcribe with whisper-cpp (output plain text, no timestamps)
      TRANSCRIPT=$(${pkgs.whisper-cpp}/bin/whisper-cli \
        --model "$MODEL_PATH" \
        --file "$AUDIO_FILE" \
        --output-txt \
        --no-timestamps \
        --threads 4 \
        2>/dev/null | sed '/^$/d' | sed 's/^[[:space:]]*//')

      rm -f "$AUDIO_FILE"

      if [ -n "$TRANSCRIPT" ]; then
        # Type the transcribed text into the focused window
        ${pkgs.wtype}/bin/wtype -d 10 -- "$TRANSCRIPT"
        ${pkgs.libnotify}/bin/notify-send -t 2000 "Voice Dictation" "Typed: $(echo "$TRANSCRIPT" | head -c 80)..."
      else
        ${pkgs.libnotify}/bin/notify-send -u normal "Voice Dictation" "No speech detected."
      fi
    else
      # Start recording
      rm -f "$AUDIO_FILE"

      # Record audio using sox (16kHz mono WAV for whisper)
      ${pkgs.sox}/bin/rec -r 16000 -c 1 -b 16 "$AUDIO_FILE" &
      echo $! > "$PID_FILE"

      ${pkgs.libnotify}/bin/notify-send -t 1500 "Voice Dictation" "Recording... Press again to stop."
    fi
  '';
in
lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  home.packages = [
    voiceDictation
    pkgs.whisper-cpp
    pkgs.wtype
  ];
}
