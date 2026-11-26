// Sierra SCI0 AdLib software driver (Stage 5a).
//
// Clean-room Dart driver that turns lossless [SciMidiEvent]s into YM3812
// register writes through an [OplRegisterSink]. Behavior is defined by the
// Sierra driver semantics documented in doc/sci_adlib_mt32_audio_plan.md
// (Stage 5) and observed from the reference Sierra driver: voice
// assignment in initTrack, round-robin allocation with oldest-voice
// stealing, sustain pedal, pitch bend, dynamic voice mapping (CC 0x4B),
// velocity enable, offline sequence with master volume, and the register
// programming contract for patch operators, feedback/algorithm, pitch
// (computed equal temperament), and velocity.
//
// The driver depends only on [OplRegisterSink], so tests run against a
// recording fake sink with no chip. [Opl2ChipRegisterSink] adapts a real
// [Opl2Chip] for playback. No audio is generated here; the offline
// audition renderer is a later stage.
//
// Profile design: a per-driver [SciAdlibProfile] decides the voice cap
// (8 for SCI0-early, 9 otherwise). [initTrack] takes the decoded
// [SciMidiTrack] and trusts the track's own header variant and channel
// records for the assignment rules even if they disagree with the profile;
// only the cap comes from the profile. This is deliberate: the variant is
// a per-resource fact, the 8-voice cap is a per-game-version fact.

import 'dart:math' as math;

import 'package:flutter_agigame/audio/opl/opl2_chip.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/sci/engine/sci_midi_track.dart';

/// Sink for YM3812 register writes (address/value are 8-bit values).
///
/// The driver writes only through this interface. [reset] is invoked by
/// [SciAdLibDriver.open] before the open sequence is written.
abstract class OplRegisterSink {
  /// Writes one register ([address], [value], each 0..255).
  void writeRegister(int address, int value);

  /// Resets the sink (chip registers/state, or a test recording).
  void reset();
}

/// [OplRegisterSink] adapter forwarding to a real [Opl2Chip].
final class Opl2ChipRegisterSink implements OplRegisterSink {
  /// The wrapped chip.
  final Opl2Chip chip;

  Opl2ChipRegisterSink(this.chip);

  @override
  void writeRegister(int address, int value) => chip.writeRegister(address, value);

  @override
  void reset() => chip.reset();
}

/// SCI0 driver profile: decides the physical voice cap.
enum SciAdlibProfile {
  /// Early SCI0 games: 8 voices.
  sci0Early,

  /// Late SCI0 (and default): 9 voices.
  sci0Late,
}

/// Modulator register offsets per physical voice (datasheet channel map).
const List<int> _registerOffsets = [0, 1, 2, 8, 9, 10, 16, 17, 18];

/// AdLib play bit in a late-header play mask.
const int _lateAdLibMask = 0x04;

/// AdLib play bit in an early-header byte.
const int _earlyAdLibBit = 0x01;

/// Controller recognizing an all-notes-off request.
const int _ccAllNotesOff = 0x7B;

/// Default patch used by initTrack until a program change arrives.
const int _defaultPatch = 13;

/// Sierra note range clip: notes outside 12..107 are ignored.
const int _minNote = 12;
const int _maxNote = 107;

/// Sierra pitch wheel center.
const int _pitchCenter = 8192;

/// Master volume bounds (0..15).
const int _maxMasterVolume = 15;

/// Mutable per-logical-channel driver state (16 channels).
final class _ChannelState {
  int patch = 0;
  int volume = 63;
  int pan = 64;
  int holdPedal = 0;
  int pitchWheel = _pitchCenter;
  int lastVoice = 0;
  bool enableVelocity = false;
  int mappedVoices = 0;
}

/// Mutable per-voice driver state (9 physical voices).
final class _VoiceState {
  int channel = -1;
  int mappedChannel = -1;
  int note = -1;
  int patch = -1;
  int velocity = 0;
  bool isSustained = false;

  /// Tick at which the current note started (voice age = tick - startTick).
  int startTick = 0;
}

