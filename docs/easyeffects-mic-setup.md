# EasyEffects Mic Setup for z13flow

## System Mic Volume

**Critical:** Set system mic input to **30%** before using EasyEffects.

```bash
wpctl set-volume @DEFAULT_SOURCE@ 0.30
```

At 100%, the mic clips at the hardware level before EasyEffects can process it, causing a "blown out" distorted sound.

## Signal Chain

The FlowMic preset uses this chain:

1. **RNNoise** - AI noise suppression
2. **Gate** - Cuts background noise when not speaking
3. **Compressor** - Evens out volume, adds 8dB makeup gain
4. **Limiter** - Prevents peaks above -3dB

## Why 30%?

| Mic Volume | Result |
|------------|--------|
| 100% | Clipping/distortion at hardware level |
| 50% | Still some clipping |
| 30% | Clean signal, no distortion |

The compressor's 8dB makeup gain compensates for the lower input, giving a final output around -14dB RMS (ideal for voice calls).

## Verification

Record and analyze with sox:

```bash
pw-record /tmp/test.wav &
PID=$!
sleep 5
kill $PID
sox /tmp/test.wav -n stats
```

Good values:
- Flat factor: 0.00 (no clipping)
- RMS lev dB: -18 to -12 (good loudness)
- Pk lev dB: -3 or lower (headroom)
