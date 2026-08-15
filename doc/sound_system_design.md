# Sierra AGI Sound System: Design & Architecture

This document describes the design, binary specification, and implementation of the Sound (SND) resource parser, multi-mode PCM synthesizer, MIDI exporter, and CSound generator in `flutter_agigame`.

---

## 1. System Overview

The sound subsystem is responsible for:
1. **Parsing** raw Sierra AGI SND binary resources extracted from `VOL.n` archives into strongly typed domain models (`AgiSound`, `ToneChannel`, `AgiNote`, `NoiseChannel`, `AgiNoise`).
2. **Synthesizing** sounds into raw 16-bit Linear PCM audio in three distinct modes:
   - **IBM PC 1-Channel**: Single square wave speaker emulation (Voice 1).
   - **Tandy 1000 / IBM PCjr 3-Voice + Noise**: Authentic Texas Instruments SN76489 / SN76496 sound chip emulation.
   - **Enhanced Synthesizer**: Modern stereo synthesis with selectable waveforms (Sine, Sawtooth, Triangle, Square, PWM), spatial panning, gentle envelope shaping, and Freeverb-based stereo reverberation.
3. **Exporting** to standard audio and music formats:
   - **WAV** (16-bit PCM RIFF container)
   - **Standard MIDI Files** (SMF Format 1 multi-track `.mid`)
   - **CSound Scores & Orchestras** (`.sco` and `.orc`)

```
┌───────────────────────────┐
│     VOL / DIR Files       │
└─────────────┬─────────────┘
              │ AgiResourceLoader.loadSound(n)
              ▼
┌───────────────────────────┐
│       SoundParser         │
└─────────────┬─────────────┘
              │ Produces AgiSound
              ▼
    ┌───────────────────┬───────────────────┬───────────────────┐
    ▼                   ▼                   ▼                   ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌───────────────────┐
│ PcmSynthesizer│ │  WavEncoder   │ │  MidiBuilder  │ │   CSoundBuilder   │
│ (IBM/Tandy/   │ │ (RIFF .wav)   │ │ (SMF .mid)    │ │   (.sco / .orc)   │
│  Enhanced)    │ │               │ │               │                   │
└───────────────┘ └───────────────┘ └───────────────┘ └───────────────────┘
```

---

## 2. Sierra AGI SND Binary Resource Specification

AGI sound resources are stored in `VOL` files with a 4-channel layout designed around the Texas Instruments SN76489 / SN76496 Digital Complex Sound Generator (DCSG).

### 2.1 Header (8 Bytes)

The resource begins with four 16-bit little-endian offsets pointing to the track data for each voice:

| Offset | Field | Description |
|--------|-------|-------------|
| `0x00..0x01` | `voice1Offset` | Start offset of Tone Voice 1 (16-bit LE) |
| `0x02..0x03` | `voice2Offset` | Start offset of Tone Voice 2 (16-bit LE) |
| `0x04..0x05` | `voice3Offset` | Start offset of Tone Voice 3 (16-bit LE) |
| `0x06..0x07` | `noiseOffset`  | Start offset of Noise Channel (16-bit LE) |

- The data for Voice 1 extends from `voice1Offset` to `voice2Offset`.
- The data for Voice 2 extends from `voice2Offset` to `voice3Offset`.
- The data for Voice 3 extends from `voice3Offset` to `noiseOffset`.
- The data for Noise extends from `noiseOffset` to `data.length`.

### 2.2 Tone Channel Note Records (5 Bytes per event)

Each tone channel contains a sequence of 5-byte records:

| Byte | Field | Description |
|------|-------|-------------|
| `0..1` | `duration` | Duration in 1/60th second ticks (16-bit LE). Value `0xFFFF` signals End of Track. |
| `2` | `freqHigh` | Top 6 bits of 10-bit frequency divider: `(data[idx + 2] & 0x3F) << 4` |
| `3` | `freqLow`  | Lower 4 bits of 10-bit frequency divider: `data[idx + 3] & 0x0F` |
| `4` | `attenuation` | Volume level: `0` (maximum volume / 0 dB) to `15` (silence / -∞ dB). |

The combined 10-bit frequency count is:
$$\text{frequencyCount} = ((\text{byte}_2 \ \& \ 0\text{x}3\text{F}) \ll 4) \ | \ (\text{byte}_3 \ \& \ 0\text{x}0\text{F})$$

### 2.3 Noise Channel Records (5 Bytes per event)

| Byte | Field | Description |
|------|-------|-------------|
| `0..1` | `duration` | Duration in 1/60th second ticks (16-bit LE). Value `0xFFFF` signals End of Track. |
| `2` | `unused` | Reserved. |
| `3` | `mode` | Noise generator configuration: <br>• Bit 2 (`& 0x04`): Feedback mode (`0` = Periodic / Linear, `1` = White Noise).<br>• Bits 0–1 (`& 0x03`): Shift frequency divider (`0` = High 0x10, `1` = Medium 0x20, `2` = Low 0x40, `3` = Tone 3 Pitch). |
| `4` | `attenuation` | Volume level: `0` (loudest) to `15` (silence). |

---

## 3. Frequency & Pitch Mathematics

### 3.1 Hardware Master Clock & Divider

The IBM PCjr and Tandy 1000 derive the SN76496 sound chip clock from the NTSC colorburst crystal:
$$f_{\text{crystal}} = 14.3181818\dots \text{ MHz}$$
$$f_{\text{chip}} = \frac{f_{\text{crystal}}}{4} = 3.57954545\dots \text{ MHz}$$

