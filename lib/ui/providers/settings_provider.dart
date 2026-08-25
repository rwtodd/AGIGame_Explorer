import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/models/user_settings.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

/// Riverpod provider for global user settings.
final settingsProvider =
    NotifierProvider<SettingsNotifier, AgiUserSettings>(SettingsNotifier.new);

/// Manages and persists global audio-visual settings.
class SettingsNotifier extends Notifier<AgiUserSettings> {
  final File? _customConfigFile;
  AgiUserSettings _fallbackState = const AgiUserSettings();

  SettingsNotifier({File? configFile}) : _customConfigFile = configFile;

  @override
  AgiUserSettings build() {
    Future.microtask(() => loadSettings());
    return _fallbackState;
  }

  @visibleForTesting
  @override
  AgiUserSettings get state {
    try {
      return super.state;
    } catch (_) {
      return _fallbackState;
    }
  }

  @override
  set state(AgiUserSettings value) {
    try {
      super.state = value;
    } catch (_) {
      _fallbackState = value;
    }
  }

  File? _getConfigFile() {
    if (_customConfigFile != null) return _customConfigFile;

    try {
      String? configDirPath;
      if (Platform.isMacOS || Platform.isLinux) {
        final home = Platform.environment['HOME'];
        if (home != null && home.isNotEmpty) {
          configDirPath = '$home/.config/flutter_agigame';
        }
      } else if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'];
        if (appData != null && appData.isNotEmpty) {
          configDirPath = '$appData/flutter_agigame';
        }
      }

      if (configDirPath != null) {
        final dir = Directory(configDirPath);
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        return File('$configDirPath/settings.json');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Warning: unable to resolve config file path: $e');
      }
    }
    return null;
  }

  /// Loads saved user preferences from JSON file.
  Future<void> loadSettings() async {
    try {
      final file = _getConfigFile();
      if (file != null && file.existsSync()) {
        final jsonStr = await file.readAsString();
        final Map<String, dynamic> json = jsonDecode(jsonStr);
        state = AgiUserSettings.fromJson(json);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Warning: failed to load user settings from disk: $e');
      }
    }
  }

  Future<void>? _pendingSave;

  /// Saves current state to disk asynchronously with sequential write queue and atomic rename.
  Future<void> saveSettings() {
    _pendingSave = (_pendingSave ?? Future.value()).then((_) async {
      try {
        final file = _getConfigFile();
        if (file != null) {
          final jsonStr = const JsonEncoder.withIndent('  ').convert(state.toJson());
          final tmpFile = File('${file.path}.tmp');
          await tmpFile.writeAsString(jsonStr, flush: true);
          if (tmpFile.existsSync()) {
            await tmpFile.rename(file.path);
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Warning: failed to persist user settings to disk: $e');
        }
      }
    });
    return _pendingSave!;
  }

  Future<void> _saveSettings() => saveSettings();

  /// Updates display settings and triggers disk save.
  void updateDisplay({
    bool? correctAspectRatio,
    bool? strictIntegerScaling,
    bool? showCrtShader,
    bool? showPixelGrid,
    bool? renderBlackTextBackgrounds,
    AgiPictureRenderMode? renderMode,
  }) {
    state = state.copyWith(
      display: state.display.copyWith(
        correctAspectRatio: correctAspectRatio,
        strictIntegerScaling: strictIntegerScaling,
        showCrtShader: showCrtShader,
        showPixelGrid: showPixelGrid,
        renderBlackTextBackgrounds: renderBlackTextBackgrounds,
        renderMode: renderMode,
      ),
    );
    _saveSettings();
  }

  /// Updates audio sound mode.
  void setSoundMode(AgiSoundMode mode) {
    state = state.copyWith(
      audio: state.audio.copyWith(soundMode: mode),
    );
    _saveSettings();
  }

  /// Updates synthesizer DSP parameters.
  void setSynthesizerConfig(SynthesizerConfig config) {
    AgiSoundMode soundMode = state.audio.soundMode;
    if (config.mode == PcmPlaybackMode.ibmPcSingleChannel) {
      soundMode = AgiSoundMode.ibmPc;
    } else if (config.mode == PcmPlaybackMode.tandy3VoiceNoise) {
      soundMode = AgiSoundMode.pcJr;
    } else if (config.mode == PcmPlaybackMode.enhanced) {
      soundMode = AgiSoundMode.enhanced;
    }

    state = state.copyWith(
      audio: state.audio.copyWith(
        soundMode: soundMode,
        waveform: config.waveform,
        enableReverb: config.enableReverb,
        reverbMix: config.reverbMix,
        masterVolume: config.masterVolume,
      ),
    );
    _saveSettings();
  }

  /// Updates master volume.
  void setMasterVolume(double volume) {
    state = state.copyWith(
      audio: state.audio.copyWith(masterVolume: volume.clamp(0.0, 1.0)),
    );
    _saveSettings();
  }
}
