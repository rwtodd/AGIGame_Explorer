import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/engine/agi_game_engine.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';

/// Available tabs in the sidebar slideout panel.
enum SidebarPanelTab {
  audio,
  video,
}

/// Slide-out options panel docked next to the left sidebar in [GameScreen].
class SidebarSlideoutPanel extends StatefulWidget {
  final bool isOpen;
  final SidebarPanelTab activeTab;
  final AgiGameEngine engine;
  final ValueChanged<SidebarPanelTab> onTabChanged;
  final VoidCallback onClose;

  // Video options callbacks/state
  final bool showCrtShader;
  final ValueChanged<bool> onCrtShaderChanged;
  final bool showPixelGrid;
  final ValueChanged<bool> onPixelGridChanged;
  final bool correctAspectRatio;
  final ValueChanged<bool> onAspectRatioChanged;
  final bool strictIntegerScaling;
  final ValueChanged<bool> onStrictIntegerScalingChanged;
  final AgiPictureRenderMode renderMode;
  final ValueChanged<AgiPictureRenderMode> onRenderModeChanged;

  const SidebarSlideoutPanel({
    super.key,
    required this.isOpen,
    required this.activeTab,
    required this.engine,
    required this.onTabChanged,
    required this.onClose,
    required this.showCrtShader,
    required this.onCrtShaderChanged,
    required this.showPixelGrid,
    required this.onPixelGridChanged,
    required this.correctAspectRatio,
    required this.onAspectRatioChanged,
    required this.strictIntegerScaling,
    required this.onStrictIntegerScalingChanged,
    required this.renderMode,
    required this.onRenderModeChanged,
  });

  @override
  State<SidebarSlideoutPanel> createState() => _SidebarSlideoutPanelState();
}