/// Sierra SCI0 AdLib software driver over an [OplRegisterSink].
///
/// Feed it [SciMidiTrack]s and [SciMidiEvent]s; inspect it through the
/// read-only state getters (mapped channel per voice, per-channel mapped
/// voice counts, current patch/volume/pan/hold/pitch-wheel, active note
/// per voice).
final class SciAdLibDriver {
  /// The decoded patch bank.
  final SciAdlibBank bank;

  /// The register sink.
  final OplRegisterSink sink;

  /// Driver profile (voice cap).
  final SciAdlibProfile profile;

  final List<_ChannelState> _channels =
      List<_ChannelState>.generate(16, (_) => _ChannelState());
  final List<_VoiceState> _voices =
      List<_VoiceState>.generate(kOpl2Channels, (_) => _VoiceState());

  int _masterVolume = 15;
  bool _playEnabled = true;

  SciAdLibDriver({
    required this.bank,
    required this.sink,
    this.profile = SciAdlibProfile.sci0Late,
  });

  /// Physical voice cap for this profile (8 early, 9 late).
  int get voiceCap => profile == SciAdlibProfile.sci0Early ? 8 : kOpl2Channels;

  /// Current master volume 0..15.
  int get masterVolume => _masterVolume;

  /// Whether playback is enabled (reference play switch).
  bool get playEnabled => _playEnabled;

  /// Sets playback enable and renews sounding notes, mirroring the
  /// reference playSwitch behavior: when disabled, the switch is stored
  /// and all active notes are rewritten with key off (their velocity
  /// register writes also drop to velocity 0).
  set playEnabled(bool value) {
    _playEnabled = value;
    _renewNotes(-1, value);
  }

  // --- Read-only state for tests/debug. ---

  /// Logical channel mapped to [voice], or -1 when unmapped.
  int voiceMappedChannel(int voice) => _voices[voice].mappedChannel;

  /// Logical channel currently sounding on [voice], or -1.
  int voiceChannel(int voice) => _voices[voice].channel;

  /// Active note on [voice], or -1 when silent.
  int voiceNote(int voice) => _voices[voice].note;

  /// Instrument loaded on [voice], or -1 before the first patch load.
  int voicePatch(int voice) => _voices[voice].patch;

  /// Stored note velocity (0..63) on [voice].
  int voiceVelocity(int voice) => _voices[voice].velocity;

  /// Whether the note on [voice] is held by the sustain pedal.
  bool voiceSustained(int voice) => _voices[voice].isSustained;

  /// Number of voices mapped to [channel].
  int channelMappedVoices(int channel) => _channels[channel].mappedVoices;

  /// Current program/patch for [channel].
  int channelPatch(int channel) => _channels[channel].patch;

  /// Stored channel volume for [channel] (CC 0x07 value >> 1).
  int channelVolume(int channel) => _channels[channel].volume;

  /// Stored pan for [channel] (64 is center).
  int channelPan(int channel) => _channels[channel].pan;

  /// Hold pedal state for [channel] (0 is released).
  int channelHoldPedal(int channel) => _channels[channel].holdPedal;

  /// Pitch wheel for [channel] (8192 is center).
  int channelPitchWheel(int channel) => _channels[channel].pitchWheel;

  /// Whether [channel] responds to note velocity.
  bool channelEnableVelocity(int channel) =>
      _channels[channel].enableVelocity;

  /// Resets all channel/voice state to reference defaults and runs the
  /// open register sequence (0xBD=0, 0x08=0, 0x01=0x20).
  ///
  /// The sink is reset first so the written sequence is what the consumer
  /// observes. Channel state returns to its pre-initTrack defaults
  /// (patch 0; initTrack sets patch 13).
  void open() {
    _resetState();
    sink.reset();
    sink.writeRegister(0xBD, 0);
    sink.writeRegister(0x08, 0);
    sink.writeRegister(0x01, 0x20);
  }

