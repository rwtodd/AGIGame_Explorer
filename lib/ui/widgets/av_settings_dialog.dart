import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/models/user_settings.dart';
import 'package:flutter_agigame/ui/providers/settings_provider.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

/// Pre-launch and global Audio-Visual Settings configuration dialog.
class AvSettingsDialog extends ConsumerStatefulWidget {
  final AgiResourceLoader? resourceLoader;
  final AgiGameEngine? engine;

  const AvSettingsDialog({
    super.key,
    this.resourceLoader,
    this.engine,
  });

  /// Displays the modal Audio-Visual Settings dialog.
  static Future<void> show(
    BuildContext context, {
    AgiResourceLoader? resourceLoader,
    AgiGameEngine? engine,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => AvSettingsDialog(
        resourceLoader: resourceLoader,
        engine: engine,
      ),
    );
  }

  @override
  ConsumerState<AvSettingsDialog> createState() => _AvSettingsDialogState();
}

class _AvSettingsDialogState extends ConsumerState<AvSettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AgiSoundPlayer? _previewPlayer;
  bool _isPlayingPreview = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _previewPlayer = AgiSoundPlayer();
    _previewPlayer!.onFinished = () {
      if (mounted) {
        setState(() {
          _isPlayingPreview = false;
        });
      }
    };
  }

  @override
  void dispose() {
    _previewPlayer?.stop();
    _previewPlayer?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// Synthesizes and plays a preview fanfare or sample sound using active audio settings.
  Future<void> _playTestSound(AgiAudioSettings audioSettings) async {
    if (_previewPlayer == null) return;

    if (_isPlayingPreview) {
      _previewPlayer!.stop();
      setState(() {
        _isPlayingPreview = false;
      });
      return;
    }

    AgiSound soundToPlay;
    if (widget.resourceLoader != null &&
        widget.resourceLoader!.presentSoundNumbers.isNotEmpty) {
      final soundNum = widget.resourceLoader!.presentSoundNumbers.first;
      soundToPlay = widget.resourceLoader!.loadSound(soundNum);
    } else if (widget.engine?.resourceLoader != null &&
        widget.engine!.resourceLoader!.presentSoundNumbers.isNotEmpty) {
      final soundNum = widget.engine!.resourceLoader!.presentSoundNumbers.first;
      soundToPlay = widget.engine!.resourceLoader!.loadSound(soundNum);
    } else {
      soundToPlay = _generatePreviewFanfare();
    }

    final config = audioSettings.toSynthesizerConfig();
    setState(() {
      _isPlayingPreview = true;
    });

    try {
      await _previewPlayer!.play(soundToPlay, config: config);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPlayingPreview = false;
        });
      }
    }
  }

  AgiSound _generatePreviewFanfare() {
    final track0 = ToneChannel(notes: const [
      AgiNote(startTime: 0, duration: 12, frequencyCount: 852, attenuation: 2), // C4
      AgiNote(startTime: 12, duration: 12, frequencyCount: 676, attenuation: 2), // E4
      AgiNote(startTime: 24, duration: 12, frequencyCount: 569, attenuation: 2), // G4
      AgiNote(startTime: 36, duration: 30, frequencyCount: 426, attenuation: 1), // C5
      AgiNote(startTime: 66, duration: 6, frequencyCount: 0, attenuation: 15),   // rest
    ]);
    final track1 = ToneChannel(notes: const [
      AgiNote(startTime: 0, duration: 24, frequencyCount: 1704, attenuation: 3), // C3
      AgiNote(startTime: 24, duration: 24, frequencyCount: 1138, attenuation: 3), // G3
      AgiNote(startTime: 48, duration: 24, frequencyCount: 852, attenuation: 2),  // C4
    ]);
    final track2 = ToneChannel(notes: const [
      AgiNote(startTime: 0, duration: 12, frequencyCount: 0, attenuation: 15),
      AgiNote(startTime: 12, duration: 12, frequencyCount: 852, attenuation: 3),
      AgiNote(startTime: 24, duration: 12, frequencyCount: 676, attenuation: 3),
      AgiNote(startTime: 36, duration: 30, frequencyCount: 569, attenuation: 2),
      AgiNote(startTime: 66, duration: 6, frequencyCount: 0, attenuation: 15),
    ]);

    return AgiSound(
      voices: [track0, track1, track2],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Dialog(
      backgroundColor: AgiTheme.egaDarkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AgiTheme.egaBorder, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 620,
          maxHeight: 680,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _buildAudioTab(settings.audio, notifier),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _buildVideoTab(settings.display, notifier),
                  ),
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AgiTheme.egaCyan),
            ),
            child: const Icon(Icons.tune, color: AgiTheme.egaCyan, size: 18),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AUDIO-VISUAL CONFIGURATION',
                  style: TextStyle(
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.0,
                    color: AgiTheme.egaWhite,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Graphics, Sound Hardware Emulation, and Shaders',
                  style: TextStyle(
                    fontSize: 11,
                    color: AgiTheme.egaMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AgiTheme.egaMuted),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFF131D31),
      child: TabBar(
        controller: _tabController,
        indicatorColor: AgiTheme.egaCyan,
        labelColor: AgiTheme.egaCyan,
        unselectedLabelColor: AgiTheme.egaMuted,
        labelStyle: const TextStyle(
          fontFamily: 'Courier',
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        tabs: const [
          Tab(icon: Icon(Icons.music_note, size: 16), text: 'Audio & Synth'),
          Tab(icon: Icon(Icons.monitor, size: 16), text: 'Video & Display'),
        ],
      ),
    );
  }

  // ===========================================================================
  // Audio Tab
  // ===========================================================================

  Widget _buildAudioTab(AgiAudioSettings audio, SettingsNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('SOUND OUTPUT HARDWARE'),
        const SizedBox(height: 10),
        _buildSoundModeOption(
          mode: AgiSoundMode.pcJr,
          title: 'PCjr / Tandy 1000 3-Voice + Noise',
          subtitle: 'Authentic 3-tone + noise SN76489 sound chip (Standard Sierra AGI)',
          icon: Icons.volume_up,
          isSelected: audio.soundMode == AgiSoundMode.pcJr,
          onTap: () {
            notifier.setSoundMode(AgiSoundMode.pcJr);
            widget.engine?.setSoundMode(AgiSoundMode.pcJr);
          },
        ),
        const SizedBox(height: 8),
        _buildSoundModeOption(
          mode: AgiSoundMode.ibmPc,
          title: 'IBM PC 1-Channel Internal Speaker',
          subtitle: 'Authentic 1-channel square wave speaker (Voice 1 only)',
          icon: Icons.speaker,
          isSelected: audio.soundMode == AgiSoundMode.ibmPc,
          onTap: () {
            notifier.setSoundMode(AgiSoundMode.ibmPc);
            widget.engine?.setSoundMode(AgiSoundMode.ibmPc);
          },
        ),
        const SizedBox(height: 8),
        _buildSoundModeOption(
          mode: AgiSoundMode.enhanced,
          title: 'Enhanced Mode (Modern DSP Synthesizer)',
          subtitle: 'Multi-waveform synth with pulse-width modulation and DSP room reverb',
          icon: Icons.auto_awesome,
          isSelected: audio.soundMode == AgiSoundMode.enhanced,
          onTap: () {
            notifier.setSoundMode(AgiSoundMode.enhanced);
            widget.engine?.setSoundMode(AgiSoundMode.enhanced);
          },
        ),
        const SizedBox(height: 8),
        _buildSoundModeOption(
          mode: AgiSoundMode.off,
          title: 'Mute Sound (Off)',
          subtitle: 'Disable all game audio (%f9 = 0)',
          icon: Icons.volume_off,
          isSelected: audio.soundMode == AgiSoundMode.off,
          onTap: () {
            notifier.setSoundMode(AgiSoundMode.off);
            widget.engine?.setSoundMode(AgiSoundMode.off);
          },
        ),

        if (audio.soundMode == AgiSoundMode.enhanced) ...[
          const SizedBox(height: 18),
          const Divider(color: AgiTheme.egaBorder),
          const SizedBox(height: 14),
          _buildSectionHeader('ENHANCED WAVEFORM'),
          const SizedBox(height: 10),
          _buildWaveformChips(audio, notifier),
          const SizedBox(height: 18),
          _buildSectionHeader('DSP ROOM REVERB'),
          const SizedBox(height: 10),
          _buildReverbPresets(audio, notifier),
        ],

        const SizedBox(height: 20),
        const Divider(color: AgiTheme.egaBorder),
        const SizedBox(height: 14),
        _buildSectionHeader('MASTER VOLUME'),
        const SizedBox(height: 8),
        _buildVolumeSlider(audio, notifier),
        const SizedBox(height: 20),
        _buildTestSoundAction(audio),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Courier',
        fontWeight: FontWeight.bold,
        fontSize: 11.5,
        letterSpacing: 0.8,
        color: AgiTheme.egaAmber,
      ),
    );
  }

  Widget _buildSoundModeOption({
    required AgiSoundMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E3A5F) : const Color(0xFF131D31),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AgiTheme.egaCyan : const Color(0xFF27354A),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? AgiTheme.egaCyan : AgiTheme.egaMuted,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isSelected ? AgiTheme.egaWhite : const Color(0xFFCBD5E1),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AgiTheme.egaMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                size: 18,
                color: AgiTheme.egaCyan,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveformChips(AgiAudioSettings audio, SettingsNotifier notifier) {
    const options = [
      (WaveformType.square, 'Square', '8-bit retro'),
      (WaveformType.pulseWidthModulation, 'PWM', 'Chorus pulse'),
      (WaveformType.sawtooth, 'Sawtooth', 'Bright lead'),
      (WaveformType.triangle, 'Triangle', 'Warm bass'),
      (WaveformType.sine, 'Sine', 'Smooth organ'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = audio.waveform == opt.$1;
        return ChoiceChip(
          label: Text(
            opt.$2,
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.black : AgiTheme.egaWhite,
            ),
          ),
          selected: isSelected,
          selectedColor: AgiTheme.egaCyan,
          backgroundColor: const Color(0xFF131D31),
          side: BorderSide(
            color: isSelected ? AgiTheme.egaCyan : const Color(0xFF27354A),
          ),
          onSelected: (selected) {
            if (selected) {
              final newConfig = audio.toSynthesizerConfig().copyWith(waveform: opt.$1);
              notifier.setSynthesizerConfig(newConfig);
              widget.engine?.setSynthesizerConfig(newConfig);
            }
          },
        );
      }).toList(),
    );
  }

  Widget _buildReverbPresets(AgiAudioSettings audio, SettingsNotifier notifier) {
    const presets = [
      ('Dry (0%)', 0.0),
      ('Light (15%)', 0.15),
      ('Hall (30%)', 0.30),
      ('Cathedral (60%)', 0.60),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: presets.map((p) {
        final isSelected = (audio.reverbMix - p.$2).abs() < 0.05 && (p.$2 == 0.0 ? !audio.enableReverb : audio.enableReverb);

        return InkWell(
          onTap: () {
            final newConfig = audio.toSynthesizerConfig().copyWith(
              enableReverb: p.$2 > 0.0,
              reverbMix: p.$2,
            );
            notifier.setSynthesizerConfig(newConfig);
            widget.engine?.setSynthesizerConfig(newConfig);
          },
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF1E3A5F) : const Color(0xFF131D31),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? AgiTheme.egaCyan : const Color(0xFF27354A),
              ),
            ),
            child: Text(
              p.$1,
              style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AgiTheme.egaCyan : AgiTheme.egaMuted,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildVolumeSlider(AgiAudioSettings audio, SettingsNotifier notifier) {
    final volPercent = (audio.masterVolume * 100).toInt();

    return Row(
      children: [
        Icon(
          volPercent == 0
              ? Icons.volume_mute
              : volPercent < 50
                  ? Icons.volume_down
                  : Icons.volume_up,
          size: 20,
          color: AgiTheme.egaCyan,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AgiTheme.egaCyan,
              inactiveTrackColor: const Color(0xFF27354A),
              thumbColor: AgiTheme.egaCyan,
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: audio.masterVolume,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (val) {
                notifier.setMasterVolume(val);
                widget.engine?.setSynthesizerConfig(
                  audio.toSynthesizerConfig().copyWith(masterVolume: val),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(
            '$volPercent%',
            style: const TextStyle(
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: AgiTheme.egaWhite,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTestSoundAction(AgiAudioSettings audio) {
    return ElevatedButton.icon(
      onPressed: () => _playTestSound(audio),
      icon: Icon(
        _isPlayingPreview ? Icons.stop : Icons.play_arrow,
        size: 18,
        color: Colors.black,
      ),
      label: Text(
        _isPlayingPreview ? 'STOP PREVIEW' : 'PLAY TEST SOUND',
        style: const TextStyle(
          fontFamily: 'Courier',
          fontWeight: FontWeight.bold,
          fontSize: 12.5,
          color: Colors.black,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _isPlayingPreview ? AgiTheme.egaRed : AgiTheme.egaCyan,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  // ===========================================================================
  // Video Tab
  // ===========================================================================

  Widget _buildVideoTab(AgiDisplaySettings display, SettingsNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('ASPECT RATIO & DISPLAY SCALING'),
        const SizedBox(height: 10),
        _buildSwitchOption(
          title: '4:3 CRT Aspect Ratio Correction',
          subtitle: display.correctAspectRatio
              ? 'Authentic 4:3 CRT monitor aspect ratio with horizontal stretch'
              : '1:1 Square Pixel Aspect Ratio (160x168)',
          value: display.correctAspectRatio,
          icon: Icons.aspect_ratio,
          onChanged: (val) => notifier.updateDisplay(correctAspectRatio: val),
        ),
        const SizedBox(height: 10),
        _buildSwitchOption(
          title: 'Strict Integer Scaling',
          subtitle: display.strictIntegerScaling
              ? 'Scale strictly by whole integer multiples (1x, 2x, 3x, 4x...)'
              : 'Smoothly fit to window viewport constraints',
          value: display.strictIntegerScaling,
          icon: Icons.fit_screen,
          onChanged: (val) => notifier.updateDisplay(strictIntegerScaling: val),
        ),

        const SizedBox(height: 20),
        const Divider(color: AgiTheme.egaBorder),
        const SizedBox(height: 14),
        _buildSectionHeader('RETRO SHADERS & OVERLAYS'),
        const SizedBox(height: 10),
        _buildSwitchOption(
          title: 'CRT Scanlines & Phosphor Shader',
          subtitle: 'Simulate retro CRT display scanlines, phosphor glow, and screen vignette',
          value: display.showCrtShader,
          icon: Icons.tv,
          onChanged: (val) => notifier.updateDisplay(showCrtShader: val),
        ),
        const SizedBox(height: 10),
        _buildSwitchOption(
          title: 'Pixel Grid Overlay',
          subtitle: 'Overlay 160x168 EGA pixel grid borders for crisp diagnostic alignment',
          value: display.showPixelGrid,
          icon: Icons.grid_4x4,
          onChanged: (val) => notifier.updateDisplay(showPixelGrid: val),
        ),

        const SizedBox(height: 20),
        const Divider(color: AgiTheme.egaBorder),
        const SizedBox(height: 14),
        _buildSectionHeader('DEFAULT RENDER MODE'),
        const SizedBox(height: 10),
        _buildRenderModeSelector(display, notifier),
      ],
    );
  }

  Widget _buildSwitchOption({
    required String title,
    required String subtitle,
    required bool value,
    required IconData icon,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF27354A)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: value ? AgiTheme.egaCyan : AgiTheme.egaMuted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: AgiTheme.egaWhite,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AgiTheme.egaMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeTrackColor: AgiTheme.egaCyan,
            activeThumbColor: Colors.black,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildRenderModeSelector(AgiDisplaySettings display, SettingsNotifier notifier) {
    const modes = [
      (AgiPictureRenderMode.compositedSlices, 'Composited Slices', 'Standard 16-layer compositing with sprite depth sorting'),
      (AgiPictureRenderMode.flatVisual, 'Visual Only', 'Background visual plane only (ignoring actors)'),
      (AgiPictureRenderMode.priorityMap, 'Priority Buffer', '16-color priority depth map (0..15)'),
      (AgiPictureRenderMode.controlMap, 'Control Screen', 'Collision barrier lines and trigger pixels'),
    ];

    return Column(
      children: modes.map((m) {
        final isSelected = display.renderMode == m.$1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            onTap: () => notifier.updateDisplay(renderMode: m.$1),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1E3A5F) : const Color(0xFF131D31),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected ? AgiTheme.egaCyan : const Color(0xFF27354A),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 16,
                    color: isSelected ? AgiTheme.egaCyan : AgiTheme.egaMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.$2,
                          style: TextStyle(
                            fontFamily: 'Courier',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isSelected ? AgiTheme.egaWhite : const Color(0xFFCBD5E1),
                          ),
                        ),
                        Text(
                          m.$3,
                          style: const TextStyle(fontSize: 10.5, color: AgiTheme.egaMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Text(
              'Settings automatically persist across sessions.',
              style: TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AgiTheme.egaCyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text(
              'DONE',
              style: TextStyle(
                fontFamily: 'Courier',
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
