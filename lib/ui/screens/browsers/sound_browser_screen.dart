import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/csound_builder.dart';
import 'package:flutter_agigame/audio/midi_builder.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';

/// Available rendering and export methods for AGI sounds.
enum SoundRenderMethod {
  tandy3VoiceNoise(label: 'Tandy 3-Voice + Noise', isPcm: true),
  ibmPcSingleChannel(label: 'IBM PC Single Speaker', isPcm: true),
  enhanced(label: 'Enhanced Synthesizer', isPcm: true),
  midiFile(label: 'Standard MIDI File (SMF)', isPcm: false),
  csoundScore(label: 'CSound Score & Orchestra', isPcm: false);

  final String label;
  final bool isPcm;
  const SoundRenderMethod({required this.label, required this.isPcm});
}

class SoundBrowserScreen extends ConsumerStatefulWidget {
  final int? initialSoundNumber;
  final AgiSoundPlayer? soundPlayer;

  const SoundBrowserScreen({
    super.key,
    this.initialSoundNumber,
    this.soundPlayer,
  });

  @override
  ConsumerState<SoundBrowserScreen> createState() => _SoundBrowserScreenState();
}

class _SoundBrowserScreenState extends ConsumerState<SoundBrowserScreen> {
  int _selectedSoundNumber = 0;
  SoundRenderMethod _selectedMethod = SoundRenderMethod.tandy3VoiceNoise;
  WaveformType _waveform = WaveformType.pulseWidthModulation;
  bool _enableReverb = false;
  double _reverbMix = 0.28;
  double _zoomScale = 6.0; // pixels per tick
  double _volume = 0.8;
  bool _isLooping = false;

  AgiSound? _currentSound;
  bool _isLoading = false;
  String? _errorMessage;

  late final AgiSoundPlayer _player;
  late final StreamSubscription<SoundPlaybackPosition> _positionSubscription;
  final ValueNotifier<SoundPlaybackPosition> _positionNotifier =
      ValueNotifier(SoundPlaybackPosition.zero);

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _player = widget.soundPlayer ?? AgiSoundPlayer();
    _player.setVolume(_volume);
    _player.setLooping(_isLooping);

    _player.onFinished = () {
      if (mounted) setState(() {});
    };

    _positionSubscription = _player.positionStream.listen((pos) {
      _positionNotifier.value = pos;
    });