  void _resetState() {
    for (final c in _channels) {
      c.patch = 0;
      c.volume = 63;
      c.pan = 64;
      c.holdPedal = 0;
      c.pitchWheel = _pitchCenter;
      c.lastVoice = 0;
      c.enableVelocity = false;
      c.mappedVoices = 0;
    }
    for (final v in _voices) {
      v.channel = -1;
      v.mappedChannel = -1;
      v.note = -1;
      v.patch = -1;
      v.velocity = 0;
      v.isSustained = false;
      v.startTick = 0;
    }
    _masterVolume = 15;
    _playEnabled = true;
  }

  /// Applies SCI track-header voice assignment for [track].
  ///
  /// Caps rule: a nonzero flags byte disables assignment (early headers
  /// accept only 0; late headers accept only 2) and the method returns
  /// BEFORE touching any voice or channel state, mirroring the reference
  /// driver's early return. Callers observe no assignment change in that
  /// case.
  ///
  /// Otherwise voices are reset (channel/mapped/note -1, patch 13,
  /// velocity 0, not sustained, start tick 0) and every channel gets
  /// patch 13 with mappedVoices 0, then:
  /// - Late: a channel with the AdLib mask bit 0x04 and a positive
  ///   requested-voice count gets that many voices assigned (capped by
  ///   [voiceCap]; excess requests are silently unassigned).
  /// - Early: a channel plays for AdLib when bit 0x01 is set; it gets
  ///   its upper-nibble voice count assigned sequentially unless the
  ///   control flag (bit 3) is set or the count is 0x0F. Channels with
  ///   only the control flag set receive no voices.
  void initTrack(SciMidiTrack track) {
    final flags = track.flagsByte;
    final early = track.variant == SciMidiHeaderVariant.early;
    if (flags != 0 && (early || flags != 2)) {
      // No assignment, and no state reset either (reference parity).
      return;
    }

    for (final v in _voices) {
      v.channel = -1;
      v.mappedChannel = -1;
      v.note = -1;
      v.patch = _defaultPatch;
      v.velocity = 0;
      v.isSustained = false;
      v.startTick = 0;
    }
    for (final c in _channels) {
      c.patch = _defaultPatch;
      c.mappedVoices = 0;
    }

    SciMidiChannelInit? channelAt(int i) =>
        i < track.channels.length ? track.channels[i] : null;

    if (!early) {
      for (var i = 0; i < 16; i++) {
        final init = channelAt(i);
        if (init == null) continue;
        if ((init.playMask & _lateAdLibMask) != 0 && init.requestedVoices > 0) {
          _assignVoices(i, init.requestedVoices);
        }
      }
    } else {
      var numVoices = 0;
      for (var i = 0; i < 16; i++) {
        final init = channelAt(i);
        if (init == null) continue;
        if ((init.playMask & _earlyAdLibBit) != 0) {
          var num = init.requestedVoices;
          if (!init.hasControlFlag && num > 0 && num != 0x0F) {
            while (num > 0) {
              num--;
              if (numVoices >= voiceCap) continue;
              _voices[numVoices++].mappedChannel = i;
              _channels[i].mappedVoices++;
            }
          }
        } else if (init.isControlChannel) {
          // Control channel found; AdLib assigns it no voices.
        }
      }
    }
  }

  /// Assigns up to [voices] unmapped physical voices to [channel].
  void _assignVoices(int channel, int voices) {
    for (var i = 0; i < voiceCap; i++) {
      if (_voices[i].mappedChannel == -1) {
        // A note sounding on an unmapped voice (late-SCI1.x only in the
        // reference) is stopped before remapping.
        if (_voices[i].note != -1) _voiceOff(i);
        _voices[i].mappedChannel = channel;
        _channels[channel].mappedVoices++;
        if (--voices == 0) return;
      }
    }
    // Excess requests are silently unassigned for SCI0 (extraVoices is a
    // SCI1 concept and is not tracked here).
  }

