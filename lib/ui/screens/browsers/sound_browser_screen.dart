import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/domain/sound.dart';
import 'package:flutter_agigame/ui/core/theme.dart';
import 'package:flutter_agigame/ui/providers/game_launcher_provider.dart';

class SoundBrowserScreen extends ConsumerStatefulWidget {
  final int? initialSoundNumber;

  const SoundBrowserScreen({super.key, this.initialSoundNumber});

  @override
  ConsumerState<SoundBrowserScreen> createState() => _SoundBrowserScreenState();
}

class _SoundBrowserScreenState extends ConsumerState<SoundBrowserScreen> {
  int _selectedSoundNumber = 0;
  PcmPlaybackMode _playbackMode = PcmPlaybackMode.tandy3VoiceNoise;
  WaveformType _waveform = WaveformType.pulseWidthModulation;
  bool _enableReverb = false;
  double _zoomScale = 6.0; // pixels per tick

  AgiSound? _currentSound;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
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

  void _loadSound(int soundNum) {
    final loader = ref.read(launcherProvider).loader;
    if (loader == null) return;

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

  Future<void> _exportWav() async {
    final snd = _currentSound;
    if (snd == null) return;

    try {
      final config = SynthesizerConfig(
        mode: _playbackMode,
        waveform: _waveform,
        enableReverb: _enableReverb,
      );
      final synth = PcmSynthesizer(config);
      final wavBytes = synth.renderWav(snd);

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Sound #$_selectedSoundNumber WAV',
        fileName: 'sound_${_selectedSoundNumber.toString().padLeft(3, '0')}.wav',
        type: FileType.custom,
        allowedExtensions: ['wav'],
      );

      if (path != null) {
        final file = File(path.endsWith('.wav') ? path : '$path.wav');
        await file.writeAsBytes(wavBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported WAV audio to ${file.path}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export WAV failed: $e'), backgroundColor: AgiTheme.egaRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final launcherState = ref.watch(launcherProvider);
    final loader = launcherState.loader;
    final presentSounds = loader?.presentSoundNumbers ?? [];

    return Scaffold(
      backgroundColor: AgiTheme.egaBlack,
      appBar: _buildAppBar(presentSounds),
      body: Row(
        children: [
          // Left: Timeline & Piano Roll Note Visualizer
          Expanded(
            child: Column(
              children: [
                _buildSynthesizerBar(),
                Expanded(
                  child: Container(
                    color: const Color(0xFF080B0F),
                    child: _buildTimelineArea(),
                  ),
                ),
              ],
            ),
          ),

          // Right: Channel Notes Breakdown
          _buildChannelSidebar(),
        ],
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
        IconButton(
          icon: const Icon(Icons.audiotrack, color: AgiTheme.egaAmber),
          onPressed: _exportWav,
          tooltip: 'Export WAV Audio',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSynthesizerBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text('Synth Mode: ', style: TextStyle(color: AgiTheme.egaMuted, fontSize: 12)),
            DropdownButtonHideUnderline(
              child: DropdownButton<PcmPlaybackMode>(
                value: _playbackMode,
                dropdownColor: AgiTheme.egaCardSurface,
                style: const TextStyle(color: AgiTheme.egaCyan, fontSize: 12, fontWeight: FontWeight.bold),
                items: const [
                  DropdownMenuItem(value: PcmPlaybackMode.tandy3VoiceNoise, child: Text('Tandy 3-Voice + Noise')),
                  DropdownMenuItem(value: PcmPlaybackMode.ibmPcSingleChannel, child: Text('IBM PC Single Speaker')),
                  DropdownMenuItem(value: PcmPlaybackMode.enhanced, child: Text('Enhanced Synthesizer')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _playbackMode = v);
                },
              ),
            ),
            const SizedBox(width: 16),

            if (_playbackMode == PcmPlaybackMode.enhanced) ...[
              const Text('Wave: ', style: TextStyle(color: AgiTheme.egaMuted, fontSize: 12)),
              DropdownButtonHideUnderline(
                child: DropdownButton<WaveformType>(
                  value: _waveform,
                  dropdownColor: AgiTheme.egaCardSurface,
                  style: const TextStyle(color: AgiTheme.egaAmber, fontSize: 12),
                  items: const [
                    DropdownMenuItem(value: WaveformType.pulseWidthModulation, child: Text('PWM Square')),
                    DropdownMenuItem(value: WaveformType.square, child: Text('Square')),
                    DropdownMenuItem(value: WaveformType.sawtooth, child: Text('Sawtooth')),
                    DropdownMenuItem(value: WaveformType.sine, child: Text('Sine')),
                    DropdownMenuItem(value: WaveformType.triangle, child: Text('Triangle')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _waveform = v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Reverb'),
                selected: _enableReverb,
                onSelected: (v) => setState(() => _enableReverb = v),
              ),
              const SizedBox(width: 16),
            ],

            const Text('Zoom: ', style: TextStyle(color: AgiTheme.egaMuted, fontSize: 12)),
            SizedBox(
              width: 100,
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

            const SizedBox(width: 16),

            ElevatedButton.icon(
              onPressed: _exportWav,
              icon: const Icon(Icons.file_download, size: 14),
              label: const Text('Render & Export WAV'),
            ),
          ],
        ),
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
            // Time / Tick Ruler
            _buildTimeRuler(totalTicks, trackWidth),
            const SizedBox(height: 16),

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
      ),
    );
  }

  Widget _buildTimeRuler(int totalTicks, double width) {
    return SizedBox(
      width: width,
      height: 24,
      child: CustomPaint(
        size: Size(width, 24),
        painter: _TimeRulerPainter(
          totalTicks: totalTicks,
          zoomScale: _zoomScale,
        ),
      ),
    );
  }

  Widget _buildVoiceTrack(int vIdx, ToneChannel voice, int totalTicks, double width) {
    final colors = [AgiTheme.egaCyan, AgiTheme.egaAmber, AgiTheme.egaMagenta];
    final trackColor = colors[vIdx % colors.length];

    return Column(
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
    );
  }

  Widget _buildNoiseTrack(NoiseChannel noise, int totalTicks, double width) {
    return Column(
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
    );
  }

  Widget _buildChannelSidebar() {
    final snd = _currentSound;

    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: AgiTheme.egaDarkSurface,
        border: Border(left: BorderSide(color: AgiTheme.egaBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AgiTheme.egaBorder)),
            ),
            child: const Row(
              children: [
                Icon(Icons.queue_music, size: 16, color: AgiTheme.egaAmber),
                SizedBox(width: 8),
                Text(
                  'VOICE TRACKS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: AgiTheme.egaAmber,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: snd == null
                ? const SizedBox.shrink()
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (var i = 0; i < snd.voices.length; i++)
                        _buildTrackCard(
                          'Tone Voice ${i + 1}',
                          snd.voices[i].notes.length,
                          '${snd.voices[i].length} ticks (${(snd.voices[i].length / 60.0).toStringAsFixed(2)}s)',
                          [AgiTheme.egaCyan, AgiTheme.egaAmber, AgiTheme.egaMagenta][i % 3],
                        ),
                      if (snd.noise != null)
                        _buildTrackCard(
                          'Noise Channel',
                          snd.noise!.noises.length,
                          '${snd.noise!.length} ticks (${(snd.noise!.length / 60.0).toStringAsFixed(2)}s)',
                          AgiTheme.egaRed,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackCard(String title, int count, String duration, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AgiTheme.egaBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.graphic_eq, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AgiTheme.egaWhite, fontSize: 12)),
                Text('$count notes • $duration', style: const TextStyle(color: AgiTheme.egaMuted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter that renders a time and tick ruler.
class _TimeRulerPainter extends CustomPainter {
  final int totalTicks;
  final double zoomScale;

  const _TimeRulerPainter({
    required this.totalTicks,
    required this.zoomScale,
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
  }

  @override
  bool shouldRepaint(covariant _TimeRulerPainter oldDelegate) =>
      oldDelegate.totalTicks != totalTicks || oldDelegate.zoomScale != zoomScale;
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
