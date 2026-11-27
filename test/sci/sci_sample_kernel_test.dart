// Stage 8: kernel digital-sample routing (Sound Blaster device,
// sample-only playback under every device, cue rewriting).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_sound.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';

Uint8List sineRecord() {
  final b = Uint8List(28);
  b[0] = 0; b[1] = 1; b[2] = 0; b[3] = 15; b[4] = 0; b[5] = 1; b[6] = 8; b[7] = 8; b[8] = 0;
  b[13] = 0; b[14] = 1; b[16] = 15; b[18] = 1; b[19] = 8; b[20] = 8; b[21] = 0;
  return b;
}

Uint8List bank1344() {
  final data = Uint8List(kSciAdlibBank48Size);
  for (var i = 0; i < kSciAdlibInstruments48; i++) {
    data.setRange(28 * i, 28 * i + 28, sineRecord());
  }
  return data;
}

/// 44-byte SCI0 sample header (rate u16 LE @14, length u16 LE @32)
/// followed by the PCM payload.
Uint8List samplePayload({required int rate, required int length, List<int>? pcm}) {
  final header = Uint8List(44);
  final bd = ByteData.sublistView(header);
  bd.setUint16(14, rate, Endian.little);
  bd.setUint16(32, length, Endian.little);
  final bytes = pcm ?? List.filled(length, 200);
  return (BytesBuilder()
        ..add(header)
        ..add(bytes))
      .toBytes();
}

/// Late SCI0 header (channel 0 AdLib|Tandy, channel 15 cues full).
Uint8List lateHeader({required int flags}) {
  final header = Uint8List(33);
  header[0] = flags;
  header[1] = 1;
  header[2] = 0x14;
  header[31] = 1;
  return header;
}

/// Sample-only sound: no notes at all, end-of-track at tick 0, then a
/// 44-byte sample with 11025 PCM bytes at 11025 Hz (duration 60 ticks).
Uint8List sampleOnlySound() {
  return (BytesBuilder()
        ..add(lateHeader(flags: 2))
        ..add([0x00, 0xFC])
        ..add(samplePayload(rate: 11025, length: 11025)))
      .toBytes();
}

/// Mixed sound: a real note (tick 0..30, cue 42 at tick 30, end at 40)
/// plus a 11025 Hz / 11025 byte sample (60 ticks).
Uint8List mixedSound() {
  return (BytesBuilder()
        ..add(lateHeader(flags: 2))
        ..add([
          0x00, 0xC0, 0,
          0x00, 0x90, 60, 100,
          0x1E, 0x80, 60, 0,
          0x00, 0xCF, 42,
          0x0A, 0xFC,
        ])
        ..add(samplePayload(rate: 11025, length: 11025)))
      .toBytes();
}

/// Plain FM sound (syntheticSound from sci_adlib_kernel_test.dart).
Uint8List fmSound() {
  final header = Uint8List(33);
  header[0] = 0;
  header[1] = 1;
  header[2] = 0x14;
  header[31] = 1;
  return (BytesBuilder()
        ..add(header)
        ..add([
          0x00, 0xC0, 0,
          0x00, 0x90, 60, 100,
          0x1E, 0x80, 60, 0,
          0x00, 0xCF, 42,
          0x0A, 0xFC,
        ]))
      .toBytes();
}

Directory makeVolumeDir(Uint8List soundBytes, {Uint8List? loosePatch}) {
  final dir = Directory.systemTemp.createTempSync('sci_sample_kernel_test_');
  final mapData = Uint8List(12);
  final mbd = ByteData.sublistView(mapData);
  mbd.setUint16(0, (SciResourceType.sound.typeCode << 11) | 1, Endian.little);
  mbd.setUint32(2, 0, Endian.little);
  mbd.setUint32(8, 0xFFFFFFFF, Endian.little);
  File('${dir.path}/RESOURCE.MAP').writeAsBytesSync(mapData);
  final volData = Uint8List(8 + soundBytes.length);
  final vbd = ByteData.sublistView(volData);
  vbd.setUint16(0, (SciResourceType.sound.typeCode << 11) | 1, Endian.little);
  vbd.setUint16(2, soundBytes.length + 4, Endian.little);
  vbd.setUint16(4, soundBytes.length, Endian.little);
  volData.setRange(8, 8 + soundBytes.length, soundBytes);
  File('${dir.path}/RESOURCE.000').writeAsBytesSync(volData);
  if (loosePatch != null) {
    final loose = Uint8List(2 + 4 + loosePatch.length);
    loose[0] = 0x89;
    loose[1] = 4;
    loose.setRange(6, 6 + loosePatch.length, loosePatch);
    File('${dir.path}/patch.003').writeAsBytesSync(loose);
  }
  return dir;
}