  /// Releases [voices] voices from [channel]: free mapped voices first,
  /// then sounding mapped voices (via [_voiceOff]), in voice order.
  void _releaseVoices(int channel, int voices) {
    for (var i = 0; i < voiceCap; i++) {
      if (_voices[i].mappedChannel == channel && _voices[i].note == -1) {
        _voices[i].mappedChannel = -1;
        _channels[channel].mappedVoices--;
        if (--voices == 0) return;
      }
    }
    for (var i = 0; i < voiceCap; i++) {
      if (_voices[i].mappedChannel == channel) {
        _voiceOff(i);
        _voices[i].mappedChannel = -1;
        _channels[channel].mappedVoices--;
        if (--voices == 0) return;
      }
    }
  }

  /// Dynamic voice mapping (CC 0x4B): grows or shrinks [channel]'s mapped
  /// voice count toward [voices]. Donating freed voices to other channels
  /// is a SCI1 concept; for SCI0 the outcome is equivalent to the
  /// simplified assign/release above.
  void _voiceMapping(int channel, int voices) {
    var curVoices = 0;
    for (var i = 0; i < voiceCap; i++) {
      if (_voices[i].mappedChannel == channel) curVoices++;
    }
    if (curVoices < voices) {
      _assignVoices(channel, voices - curVoices);
    } else if (curVoices > voices) {
      _releaseVoices(channel, curVoices - voices);
    }
  }

  /// Entry point for sequencer events. Channel 15 is not special-cased:
  /// cues are filtered by the sequencer, and a note on an unmapped
  /// channel simply finds no voice.
  void handleEvent(SciMidiEvent event) {
    switch (event.kind) {
      case SciMidiEventKind.noteOn:
        if (event.channel < 0 || event.channel > 15) return;
        // The model normalizes velocity-0 note-ons to note-off; guard to
        // keep the reference noteOn semantics anyway.
        if (event.data2 == 0) {
          _noteOff(event.channel, event.data1);
        } else {
          _noteOn(event.channel, event.data1, event.data2, event.tick);
        }
      case SciMidiEventKind.noteOff:
        if (event.channel < 0 || event.channel > 15) return;
        _noteOff(event.channel, event.data1);
      case SciMidiEventKind.programChange:
        if (event.channel < 0 || event.channel > 15) return;
        _channels[event.channel].patch = event.data1;
      case SciMidiEventKind.controlChange:
        if (event.channel < 0 || event.channel > 15) return;
        _controlChange(event.channel, event.data1, event.data2);
      case SciMidiEventKind.pitchBend:
        if (event.channel < 0 || event.channel > 15) return;
        _channels[event.channel].pitchWheel = event.pitchBendValue;
        _renewNotes(event.channel, true);
      case SciMidiEventKind.polyPressure:
      case SciMidiEventKind.channelPressure:
      case SciMidiEventKind.sysEx:
      case SciMidiEventKind.system:
      case SciMidiEventKind.endOfTrack:
        // The original Sierra driver ignores aftertouch entirely, and
        // system/SysEx/end-of-track carry no voice state in SCI0.
        break;
    }
  }

  void _controlChange(int channel, int controller, int value) {
    final c = _channels[channel];
    switch (controller) {
      case 0x07:
        c.volume = value >> 1;
        _renewNotes(channel, true);
      case 0x0A:
        // Pan is stored for future stereo; the mono chip has no audible
        // pan, but the renewal keeps observable state consistent.
        c.pan = value;
        _renewNotes(channel, true);
      case 0x40:
        c.holdPedal = value;
        if (value == 0) {
          for (var i = 0; i < kOpl2Channels; i++) {
            if (_voices[i].channel == channel && _voices[i].isSustained) {
              _voiceOff(i);
            }
          }
        }
      case 0x4B:
        _voiceMapping(channel, value);
      case 0x4E:
        c.enableVelocity = value != 0;
      case _ccAllNotesOff:
        for (var i = 0; i < kOpl2Channels; i++) {
          if (_voices[i].channel == channel && _voices[i].note != -1) {
            _voiceOff(i);
          }
        }
      default:
        break;
    }
  }