The internal tone generator counts down half-cycles with an internal 16-to-1 prescaler, resulting in a total divisor of $16 \times 2 = 32$:
$$f_{\text{tone}} = \frac{f_{\text{chip}}}{32 \times N} = \frac{111860.78125}{N} \text{ Hz}$$

Where $N$ is the 10-bit frequency count ($1 \le N \le 1023$).

### 3.2 MIDI Note Conversion

In standard 12-Tone Equal Temperament (12-TET with $A_4 = 440 \text{ Hz}$ at MIDI note 69):
$$m = \text{round}\left(69 + 12 \cdot \log_2\left(\frac{f}{440.0}\right)\right)$$

For historical compatibility with early AGI extractors that anchored their formula around $C_2 = 64 \text{ Hz}$ at MIDI note 36:
$$m_{\text{legacy}} = \text{round}\left(36 + 12 \cdot \log_2\left(\frac{f}{64.0}\right)\right)$$

Both formulas are supported via `AgiNote.toMidiNoteNumber({bool useAgiLegacyFormula})`.

### 3.3 Attenuation to Amplitude

The SN76489 attenuation register provides 16 volume steps in logarithmic 2 dB increments:
$$A(i) = \begin{cases} 10^{-2i / 20}, & 0 \le i \le 14 \\ 0.0, & i = 15 \end{cases}$$

---

## 4. Synthesizer Architecture

The `PcmSynthesizer` generates 16-bit linear PCM audio buffers configured by `SynthesizerConfig`:

```
                  ┌───────────────────────────────┐
                  │          AgiSound             │
                  └───────────────┬───────────────┘
                                  │
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
  [Tone Voice 1]           [Tone Voice 2]           [Tone Voice 3]
  (Phase Acc + Wave)       (Phase Acc + Wave)       (Phase Acc + Wave)
         │                        │                        │
         ▼                        ▼                        ▼
  (Pan: 0.35 L)            (Pan: 0.65 R)            (Pan: 0.50 C)
         └────────────────────────┼────────────────────────┘
                                  │
                           [Noise Channel]
                         (15-bit LFSR Noise)
                                  │
                                  ▼
                         ┌─────────────────┐
                         │  Stereo Mixer   │
                         └────────┬────────┘
                                  │
                                  ▼
                         ┌─────────────────┐
                         │ Freeverb Stereo │ (Optional / Enhanced)
                         │   Reverb DSP    │
                         └────────┬────────┘
                                  │
                                  ▼
                         ┌─────────────────┐
                         │ Soft Polynomial │
                         │     Limiter     │
                         └────────┬────────┘
                                  │
                                  ▼
                         ┌─────────────────┐
                         │ 16-bit PCM / WAV│
                         └─────────────────┘
```

### 4.1 Playback Modes

1. **`PcmPlaybackMode.ibmPcSingleChannel`**:
   - Single square wave generator playing Tone Voice 1.
   - Emulates the classic IBM PC 5150 built-in speaker.

2. **`PcmPlaybackMode.tandy3VoiceNoise`**:
   - 3 polyphonic square wave channels + 1 LFSR noise channel.
   - Authentic 15-bit Linear Feedback Shift Register (LFSR) emulation:
     - Periodic noise: Shifts register with feedback bit = bit 0.
     - White noise: Shifts register with feedback bit = bit 0 $\oplus$ bit 1.

3. **`PcmPlaybackMode.enhanced`**:
   - Selectable waveforms:
     - **Square**: Classic chip sound.
     - **Sine**: Pure, soft harmonic tones.
     - **Sawtooth**: Rich, bright retro synthesizer timbre.
     - **Triangle**: Warm, hollow flute-like tones.
     - **PWM**: Dynamic Pulse Width Modulation with $1.8 \text{ Hz}$ LFO.
   - Anti-click and natural decay envelope smoothing (4 ms attack/release ramps with gentle exponential decay over long sustains).
   - Stereo separation: Voices 1, 2, and 3 panned across the stereo soundstage.
   - Freeverb DSP: 8 parallel feedback comb filter pairs + 4 cascaded allpass diffusers with stereo spread.

---

## 5. MIDI Exporter (`MidiBuilder`)

`MidiBuilder` converts an `AgiSound` directly into a Standard MIDI File (SMF Format 1):

- **Header Chunk (`MThd`)**: Format 1, $N+1$ tracks, Division = 60 PPQ (ticks per quarter note).
- **Track 0 (Tempo Track)**:
  - Track name meta event ("AGI Sound Resource $X$").
  - Set Tempo meta event (120 BPM = 500,000 µs/beat).
  - End of Track event (`0xFF 0x2F 0x00`).
- **Tracks 1..N (Voice Tracks)**:
  - Track name ("AGI Voice $Y$").
  - Program change instrument selection.
  - Note-On and Note-Off events with Variable Length Quantity (VLQ) delta timing.
  - Since AGI ticks run at 60 ticks/second and 120 BPM has 120 ticks/second at 60 PPQ, multiplying AGI ticks by 2 ($\text{tick} \times 2$) provides exact 1:1 musical timing.

---

## 6. CSound Score & Orchestra Generator (`CSoundBuilder`)

`CSoundBuilder` produces:
1. **CSound Scores (`.sco`)**:
   - `t 0 3600` score timing (matching 60 ticks/second).
   - Panning instruments `i2`.
   - Voice instruments `i11`, `i12`, `i13`.
   - Noise instruments `i21` (white) and `i31` (periodic).
   - Master reverb mixer `i99`.
2. **CSound Orchestras (`.orc`)**:
   - `tandyOrchestra`: Square waves + SN76489 noise generator.
   - `pwmOrchestra`: Pulse-width modulation + stereo panning + reverb.
   - `synthOrchestra`: FluidSynth SoundFont instrument bridge.