void main() {
  group('SciKernel digital samples (Stage 8)', () {
    late SciSegManager segMan;
    late SciKernel kernel;
    late SciVM vm;
    late AgiSoundPlayer player;
    late SciObject soundObj;
    late int stateSel;
    late int sigSel;
    late int loopSel;
    late Directory volumeDir;

    Future<void> settle() async {
      for (var i = 0; i < 100 && player.status != SoundPlayerStatus.playing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(player.status, SoundPlayerStatus.playing);
    }

    void play() {
      kernel.currentSciTicks = kernel.currentSciTicks;
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(1), soundObj.pos]);
    }

    void advanceTicks(int ticks) {
      for (var i = 0; i < ticks; i++) {
        kernel.advanceSciClock(hostHz: 60);
      }
    }

    void alignSlotClock() {
      kernel.currentSciTicks = kernel.currentSciTicks;
      kernel.soundSlots[soundObj.pos]!.startTick = kernel.currentSciTicks;
    }

    void useSound(Uint8List bytes, {bool withBank = true}) {
      try {
        if (volumeDir.existsSync()) volumeDir.deleteSync(recursive: true);
      } catch (_) {}
      volumeDir = makeVolumeDir(bytes, loosePatch: withBank ? bank1344() : null);
      kernel.volumeManager?.close();
      kernel.volumeManager = SciVolumeManager.fromDirectory(volumeDir.path);
    }

    void setLoop(int loop) => soundObj.setProp(segMan, loopSel, SciReg.fromInt(loop));

    setUp(() {
      segMan = SciSegManager();
      kernel = SciKernel();
      final selectors = SciSelectors();
      kernel.selectors = selectors;
      vm = SciVM(segManager: segMan, kernel: kernel, selectors: selectors);
      player = AgiSoundPlayer();
      kernel.soundPlayer = player;

      selectors.registerSelector('number', 100);
      selectors.registerSelector('loop', 101);
      selectors.registerSelector('priority', 102);
      selectors.registerSelector('state', 103);
      selectors.registerSelector('signal', 104);
      selectors.registerSelector('handle', 105);
      selectors.registerSelector('nodePtr', 106);
      stateSel = 103;
      sigSel = 104;
      loopSel = 101;

      final template = SciObject(
        pos: SciReg.nullReg,
        variables: [
          const SciReg.fromInt(1),
          const SciReg.fromInt(1),
          const SciReg.fromInt(0),
          const SciReg.fromInt(0),
          const SciReg.fromInt(0),
          SciReg.nullReg,
          SciReg.nullReg,
        ],
        baseVars: [100, 101, 102, 103, 104, 105, 106],
      );
      soundObj = segMan.cloneObject(template);
      useSound(fmSound());
    });

    tearDown(() {
      player.dispose();
      kernel.dispose();
      kernel.volumeManager?.close();
      if (volumeDir.existsSync()) volumeDir.deleteSync(recursive: true);
    });

    test('sample-only sound under legacyPsg plays the sample with rewritten cues',
        () async {
      useSound(sampleOnlySound());
      expect(kernel.sciMusicDevice, SciMusicDevice.legacyPsg);
      play();
      await settle();
      alignSlotClock();
      expect(kernel.activeSampleSource, isNotNull);
      expect(kernel.activeAdLibSource, isNull);
      expect(player.isGenericActive, isTrue);
      // Sample is 11025 bytes @ 11025 Hz => 60 ticks.
      final slot = kernel.soundSlots[soundObj.pos]!;
      expect(slot.cues.last.tick, 60);
      expect(slot.cues.last.signal, sciSoundFinished);

      // Finished cue fires at tick 60 and stops playback.
      soundObj.setProp(segMan, sigSel, const SciReg.fromInt(0));
      advanceTicks(60);
      kernel.updateSci0Cues(vm);
      expect(soundObj.getProp(segMan, sigSel).toUint16(), sciSoundFinished);
      expect(soundObj.getProp(segMan, stateSel).toUint16(), SciSoundStatus.stopped);
      expect(kernel.activeSampleSource, isNull);
    });

    test('sample-only sound under adLibOpl2 also plays the sample (not silence)',
        () async {
      useSound(sampleOnlySound());
      kernel.sciMusicDevice = SciMusicDevice.adLibOpl2;
      play();
      await settle();
      expect(kernel.activeSampleSource, isNotNull);
      expect(kernel.activeAdLibSource, isNull);
    });

    test('mixed sound under adLibOpl2 keeps the FM rendition and parsed cues',
        () async {
      useSound(mixedSound());
      kernel.sciMusicDevice = SciMusicDevice.adLibOpl2;
      play();
      await settle();
      expect(kernel.activeAdLibSource, isNotNull);
      expect(kernel.activeSampleSource, isNull);
      final slot = kernel.soundSlots[soundObj.pos]!;
      expect(slot.cues.last.tick, 40);
      expect(slot.cues.last.signal, sciSoundFinished);
    });

    test('mixed sound under soundBlaster uses the sample and rewrites cues',
        () async {
      useSound(mixedSound());
      kernel.sciMusicDevice = SciMusicDevice.soundBlaster;
      play();
      await settle();
      alignSlotClock();
      expect(kernel.activeSampleSource, isNotNull);
      expect(kernel.activeAdLibSource, isNull);
      final slot = kernel.soundSlots[soundObj.pos]!;
      // Cue 42 at tick 30 survives (<= 60); finished moves 40 -> 60.
      expect(slot.cues.map((c) => c.signal).toList(), [42, sciSoundFinished]);
      expect(slot.cues.last.tick, 60);
    });

    test('soundBlaster non-sample sound uses FM', () async {
      kernel.sciMusicDevice = SciMusicDevice.soundBlaster;
      play();
      await settle();
      expect(kernel.activeAdLibSource, isNotNull);
      expect(kernel.activeSampleSource, isNull);
    });

    test('soundBlaster without a bank still plays the sample', () async {
      useSound(sampleOnlySound(), withBank: false);
      kernel.sciMusicDevice = SciMusicDevice.soundBlaster;
      play();
      await settle();
      expect(kernel.activeSampleSource, isNotNull);
      expect(kernel.activeAdLibSource, isNull);
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(5), soundObj.pos]);
      expect(kernel.activeSampleSource, isNull);
    });

    test('soundBlaster without a bank falls back to legacy for FM sound',
        () async {
      useSound(fmSound(), withBank: false);
      kernel.sciMusicDevice = SciMusicDevice.soundBlaster;
      play();
      await settle();
      expect(kernel.activeAdLibSource, isNull);
      expect(kernel.activeSampleSource, isNull);
      expect(kernel.adLibFallbackReason, isNotNull);
      expect(player.isGenericActive, isFalse);
      expect(player.status, SoundPlayerStatus.playing);
    });

    test('sndMasterVolume reaches the active sample source', () async {
      useSound(sampleOnlySound());
      kernel.sciMusicDevice = SciMusicDevice.soundBlaster;
      play();
      await settle();
      final source = kernel.activeSampleSource!;
      expect(source.masterVolume, 15);
      final playerVolBefore = player.volume;
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(8), const SciReg.fromInt(7)]);
      expect(source.masterVolume, 7);
      expect(player.volume, playerVolBefore);
    });

    test('stop and stopAll clear the active sample source', () async {
      useSound(sampleOnlySound());
      play();
      await settle();
      expect(kernel.activeSampleSource, isNotNull);
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(5), soundObj.pos]);
      expect(kernel.activeSampleSource, isNull);

      play();
      await settle();
      expect(kernel.activeSampleSource, isNotNull);
      kernel.call(vm, 0x31, 1, [const SciReg.fromInt(12)]);
      expect(kernel.activeSampleSource, isNull);
    });

    test('muted sample-only sound keeps the legacy path and parsed cues',
        () async {
      useSound(sampleOnlySound());
      kernel.sciMusicDevice = SciMusicDevice.soundBlaster;
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(4), const SciReg.fromInt(0)]);
      play();
      await settle();
      expect(kernel.activeSampleSource, isNull);
      expect(kernel.activeAdLibSource, isNull);
      expect(player.isGenericActive, isFalse);
      final slot = kernel.soundSlots[soundObj.pos]!;
      expect(slot.cues.last.signal, sciSoundFinished);
      expect(slot.cues.last.tick, 0); // totalTicks 0 legacy timing
    });

    test('loop=-1 replays the sample and re-derives rewritten cues', () async {
      useSound(sampleOnlySound());
      setLoop(-1);
      play();
      await settle();
      alignSlotClock();
      final first = kernel.activeSampleSource!;
      soundObj.setProp(segMan, sigSel, const SciReg.fromInt(0));
      advanceTicks(60);
      kernel.updateSci0Cues(vm);
      expect(kernel.activeSampleSource, isNotNull);
      expect(identical(kernel.activeSampleSource, first), isFalse);
      final slot = kernel.soundSlots[soundObj.pos]!;
      expect(slot.cues.last.tick, 60);
      expect(slot.cues.last.signal, sciSoundFinished);
    });
  });
}