  void _noteOn(int channel, int note, int velocity, int tick) {
    velocity >>= 1;
    if (note < _minNote || note > _maxNote) return;

    for (var i = 0; i < kOpl2Channels; i++) {
      if (_voices[i].channel == channel && _voices[i].note == note) {
        _voiceOff(i);
        _voiceOn(i, note, velocity, tick);
        return;
      }
    }

    final voice = _findVoice(channel, tick);
    if (voice == -1) return;
    _voiceOn(voice, note, velocity, tick);
  }

  void _noteOff(int channel, int note) {
    for (var i = 0; i < kOpl2Channels; i++) {
      if (_voices[i].channel == channel && _voices[i].note == note) {
        if (_channels[channel].holdPedal != 0) {
          _voices[i].isSustained = true;
        } else {
          _voiceOff(i);
        }
        return;
      }
    }
  }

  /// Round-robin allocation from the channel's last voice across voices
  /// mapped to [channel]; falls back to stealing the oldest sounding
  /// mapped voice, but only when some mapped note is strictly older than
  /// the current tick (same-tick notes are never stolen).
  int _findVoice(int channel, int tick) {
    var voice = -1;
    var oldestVoice = -1;
    var oldestAge = 0;

    for (var i = 0; i < kOpl2Channels; i++) {
      final v = (_channels[channel].lastVoice + i + 1) % kOpl2Channels;
      if (_voices[v].mappedChannel == channel) {
        if (_voices[v].note == -1) {
          voice = v;
          _voices[voice].channel = channel;
          break;
        }
        final age = tick - _voices[v].startTick;
        if (age >= oldestAge) {
          oldestAge = age;
          oldestVoice = v;
        }
      }
    }

    if (voice == -1) {
      if (oldestAge == 0) return -1;
      _voiceOff(oldestVoice);
      voice = oldestVoice;
      _voices[voice].channel = channel;
    }

    _channels[channel].lastVoice = voice;
    return voice;
  }

  void _voiceOn(int voice, int note, int velocity, int tick) {
    final channel = _voices[voice].channel;
    final patch = _channels[channel].patch;
    _voices[voice].startTick = tick;

    if (patch != _voices[voice].patch && _playEnabled) {
      _setPatch(voice, patch);
    }
    _voices[voice].velocity = velocity;
    _setNote(voice, note, true);
  }

  void _voiceOff(int voice) {
    _voices[voice].isSustained = false;
    _setNote(voice, _voices[voice].note, false);
    _voices[voice].note = -1;
  }

  /// Rewrites pitch (and velocity) for active notes on [channel], or all
  /// channels when [channel] is -1, forcing key state to [key].
  void _renewNotes(int channel, bool key) {
    for (var i = 0; i < kOpl2Channels; i++) {
      if ((channel == -1 || _voices[i].channel == channel) &&
          _voices[i].note != -1) {
        _setNote(i, _voices[i].note, key);
      }
    }
  }

  /// Sets master volume (clamped to 0..15) and renews all active notes.
  void setMasterVolume(int volume) {
    _masterVolume = volume.clamp(0, _maxMasterVolume);
    _renewNotes(-1, true);
  }

  /// Keys off every sounding voice.
  void allNotesOff() {
    for (var i = 0; i < kOpl2Channels; i++) {
      if (_voices[i].note != -1) _voiceOff(i);
    }
  }

  // --- Register programming. ---

  SciAdlibInstrument _instrumentFor(int patch) {
    if (patch < 0 || patch >= bank.instrumentCount) return bank.instruments[0];
    return bank.instruments[patch];
  }

  void _setPatch(int voice, int patch) {
    // Invalid patch numbers fall back to instrument 0 (reference warning
    // path, observable substitution kept).
    if (patch < 0 || patch >= bank.instrumentCount) patch = 0;
    _voices[voice].patch = patch;
    final instrument = bank.instruments[patch];
    final base = _registerOffsets[voice];
    _setOperator(base, instrument.operator0);
    _setOperator(base + 3, instrument.operator1);
    sink.writeRegister(
      0xC0 + voice,
      (instrument.modulator.feedback << 1) | instrument.modulator.algorithm,
    );
  }