class _SidebarSlideoutPanelState extends State<SidebarSlideoutPanel> {
  AgiSoundPlayer? _previewPlayer;
  bool _isPlayingPreview = false;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  /// Synthesizes and plays a short preview arpeggio/melody using the active synthesizer config.
  Future<void> _playTestSound() async {
    if (_previewPlayer == null) return;

    if (_isPlayingPreview) {
      _previewPlayer!.stop();
      setState(() {
        _isPlayingPreview = false;
      });
      return;
    }

    final engine = widget.engine;
    AgiSound soundToPlay;

    // Check if the loaded game has sounds to preview
    if (engine.resourceLoader != null &&
        engine.resourceLoader!.presentSoundNumbers.isNotEmpty) {
      final soundNum = engine.resourceLoader!.presentSoundNumbers.first;
      soundToPlay = engine.resourceLoader!.loadSound(soundNum);
    } else {
      // Generate a dynamic preview sound (3-voice C Major fanfare)
      soundToPlay = _generatePreviewFanfare();
    }

    final config = engine.synthesizerConfig;
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

  /// Generates a synthetic 3-voice fanfare [AgiSound] for previewing synthesizer modes.
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
    const panelWidth = 330.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      width: widget.isOpen ? panelWidth : 0.0,
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(
          right: BorderSide(color: AgiTheme.egaBorder, width: 1.5),
        ),
      ),
      child: widget.isOpen
          ? ClipRect(
              child: OverflowBox(
                minWidth: panelWidth,
                maxWidth: panelWidth,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: panelWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      _buildTabBar(),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: widget.activeTab == SidebarPanelTab.audio
                              ? _buildAudioOptions()
                              : _buildVideoOptions(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Row(
        children: [
          Icon(
            widget.activeTab == SidebarPanelTab.audio ? Icons.volume_up : Icons.tv,
            size: 18,
            color: AgiTheme.egaCyan,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.activeTab == SidebarPanelTab.audio ? 'AUDIO OPTIONS' : 'VIDEO & DISPLAY',
              style: const TextStyle(
                fontFamily: 'Courier',
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 0.8,
                color: AgiTheme.egaWhite,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: AgiTheme.egaMuted),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            onPressed: widget.onClose,
            tooltip: 'Close Panel (Esc)',
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFF131D31),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              tab: SidebarPanelTab.audio,
              icon: Icons.music_note,
              label: 'Audio',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildTabButton(
              tab: SidebarPanelTab.video,
              icon: Icons.monitor,
              label: 'Video',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required SidebarPanelTab tab,
    required IconData icon,
    required String label,
  }) {
    final isActive = widget.activeTab == tab;

    return InkWell(
      onTap: () => widget.onTabChanged(tab),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1E3A5F) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? AgiTheme.egaCyan : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? AgiTheme.egaCyan : AgiTheme.egaMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Courier',
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
                color: isActive ? AgiTheme.egaWhite : AgiTheme.egaMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // AUDIO TAB
  // ==========================================

  Widget _buildAudioOptions() {
    final engine = widget.engine;
    final currentMode = engine.soundMode;
    final synthConfig = engine.synthesizerConfig;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('OUTPUT MODE'),
        const SizedBox(height: 6),

        _buildSoundModeTile(
          mode: AgiSoundMode.off,
          title: 'Sound Off',
          subtitle: 'Mute all game sounds (Flag %f9 = 0)',
          icon: Icons.volume_off,
          isSelected: currentMode == AgiSoundMode.off,
          onTap: () => engine.setSoundMode(AgiSoundMode.off),
        ),
        const SizedBox(height: 6),

        _buildSoundModeTile(
          mode: AgiSoundMode.ibmPc,
          title: 'IBM PC Speaker',
          subtitle: 'Authentic 1-channel square wave (%v22 = 1)',
          icon: Icons.speaker,
          isSelected: currentMode == AgiSoundMode.ibmPc,
          onTap: () => engine.setSoundMode(AgiSoundMode.ibmPc),
        ),
        const SizedBox(height: 6),

        _buildSoundModeTile(
          mode: AgiSoundMode.pcJr,
          title: 'PCjr / Tandy 3-Voice',
          subtitle: 'Authentic 3-voice + noise SN76489 (%v22 = 3)',
          icon: Icons.volume_down,
          isSelected: currentMode == AgiSoundMode.pcJr,
          onTap: () => engine.setSoundMode(AgiSoundMode.pcJr),
        ),
        const SizedBox(height: 6),

        _buildSoundModeTile(
          mode: AgiSoundMode.enhanced,
          title: 'Enhanced Mode',
          subtitle: 'Modern synth with custom waveforms & DSP reverb',
          icon: Icons.auto_awesome,
          isSelected: currentMode == AgiSoundMode.enhanced,
          onTap: () => engine.setSoundMode(AgiSoundMode.enhanced),
        ),

        if (currentMode == AgiSoundMode.enhanced) ...[
          const SizedBox(height: 16),
          const Divider(color: AgiTheme.egaBorder, height: 1),
          const SizedBox(height: 14),

          _buildSectionTitle('ENHANCED WAVEFORM'),
          const SizedBox(height: 8),
          _buildWaveformSelector(synthConfig),

          const SizedBox(height: 16),
          _buildSectionTitle('DSP ROOM REVERB'),
          const SizedBox(height: 8),
          _buildReverbControls(synthConfig),
        ],

        const SizedBox(height: 18),
        const Divider(color: AgiTheme.egaBorder, height: 1),
        const SizedBox(height: 14),

        _buildSectionTitle('MASTER VOLUME'),
        const SizedBox(height: 6),
        _buildVolumeControl(synthConfig),

        const SizedBox(height: 16),
        _buildTestSoundButton(),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: 'Courier',
        fontWeight: FontWeight.bold,
        fontSize: 11,
        letterSpacing: 0.8,
        color: AgiTheme.egaAmber,
      ),
    );
  }

  Widget _buildSoundModeTile({
    required AgiSoundMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E3A5F) : const Color(0xFF131D31),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AgiTheme.egaCyan : const Color(0xFF27354A),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AgiTheme.egaCyan : AgiTheme.egaMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: isSelected ? AgiTheme.egaWhite : const Color(0xFFCBD5E1),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 10.5,
                      color: AgiTheme.egaMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                size: 16,
                color: AgiTheme.egaCyan,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveformSelector(SynthesizerConfig config) {
    const waveOptions = [
      (WaveformType.square, 'Square', '8-bit classic'),
      (WaveformType.pulseWidthModulation, 'PWM', 'Chorus pulse'),
      (WaveformType.sawtooth, 'Sawtooth', 'Bright lead'),
      (WaveformType.triangle, 'Triangle', 'Warm bass'),
      (WaveformType.sine, 'Sine', 'Smooth organ'),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: waveOptions.map((opt) {
        final isSelected = config.waveform == opt.$1;
        return ChoiceChip(
          label: Text(
            opt.$2,
            style: TextStyle(
              fontFamily: 'Courier',
              fontSize: 11,
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
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          onSelected: (selected) {
            if (selected) {
              final newConfig = config.copyWith(waveform: opt.$1);
              widget.engine.setSynthesizerConfig(newConfig);
            }
          },
        );
      }).toList(),
    );
  }

  Widget _buildReverbControls(SynthesizerConfig config) {
    final reverbMixPercent = (config.reverbMix * 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Checkbox(
                    value: config.enableReverb,
                    activeColor: AgiTheme.egaCyan,
                    checkColor: Colors.black,
                    onChanged: (val) {
                      final newConfig = config.copyWith(
                        enableReverb: val ?? false,
                        reverbMix: (val ?? false) && config.reverbMix == 0.0 ? 0.28 : config.reverbMix,
                      );
                      widget.engine.setSynthesizerConfig(newConfig);
                    },
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Enable Reverb',
                  style: TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 11.5,
                    color: AgiTheme.egaWhite,
                  ),
                ),
              ],
            ),
            Text(
              config.enableReverb ? '$reverbMixPercent%' : 'OFF',
              style: TextStyle(
                fontFamily: 'Courier',
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: config.enableReverb ? AgiTheme.egaCyan : AgiTheme.egaMuted,
              ),
            ),
          ],
        ),
        if (config.enableReverb) ...[
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AgiTheme.egaCyan,
              inactiveTrackColor: const Color(0xFF27354A),
              thumbColor: AgiTheme.egaCyan,
              overlayColor: AgiTheme.egaCyan.withValues(alpha: 0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: config.reverbMix,
              min: 0.05,
              max: 0.90,
              divisions: 17,
              onChanged: (val) {
                final newConfig = config.copyWith(reverbMix: val, enableReverb: true);
                widget.engine.setSynthesizerConfig(newConfig);
              },
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildReverbPresetButton('Dry (0%)', 0.0, config),
              _buildReverbPresetButton('Light (15%)', 0.15, config),
              _buildReverbPresetButton('Hall (30%)', 0.30, config),
              _buildReverbPresetButton('Cathedral (60%)', 0.60, config),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildReverbPresetButton(String label, double amount, SynthesizerConfig config) {
    final isSelected = (config.reverbMix - amount).abs() < 0.05 && config.enableReverb;

    return InkWell(
      onTap: () {
        final newConfig = config.copyWith(
          reverbMix: amount,
          enableReverb: true,
        );
        widget.engine.setSynthesizerConfig(newConfig);
      },
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E3A5F) : const Color(0xFF131D31),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected ? AgiTheme.egaCyan : const Color(0xFF27354A),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Courier',
            fontSize: 9.5,
            color: isSelected ? AgiTheme.egaCyan : AgiTheme.egaMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeControl(SynthesizerConfig config) {
    final volPercent = (config.masterVolume * 100).toInt();

    return Row(
      children: [
        Icon(
          volPercent == 0
              ? Icons.volume_mute
              : volPercent < 50
                  ? Icons.volume_down
                  : Icons.volume_up,
          size: 18,
          color: AgiTheme.egaCyan,
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AgiTheme.egaCyan,
              inactiveTrackColor: const Color(0xFF27354A),
              thumbColor: AgiTheme.egaCyan,
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: config.masterVolume,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (val) {
                final newConfig = config.copyWith(masterVolume: val);
                widget.engine.setSynthesizerConfig(newConfig);
              },
            ),
          ),
        ),
        Text(
          '$volPercent%',
          style: const TextStyle(
            fontFamily: 'Courier',
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: AgiTheme.egaWhite,
          ),
        ),
      ],
    );
  }

  Widget _buildTestSoundButton() {
    return ElevatedButton.icon(
      onPressed: _playTestSound,
      icon: Icon(
        _isPlayingPreview ? Icons.stop : Icons.play_arrow,
        size: 16,
        color: _isPlayingPreview ? Colors.black : Colors.black,
      ),
      label: Text(
        _isPlayingPreview ? 'STOP PREVIEW' : 'PLAY TEST SOUND',
        style: const TextStyle(
          fontFamily: 'Courier',
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: Colors.black,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _isPlayingPreview ? AgiTheme.egaRed : AgiTheme.egaCyan,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  // ==========================================
  // VIDEO TAB
  // ==========================================

  Widget _buildVideoOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('ASPECT RATIO & SCALING'),
        const SizedBox(height: 8),

        _buildSwitchTile(
          title: '4:3 CRT Aspect Correction',
          subtitle: widget.correctAspectRatio
              ? 'Authentic 4:3 CRT monitor aspect ratio'
              : '1:1 Square Pixel Aspect Ratio (16:10)',
          value: widget.correctAspectRatio,
          onChanged: widget.onAspectRatioChanged,
          icon: Icons.aspect_ratio,
        ),
        const SizedBox(height: 6),

        _buildSwitchTile(
          title: 'Strict Integer Scaling',
          subtitle: widget.strictIntegerScaling
              ? 'Scale strictly by whole integer multiples (1x, 2x, 3x...)'
              : 'Smoothly fit to window viewport',
          value: widget.strictIntegerScaling,
          onChanged: widget.onStrictIntegerScalingChanged,
          icon: Icons.fit_screen,
        ),

        const SizedBox(height: 16),
        const Divider(color: AgiTheme.egaBorder, height: 1),
        const SizedBox(height: 14),

        _buildSectionTitle('DISPLAY SHADERS & FILTERS'),
        const SizedBox(height: 8),

        _buildSwitchTile(
          title: 'CRT Scanline Shader',
          subtitle: 'Simulate retro CRT phosphor scanlines & curve',
          value: widget.showCrtShader,
          onChanged: widget.onCrtShaderChanged,
          icon: Icons.tv,
        ),
        const SizedBox(height: 6),

        _buildSwitchTile(
          title: 'Pixel Grid Overlay',
          subtitle: 'Draw 160x168 EGA pixel grid lines',
          value: widget.showPixelGrid,
          onChanged: widget.onPixelGridChanged,
          icon: Icons.grid_4x4,
        ),

        const SizedBox(height: 16),
        const Divider(color: AgiTheme.egaBorder, height: 1),
        const SizedBox(height: 14),

        _buildSectionTitle('RENDER BUFFER MODE'),
        const SizedBox(height: 8),

        ...AgiPictureRenderMode.values.map((mode) {
          final isSelected = widget.renderMode == mode;
          String label;
          String sub;
          IconData icon;

          switch (mode) {
            case AgiPictureRenderMode.compositedSlices:
              label = 'Priority Slices (Game View)';
              sub = 'Multi-layer depth composited with sprites';
              icon = Icons.view_in_ar;
              break;
            case AgiPictureRenderMode.flatVisual:
              label = 'Flat Visual Background';
              sub = 'EGA 16-color background screen';
              icon = Icons.palette;
              break;
            case AgiPictureRenderMode.priorityMap:
              label = 'Priority Depth Buffer';
              sub = 'Depth layering map (0..15)';
              icon = Icons.layers;
              break;
            case AgiPictureRenderMode.controlMap:
              label = 'Control Screen';
              sub = 'Collision & trigger control lines';
              icon = Icons.security;
              break;
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => widget.onRenderModeChanged(mode),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                      icon,
                      size: 18,
                      color: isSelected ? AgiTheme.egaCyan : AgiTheme.egaMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontFamily: 'Courier',
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: isSelected ? AgiTheme.egaWhite : const Color(0xFFCBD5E1),
                            ),
                          ),
                          Text(
                            sub,
                            style: const TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 10,
                              color: AgiTheme.egaMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle, size: 14, color: AgiTheme.egaCyan),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131D31),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF27354A)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: value ? AgiTheme.egaCyan : AgiTheme.egaMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AgiTheme.egaWhite,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 10,
                    color: AgiTheme.egaMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AgiTheme.egaCyan,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
