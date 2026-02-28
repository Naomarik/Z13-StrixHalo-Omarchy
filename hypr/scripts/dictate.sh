#!/bin/bash
# Simple toggle dictation - Super+D to start, Super+D to stop
# This is the fallback/alternative to the daemon

PID_FILE="/tmp/dictate.pid"
AUDIO_FILE="/tmp/dictate_recording.wav"

if [ -f "$PID_FILE" ]; then
    # STOP RECORDING
    kill -INT $(cat "$PID_FILE") 2>/dev/null
    rm -f "$PID_FILE"
    pkill -RTMIN+11 waybar  # Update dictation indicator
    sleep 0.5
    
    # Check file
    if [ ! -f "$AUDIO_FILE" ] || [ $(stat -c%s "$AUDIO_FILE") -lt 500 ]; then
        notify-send "❌ Dictation" "Recording failed or too short"
        rm -f "$AUDIO_FILE"
        exit 1
    fi
    
    # Transcribe (in background for responsiveness)
    (
        # Change MODEL here: base.en (fast) | small.en (better) | medium.en (best)
        MODEL="medium.en"
        notify-send "🤖 Dictation" "Transcribing with $MODEL..."
        TEXT=$(~/whisper.cpp/build/bin/whisper-cli -m ~/whisper.cpp/models/ggml-$MODEL.bin -f "$AUDIO_FILE" -np -nt -t 8 2>/dev/null)
        
        # Remove leading newline that whisper-cli adds
        TEXT="${TEXT#$'\n'}"
        
        if [ -n "$TEXT" ]; then
            echo "$TEXT" | wl-copy
            
            # Check if active window is Emacs
            ACTIVE_WINDOW=$(hyprctl activewindow -j | jq -r '.class')
            if [[ "$ACTIVE_WINDOW" =~ [Ee]macs ]]; then
                # Use 'p' to paste in Emacs (works in normal mode)
                wtype p
            else
                # Use Ctrl+Shift+V for other apps
                wtype -M ctrl -M shift v -m shift -m ctrl
            fi
            
            notify-send "✅ Dictation" "$TEXT"
        else
            notify-send "❌ Dictation" "No speech detected"
        fi
        rm -f "$AUDIO_FILE"
    ) &
else
    # START RECORDING
    rm -f "$AUDIO_FILE"
    notify-send "🎤 Dictation" "Recording... Press Super+D to stop"
    
    ffmpeg -f pulse -i @DEFAULT_SOURCE@ -acodec pcm_s16le -ar 16000 -ac 1 -y "$AUDIO_FILE" </dev/null >/dev/null 2>&1 &
    echo $! > "$PID_FILE"
    pkill -RTMIN+11 waybar  # Update dictation indicator
fi