    final loader = ref.read(launcherProvider).loader;
    if (loader != null) {
      final present = loader.presentSoundNumbers;
      if (widget.initialSoundNumber != null && present.contains(widget.initialSoundNumber)) {
        _selectedSoundNumber = widget.initialSoundNumber!;
      } else if (present.isNotEmpty) {
        _selectedSoundNumber = present.first;
      }
      _loadSound(_selectedSoundNumber);
    }
  }

  @override
  void dispose() {
    _positionSubscription.cancel();
    _player.stop();
    if (widget.soundPlayer == null) {
      _player.dispose();
    }
    _positionNotifier.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _loadSound(int soundNum) {
    final loader = ref.read(launcherProvider).loader;
    if (loader == null) return;

    _player.stop();
    _positionNotifier.value = SoundPlaybackPosition.zero;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedSoundNumber = soundNum;
    });

    try {
      final snd = loader.loadSound(soundNum);
      setState(() {
        _currentSound = snd;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load SOUND $soundNum: $e';
        _isLoading = false;
      });
    }
  }

  SynthesizerConfig _buildCurrentConfig() {
    PcmPlaybackMode mode;
    switch (_selectedMethod) {
      case SoundRenderMethod.ibmPcSingleChannel:
        mode = PcmPlaybackMode.ibmPcSingleChannel;
        break;
      case SoundRenderMethod.enhanced:
        mode = PcmPlaybackMode.enhanced;
        break;
      case SoundRenderMethod.tandy3VoiceNoise:
      default:
        mode = PcmPlaybackMode.tandy3VoiceNoise;
        break;
    }

    return SynthesizerConfig(
      mode: mode,
      waveform: _waveform,
      enableReverb: _enableReverb,
      reverbMix: _reverbMix,
      masterVolume: _volume,
    );
  }

  Future<void> _togglePlayPause() async {
    if (!_selectedMethod.isPcm) return;
    if (_currentSound == null || _currentSound!.isEmpty) return;

    if (_player.isPlaying) {
      _player.pause();
      setState(() {});
    } else if (_player.isPaused) {
      _player.resume();
      setState(() {});
    } else {
      setState(() {});
      await _player.play(
        _currentSound!,
        config: _buildCurrentConfig(),
        startTick: _positionNotifier.value.currentTick,
      );
      if (mounted) setState(() {});
    }
  }

  void _stopPlayback() {
    _player.stop();
    _positionNotifier.value = SoundPlaybackPosition.zero;
    setState(() {});
  }

  Future<void> _seekToTick(int tick) async {
    await _player.seekToTick(tick);
  }

  Future<void> _exportActiveMethod() async {
    final snd = _currentSound;
    if (snd == null) return;

    switch (_selectedMethod) {
      case SoundRenderMethod.tandy3VoiceNoise:
      case SoundRenderMethod.ibmPcSingleChannel:
      case SoundRenderMethod.enhanced:
        await _exportWav();
        break;
      case SoundRenderMethod.midiFile:
        await _exportMidi();
        break;
      case SoundRenderMethod.csoundScore:
        await _exportCSound();
        break;
    }
  }

  Future<void> _exportWav() async {
    final snd = _currentSound;
    if (snd == null) return;

    try {
      final config = _buildCurrentConfig();
      final synth = PcmSynthesizer(config);
      final wavBytes = synth.renderWav(snd);
      final fileName = 'sound_${_selectedSoundNumber.toString().padLeft(3, '0')}.wav';

      final uri = await FilePickerPlatform.instance.saveFile(
        dialogTitle: 'Save Sound #$_selectedSoundNumber WAV',
        fileName: fileName,
        bytes: wavBytes,
        mimeType: 'audio/wav',
      );

      if (uri != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported WAV audio to ${uri.toFilePath()}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export WAV failed: $e'), backgroundColor: AgiTheme.egaRed),
        );
      }
    }
  }

  Future<void> _exportMidi() async {
    final snd = _currentSound;
    if (snd == null) return;

    try {
      final midiBytes = MidiBuilder.buildMidi(
        sound: snd,
        soundNumber: _selectedSoundNumber,
      );
      final fileName = 'sound_${_selectedSoundNumber.toString().padLeft(3, '0')}.mid';

      final uri = await FilePickerPlatform.instance.saveFile(
        dialogTitle: 'Save Sound #$_selectedSoundNumber MIDI',
        fileName: fileName,
        bytes: midiBytes,
        mimeType: 'audio/midi',
      );

      if (uri != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported MIDI file to ${uri.toFilePath()}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export MIDI failed: $e'), backgroundColor: AgiTheme.egaRed),
        );
      }
    }
  }

  Future<void> _exportCSound() async {
    final snd = _currentSound;
    if (snd == null) return;

    try {
      final scoContent = CSoundBuilder.buildScore(
        sound: snd,
        soundNumber: _selectedSoundNumber,
      );
      final fileName = 'sound_${_selectedSoundNumber.toString().padLeft(3, '0')}.sco';

      final uri = await FilePickerPlatform.instance.saveFile(
        dialogTitle: 'Save Sound #$_selectedSoundNumber CSound Score',
        fileName: fileName,
        bytes: utf8.encode(scoContent),
        mimeType: 'text/plain',
      );

      if (uri != null) {
        final filePath = uri.toFilePath();
        final file = File(filePath);

        // Also output default orchestra file alongside if missing
        final orcFile = File('${file.parent.path}/agi-tandy.orc');
        if (!await orcFile.exists()) {
          await orcFile.writeAsString(CSoundBuilder.tandyOrchestra);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported CSound score to $filePath')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export CSound failed: $e'), backgroundColor: AgiTheme.egaRed),
        );
      }
    }
  }

  void _onKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _togglePlayPause();
      } else if (event.logicalKey == LogicalKeyboardKey.keyS) {
        _stopPlayback();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final launcherState = ref.watch(launcherProvider);
    final loader = launcherState.loader;
    final presentSounds = loader?.presentSoundNumbers ?? [];

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: AgiTheme.egaBlack,
        appBar: _buildAppBar(presentSounds),
        body: Row(
          children: [
            // Left: Playback Controls & Rendering Configuration Panel
            _buildLeftControlPanel(),

            // Right: Interactive Multi-Track Piano Roll Timeline
            Expanded(
              child: Container(
                color: const Color(0xFF080B0F),
                child: _buildTimelineArea(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(List<int> presentSounds) {
    final currentIndex = presentSounds.indexOf(_selectedSoundNumber);
    final hasPrev = currentIndex > 0;
    final hasNext = currentIndex >= 0 && currentIndex < presentSounds.length - 1;

    return AppBar(
      backgroundColor: AgiTheme.egaDarkSurface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AgiTheme.egaCyan),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: 'Back to Overview',
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF443300),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AgiTheme.egaAmber),
            ),
            child: const Text(
              'SOUND BROWSER',
              style: TextStyle(
                color: AgiTheme.egaAmber,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 14),

          IconButton(
            icon: const Icon(Icons.chevron_left),
            color: hasPrev ? AgiTheme.egaCyan : AgiTheme.egaMuted,
            onPressed: hasPrev ? () => _loadSound(presentSounds[currentIndex - 1]) : null,
            tooltip: 'Previous Sound',
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: presentSounds.contains(_selectedSoundNumber) ? _selectedSoundNumber : null,
              dropdownColor: AgiTheme.egaCardSurface,
              style: const TextStyle(
                color: AgiTheme.egaWhite,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              items: presentSounds.map((soundNum) {
                return DropdownMenuItem<int>(
                  value: soundNum,
                  child: Text('SOUND $soundNum'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) _loadSound(val);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            color: hasNext ? AgiTheme.egaCyan : AgiTheme.egaMuted,
            onPressed: hasNext ? () => _loadSound(presentSounds[currentIndex + 1]) : null,
            tooltip: 'Next Sound',
          ),

          if (_currentSound != null) ...[
            const SizedBox(width: 12),
            Text(
              '${_currentSound!.voices.length} Voices • ${_currentSound!.durationInSeconds.toStringAsFixed(2)}s (${_currentSound!.length} ticks)',
              style: const TextStyle(fontSize: 11, color: AgiTheme.egaMuted),
            ),
          ],
        ],
      ),
      actions: [
        // Zoom Slider in AppBar
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.zoom_in, size: 16, color: AgiTheme.egaMuted),
            const SizedBox(width: 4),
            const Text('Zoom: ', style: TextStyle(color: AgiTheme.egaMuted, fontSize: 12)),
            SizedBox(
              width: 110,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: _zoomScale,
                  min: 2.0,
                  max: 16.0,
                  activeColor: AgiTheme.egaAmber,
                  inactiveColor: AgiTheme.egaBorder,
                  onChanged: (v) => setState(() => _zoomScale = v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildLeftControlPanel() {
    final snd = _currentSound;
    final isPlaying = _player.isPlaying;
    final isPcm = _selectedMethod.isPcm;

    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(right: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // Section 1: Sound Information
          _buildSoundInfoCard(snd),
          const SizedBox(height: 12),

          // Section 2: Playback Transport Controls
          _buildTransportCard(snd, isPlaying, isPcm),
          const SizedBox(height: 12),

          // Section 3: Synthesis & Method Configuration
          _buildRenderingMethodCard(),
          const SizedBox(height: 12),

          // Section 4: Export Action
          _buildExportCard(snd),
        ],
      ),
    );
  }

  Widget _buildSoundInfoCard(AgiSound? snd) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AgiTheme.egaBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.music_note, size: 16, color: AgiTheme.egaAmber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'SOUND #$_selectedSoundNumber',
                  style: const TextStyle(
                    color: AgiTheme.egaAmber,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (snd != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${snd.durationInSeconds.toStringAsFixed(2)}s',
                    style: const TextStyle(
                      color: AgiTheme.egaCyan,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (snd != null) ...[
            Text(
              '${snd.voices.length} Tone ${snd.voices.length == 1 ? "Voice" : "Voices"}${snd.noise != null ? " + Noise Channel" : " (No Noise)"}',
              style: const TextStyle(color: AgiTheme.egaWhite, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              'Total Duration: ${snd.length} ticks (60 Hz standard)',
              style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 11),
            ),
          ] else ...[
            const Text(
              'No sound resource selected',
              style: TextStyle(color: AgiTheme.egaMuted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransportCard(AgiSound? snd, bool isPlaying, bool isPcm) {
    final totalTicks = snd?.length ?? 0;
    final totalSeconds = (totalTicks / 60.0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AgiTheme.egaBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<SoundPlaybackPosition>(
            valueListenable: _positionNotifier,
            builder: (context, pos, _) {
              final curSecStr = pos.currentSeconds.toStringAsFixed(2);
              final totSecStr = totalSeconds.toStringAsFixed(2);

              return Row(
                children: [
                  const Icon(Icons.play_circle_outline, size: 16, color: AgiTheme.egaCyan),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'PLAYBACK',
                      style: TextStyle(
                        color: AgiTheme.egaCyan,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Text(
                    '$curSecStr / $totSecStr s',
                    style: const TextStyle(
                      color: AgiTheme.egaWhite,
                      fontSize: 11,
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),

          // Time / Tick Progress Bar
          ValueListenableBuilder<SoundPlaybackPosition>(
            valueListenable: _positionNotifier,
            builder: (context, pos, _) {
              return SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Slider(
                  value: totalTicks > 0 ? (pos.currentTick / totalTicks).clamp(0.0, 1.0) : 0.0,
                  activeColor: AgiTheme.egaAmber,
                  inactiveColor: const Color(0xFF2D333B),
                  onChanged: isPcm && totalTicks > 0
                      ? (val) {
                          final targetTick = (val * totalTicks).round();
                          _seekToTick(targetTick);
                        }
                      : null,
                ),
              );
            },
          ),

          ValueListenableBuilder<SoundPlaybackPosition>(
            valueListenable: _positionNotifier,
            builder: (context, pos, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tick: ${pos.currentTick} / $totalTicks',
                    style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 10),
                  ),
                  if (!isPcm)
                    const Text(
                      'Export Only',
                      style: TextStyle(
                        color: AgiTheme.egaAmber,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),

          // Primary Action Buttons: Play/Pause, Stop, Loop
          Row(
            children: [
              // Play / Pause Button
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: isPcm && snd != null && !snd.isEmpty ? _togglePlayPause : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPlaying ? AgiTheme.egaAmber : AgiTheme.egaGreen,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 18,
                  ),
                  label: Text(
                    isPlaying ? 'Pause' : 'Play',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Stop Button
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: isPcm && (isPlaying || _player.isPaused || _positionNotifier.value.currentTick > 0)
                      ? _stopPlayback
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AgiTheme.egaWhite,
                    side: const BorderSide(color: AgiTheme.egaBorder),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('Stop', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),

              // Loop Button
              IconButton(
                icon: Icon(
                  _isLooping ? Icons.repeat_one : Icons.repeat,
                  color: _isLooping ? AgiTheme.egaAmber : AgiTheme.egaMuted,
                  size: 20,
                ),
                tooltip: _isLooping ? 'Looping Enabled' : 'Looping Disabled',
                onPressed: () {
                  setState(() {
                    _isLooping = !_isLooping;
                    _player.setLooping(_isLooping);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Volume Control Slider
          Row(
            children: [
              Icon(
                _volume == 0.0 ? Icons.volume_off : Icons.volume_up,
                size: 16,
                color: AgiTheme.egaMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  ),
                  child: Slider(
                    value: _volume,
                    min: 0.0,
                    max: 1.0,
                    activeColor: AgiTheme.egaCyan,
                    inactiveColor: AgiTheme.egaBorder,
                    onChanged: (v) {
                      setState(() {
                        _volume = v;
                        _player.setVolume(v);
                      });
                    },
                  ),
                ),
              ),
              Text(
                '${(_volume * 100).round()}%',
                style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRenderingMethodCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AgiTheme.egaBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune, size: 16, color: AgiTheme.egaAmber),
              SizedBox(width: 8),
              Text(
                'RENDERING METHOD',
                style: TextStyle(
                  color: AgiTheme.egaAmber,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Method Selector Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AgiTheme.egaBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SoundRenderMethod>(
                value: _selectedMethod,
                isExpanded: true,
                dropdownColor: AgiTheme.egaCardSurface,
                style: const TextStyle(
                  color: AgiTheme.egaCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                items: SoundRenderMethod.values.map((method) {
                  return DropdownMenuItem<SoundRenderMethod>(
                    value: method,
                    child: Row(
                      children: [
                        Icon(
                          method.isPcm ? Icons.volume_up : Icons.save_alt,
                          size: 14,
                          color: method.isPcm ? AgiTheme.egaGreen : AgiTheme.egaMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(method.label)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedMethod = val;
                    });
                    if (!val.isPcm && _player.isPlaying) {
                      _player.stop();
                    }
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Additional Controls for Enhanced PCM Mode
          if (_selectedMethod == SoundRenderMethod.enhanced) ...[
            const Text('Enhanced Waveform:', style: TextStyle(color: AgiTheme.egaMuted, fontSize: 11)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AgiTheme.egaBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<WaveformType>(
                  value: _waveform,
                  isExpanded: true,
                  dropdownColor: AgiTheme.egaCardSurface,
                  style: const TextStyle(color: AgiTheme.egaAmber, fontSize: 12),
                  items: const [
                    DropdownMenuItem(value: WaveformType.pulseWidthModulation, child: Text('PWM Square Wave')),
                    DropdownMenuItem(value: WaveformType.square, child: Text('Square Wave')),
                    DropdownMenuItem(value: WaveformType.sawtooth, child: Text('Sawtooth Wave')),
                    DropdownMenuItem(value: WaveformType.sine, child: Text('Sine Wave')),
                    DropdownMenuItem(value: WaveformType.triangle, child: Text('Triangle Wave')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _waveform = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                const Text('Reverb DSP: ', style: TextStyle(color: AgiTheme.egaMuted, fontSize: 11)),
                const Spacer(),
                Switch(
                  value: _enableReverb,
                  activeThumbColor: AgiTheme.egaAmber,
                  onChanged: (v) => setState(() => _enableReverb = v),
                ),
              ],
            ),
            if (_enableReverb) ...[
              Row(
                children: [
                  const Text('Wet Mix:', style: TextStyle(color: AgiTheme.egaMuted, fontSize: 10)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      ),
                      child: Slider(
                        value: _reverbMix,
                        min: 0.05,
                        max: 0.75,
                        activeColor: AgiTheme.egaAmber,
                        inactiveColor: AgiTheme.egaBorder,
                        onChanged: (v) => setState(() => _reverbMix = v),
                      ),
                    ),
                  ),
                  Text('${(_reverbMix * 100).round()}%', style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 10)),
                ],
              ),
            ],
          ] else if (_selectedMethod == SoundRenderMethod.midiFile) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Standard MIDI Format 1 score. Audio unit playback is disabled for this format. Use "Export MIDI" below to save the .mid file.',
                style: TextStyle(color: AgiTheme.egaMuted, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ),
          ] else if (_selectedMethod == SoundRenderMethod.csoundScore) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'CSound score (.sco) and orchestra (.orc) generator. Playback is disabled for this format. Use "Export CSound" below.',
                style: TextStyle(color: AgiTheme.egaMuted, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExportCard(AgiSound? snd) {
    String exportLabel;
    IconData exportIcon;

    switch (_selectedMethod) {
      case SoundRenderMethod.midiFile:
        exportLabel = 'Export MIDI File (.mid)';
        exportIcon = Icons.piano;
        break;
      case SoundRenderMethod.csoundScore:
        exportLabel = 'Export CSound (.sco)';
        exportIcon = Icons.code;
        break;
      case SoundRenderMethod.tandy3VoiceNoise:
      case SoundRenderMethod.ibmPcSingleChannel:
      case SoundRenderMethod.enhanced:
        exportLabel = 'Export WAV Audio (.wav)';
        exportIcon = Icons.file_download;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AgiTheme.egaBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: snd != null && !snd.isEmpty ? _exportActiveMethod : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF238636),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            icon: Icon(exportIcon, size: 16),
            label: Text(
              exportLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineArea() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AgiTheme.egaAmber));
    }
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: const TextStyle(color: AgiTheme.egaRed)));
    }
    final snd = _currentSound;
    if (snd == null || snd.length == 0) {
      return const Center(child: Text('No sound notes to display.', style: TextStyle(color: AgiTheme.egaMuted)));
    }

    final totalTicks = snd.length;
    final trackWidth = max(800.0, totalTicks * _zoomScale);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        width: trackWidth + 40,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time / Tick Ruler (Interactive seek)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                final localX = details.localPosition.dx;
                final fraction = (localX / trackWidth).clamp(0.0, 1.0);
                final targetTick = (fraction * totalTicks).round();
                _seekToTick(targetTick);
              },
              child: _buildTimeRuler(totalTicks, trackWidth),
            ),
            const SizedBox(height: 16),

            // Main Tracks Container with Overlay Playhead Needle
            Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tone Voice Tracks
                    for (var vIdx = 0; vIdx < snd.voices.length; vIdx++) ...[
                      _buildVoiceTrack(vIdx, snd.voices[vIdx], totalTicks, trackWidth),
                      const SizedBox(height: 16),
                    ],

                    // Noise Channel Track
                    if (snd.noise != null) ...[
                      _buildNoiseTrack(snd.noise!, totalTicks, trackWidth),
                    ],
                  ],
                ),

                // Live Animated Playhead Needle (Isolated RepaintBoundary)
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: ValueListenableBuilder<SoundPlaybackPosition>(
                        valueListenable: _positionNotifier,
                        builder: (context, pos, _) {
                          return CustomPaint(
                            painter: _PlayheadPainter(
                              currentTick: pos.currentTick,
                              totalTicks: totalTicks,
                              trackWidth: trackWidth,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRuler(int totalTicks, double width) {
    return SizedBox(
      width: width,
      height: 28,
      child: RepaintBoundary(
        child: ValueListenableBuilder<SoundPlaybackPosition>(
          valueListenable: _positionNotifier,
          builder: (context, pos, _) {
            return CustomPaint(
              size: Size(width, 28),
              painter: _TimeRulerPainter(
                totalTicks: totalTicks,
                zoomScale: _zoomScale,
                currentTick: pos.currentTick,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildVoiceTrack(int vIdx, ToneChannel voice, int totalTicks, double width) {
    final colors = [AgiTheme.egaCyan, AgiTheme.egaAmber, AgiTheme.egaMagenta];
    final trackColor = colors[vIdx % colors.length];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        final localX = details.localPosition.dx;
        final fraction = (localX / width).clamp(0.0, 1.0);
        final targetTick = (fraction * totalTicks).round();
        _seekToTick(targetTick);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Tone Voice ${vIdx + 1}',
                style: TextStyle(color: trackColor, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Text(
                '(${voice.notes.length} notes, ${voice.length} ticks)',
                style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: width,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF12171E),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AgiTheme.egaBorder),
            ),
            child: CustomPaint(
              size: Size(width, 80),
              painter: _VoiceTimelinePainter(
                voice: voice,
                totalTicks: totalTicks,
                color: trackColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoiseTrack(NoiseChannel noise, int totalTicks, double width) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        final localX = details.localPosition.dx;
        final fraction = (localX / width).clamp(0.0, 1.0);
        final targetTick = (fraction * totalTicks).round();
        _seekToTick(targetTick);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Noise Channel',
                style: TextStyle(color: AgiTheme.egaRed, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Text(
                '(${noise.noises.length} noise bursts, ${noise.length} ticks)',
                style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: width,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF12171E),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AgiTheme.egaBorder),
            ),
            child: CustomPaint(
              size: Size(width, 60),
              painter: _NoiseTimelinePainter(
                noise: noise,
                totalTicks: totalTicks,
                color: AgiTheme.egaRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter for rendering the active playhead vertical needle line across tracks.
class _PlayheadPainter extends CustomPainter {
  final int currentTick;
  final int totalTicks;
  final double trackWidth;

  const _PlayheadPainter({
    required this.currentTick,
    required this.totalTicks,
    required this.trackWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalTicks <= 0 || trackWidth <= 0) return;

    final x = (currentTick / totalTicks) * trackWidth;

    // Glowing vertical needle line
    final glowPaint = Paint()
      ..color = const Color(0x66FFFF00)
      ..strokeWidth = 3;

    final needlePaint = Paint()
      ..color = AgiTheme.egaWhite
      ..strokeWidth = 1.5;

    canvas.drawLine(Offset(x, 0), Offset(x, size.height), glowPaint);
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), needlePaint);
  }

  @override
  bool shouldRepaint(covariant _PlayheadPainter oldDelegate) =>
      oldDelegate.currentTick != currentTick ||
      oldDelegate.totalTicks != totalTicks ||
      oldDelegate.trackWidth != trackWidth;
}

/// CustomPainter that renders a time and tick ruler with playhead marker.
class _TimeRulerPainter extends CustomPainter {
  final int totalTicks;
  final double zoomScale;
  final int currentTick;

  const _TimeRulerPainter({
    required this.totalTicks,
    required this.zoomScale,
    required this.currentTick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AgiTheme.egaBorder
      ..strokeWidth = 1;

    final tickTextPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Draw bottom baseline
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), linePaint);

    // Draw tick marks every 30 ticks (0.5s) and labels every 60 ticks (1.0s)
    for (int t = 0; t <= totalTicks; t += 30) {
      final x = (t / totalTicks) * size.width;
      final isSecond = (t % 60) == 0;
      final tickHeight = isSecond ? 10.0 : 5.0;

      canvas.drawLine(Offset(x, size.height - 1 - tickHeight), Offset(x, size.height - 1), linePaint);

      if (isSecond) {
        final sec = t ~/ 60;
        tickTextPainter.text = TextSpan(
          text: '${sec}s (${t}t)',
          style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 9),
        );
        tickTextPainter.layout();
        tickTextPainter.paint(canvas, Offset(x + 3, 0));
      }
    }

    // Draw Playhead Triangle Marker on Ruler
    if (totalTicks > 0) {
      final curX = (currentTick / totalTicks) * size.width;
      final trianglePath = Path()
        ..moveTo(curX - 5, 0)
        ..lineTo(curX + 5, 0)
        ..lineTo(curX, 8)
        ..close();

      final markerPaint = Paint()
        ..color = AgiTheme.egaAmber
        ..style = PaintingStyle.fill;

      canvas.drawPath(trianglePath, markerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimeRulerPainter oldDelegate) =>
      oldDelegate.totalTicks != totalTicks ||
      oldDelegate.zoomScale != zoomScale ||
      oldDelegate.currentTick != currentTick;
}

class _VoiceTimelinePainter extends CustomPainter {
  final ToneChannel voice;
  final int totalTicks;
  final Color color;

  const _VoiceTimelinePainter({
    required this.voice,
    required this.totalTicks,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalTicks <= 0 || size.width <= 0) return;

    // Draw background pitch guidelines
    final gridPaint = Paint()
      ..color = const Color(0x15FFFFFF)
      ..strokeWidth = 1;

    for (var i = 1; i <= 3; i++) {
      final y = size.height * (i / 4.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final borderPaint = Paint()
      ..color = Colors.black45
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final noteTextPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (final note in voice.notes) {
      if (note.isSilent || note.duration <= 0) continue;

      final startX = (note.startTime / totalTicks) * size.width;
      final width = max(3.0, (note.duration / totalTicks) * size.width);

      // Map MIDI note / frequency to vertical piano roll height
      final midi = note.toMidiNoteNumber();
      final normPitch = ((midi - 28) / (84 - 28)).clamp(0.08, 0.92);
      const noteHeight = 14.0;
      final y = size.height - (normPitch * (size.height - noteHeight - 4)) - noteHeight - 2;

      // Note brightness based on attenuation (0 = loud, 14 = soft)
      final alpha = (1.0 - (note.attenuation / 18.0)).clamp(0.4, 0.95);
      final notePaint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;

      final rect = Rect.fromLTWH(startX, y, max(3.0, width - 1), noteHeight);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));

      canvas.drawRRect(rrect, notePaint);
      canvas.drawRRect(rrect, borderPaint);

      // Render pitch text if box is wide enough
      if (width >= 32) {
        final noteName = _midiToNoteName(midi);
        noteTextPainter.text = TextSpan(
          text: width >= 48 ? '$noteName (${note.frequencyInHz.round()}Hz)' : noteName,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        );
        noteTextPainter.layout(maxWidth: width - 4);
        noteTextPainter.paint(canvas, Offset(startX + 3, y + 1));
      }
    }
  }

  static String _midiToNoteName(int midi) {
    if (midi <= 0) return '';
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (midi ~/ 12) - 1;
    final note = noteNames[midi % 12];
    return '$note$octave';
  }

  @override
  bool shouldRepaint(covariant _VoiceTimelinePainter oldDelegate) => true;
}

class _NoiseTimelinePainter extends CustomPainter {
  final NoiseChannel noise;
  final int totalTicks;
  final Color color;

  const _NoiseTimelinePainter({
    required this.noise,
    required this.totalTicks,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalTicks <= 0 || size.width <= 0) return;

    final borderPaint = Paint()
      ..color = Colors.black45
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final n in noise.noises) {
      if (n.isSilent || n.duration <= 0) continue;

      final startX = (n.startTime / totalTicks) * size.width;
      final width = max(3.0, (n.duration / totalTicks) * size.width);

      final alpha = (1.0 - (n.attenuation / 18.0)).clamp(0.4, 0.9);
      final paint = Paint()
        ..color = (n.type == NoiseType.white ? AgiTheme.egaRed : AgiTheme.egaAmber).withValues(alpha: alpha)
        ..style = PaintingStyle.fill;

      final rect = Rect.fromLTWH(startX, 6, max(3.0, width - 1), size.height - 12);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rrect, paint);
      canvas.drawRRect(rrect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NoiseTimelinePainter oldDelegate) => true;
}