  void _setOperator(int regOffset, SciAdlibOperator op) {
    sink.writeRegister(
      0x40 + regOffset,
      (op.kbScaleLevel << 6) | op.totalLevel,
    );
    sink.writeRegister(
      0x60 + regOffset,
      (op.attackRate << 4) | op.decayRate,
    );
    sink.writeRegister(
      0x80 + regOffset,
      (op.sustainLevel << 4) | op.releaseRate,
    );
    // Stage 3 stores the flag fields as raw bytes; the reference relies
    // on them being 0/1, so mask to boolean here to be safe.
    sink.writeRegister(
      0x20 + regOffset,
      (op.amplitudeMod != 0 ? 0x80 : 0) |
          (op.vibrato != 0 ? 0x40 : 0) |
          (op.envelopeType != 0 ? 0x20 : 0) |
          (op.kbScaleRate != 0 ? 0x10 : 0) |
          op.frequencyMult,
    );
    sink.writeRegister(0xE0 + regOffset, op.waveForm);
  }

  void _setNote(int voice, int note, bool keyOn) {
    final channel = _voices[voice].channel;
    final pitchWheel = channel >= 0 && channel < 16
        ? _channels[channel].pitchWheel
        : _pitchCenter;
    // Sierra bend is about +/-12 semitones across the wheel range.
    final bendSemitones = (pitchWheel - _pitchCenter) / _pitchCenter * 12;
    final effectiveNote = note + bendSemitones;
    final freq = 440 * math.pow(2, (effectiveNote - 69) / 12);

    var block = (effectiveNote ~/ 12) - 1;
    if (block < 0) block = 0;
    if (block > 7) block = 7;
    var fnum = (freq * math.pow(2, 20 - block) / kOpl2SampleRate).round();
    while (fnum > 1023 && block < 7) {
      block++;
      fnum >>= 1;
    }
    if (fnum < 0) fnum = 0;
    if (fnum > 1023) fnum = 1023;

    _voices[voice].note = note;
    sink.writeRegister(0xA0 + voice, fnum & 0xFF);
    sink.writeRegister(
      0xB0 + voice,
      (keyOn ? 0x20 : 0) | (block << 2) | ((fnum >> 8) & 0x03),
    );
    _setVelocity(voice);
  }

  /// SCI0 velocity: master-volume weight times the instrument note
  /// velocity (note velocity when enabled, otherwise the inverse of the
  /// operator total level), scaled by 15.
  int _calcVelocity(int voice, int op) {
    var velocity = _masterVolume;
    if (velocity > 0) velocity += 3;
    if (velocity > 15) velocity = 15;
    final channel = _voices[voice].channel;
    final instrument = _instrumentFor(_voices[voice].patch);
    final totalLevel =
        op == 1 ? instrument.operator1.totalLevel : instrument.operator0.totalLevel;
    final noteVelocity = channel >= 0 && channel < 16
        ? _channels[channel].enableVelocity
        : false;
    final insVelocity = noteVelocity
        ? _voices[voice].velocity
        : 63 - totalLevel;
    return velocity * insVelocity ~/ 15;
  }

  void _setVelocity(int voice) {
    final instrument = _instrumentFor(_voices[voice].patch);
    final base = _registerOffsets[voice];
    sink.writeRegister(
      0x40 + base + 3,
      _velocityRegValue(voice, 1, instrument.operator1.kbScaleLevel),
    );
    if (instrument.modulator.algorithm == 1) {
      sink.writeRegister(
        0x40 + base,
        _velocityRegValue(voice, 0, instrument.operator0.kbScaleLevel),
      );
    }
  }

  int _velocityRegValue(int voice, int op, int kbScaleLevel) {
    var velocity = _calcVelocity(voice, op);
    if (!_playEnabled) velocity = 0;
    return (kbScaleLevel << 6) | (63 - velocity);
  }
}
