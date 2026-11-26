// Stage 6b: SciKernel SCI AdLib (SciMusicDevice) wiring tests.
//
// Uses a synthetic temp-dir volume (sound 1 + optional loose patch.003)
// mirroring test/audio/sci_adlib_patch_test.dart patterns, and the
// kernel DoSound harness from test/sci/sci_sound_test.dart.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_patch.dart';
import 'package:flutter_agigame/audio/pcm_synthesizer.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_sound.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';

/// A 28-byte instrument record that is clearly audible (loud total
/// level, simple sine-ish tone), mirroring test/audio/sci_adlib_player_test.dart.
Uint8List sineRecord() {
  final b = Uint8List(28);
  // Total levels at 0: the driver's inverse-velocity math treats these
  // as the loudest setting (totalLevel 63 renders silent).
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

/// Late SCI0 sound: channel 0 selected for AdLib (0x04) and Tandy
/// (0x10); note C4 at tick 0..30, cue 42 at tick 10, end at tick 40.
Uint8List syntheticSound() {
  final header = Uint8List(33);
  header[0] = 0; // flags byte (not the 0x21 header size); late via length
  header[1] = 1; // channel 0 voice count
  header[2] = 0x14; // channel 0 play mask: AdLib | Tandy
  header[31] = 1; // channel 15 voice count
  header[32] = 0; // channel 15 mask (cues are handled regardless)
  final bb = BytesBuilder()
    ..add(header)
    ..add([
      // Program change selects a bank patch; without it the driver's
      // default patch is never programmed (silent until PC).
      0x00, 0xC0, 0, // program change ch 0 -> patch 0
      0x00, 0x90, 60, 100, // note on C4
      0x1E, 0x80, 60, 0, // note off at tick 30
      0x00, 0xCF, 42, // cue 42 at tick 30
      0x0A, 0xFC, // end of track at tick 40
    ]);
  return bb.toBytes();
}

Directory makeVolumeDir(Uint8List soundBytes, {Uint8List? loosePatch}) {
  final dir = Directory.systemTemp.createTempSync('sci_adlib_kernel_test_');
  // RESOURCE.MAP: one entry (sound 1) + sentinel.
  final mapData = Uint8List(12);
  final mbd = ByteData.sublistView(mapData);
  mbd.setUint16(0, (SciResourceType.sound.typeCode << 11) | 1, Endian.little);
  mbd.setUint32(2, 0, Endian.little);
  mbd.setUint32(8, 0xFFFFFFFF, Endian.little);
  File('${dir.path}/RESOURCE.MAP').writeAsBytesSync(mapData);
  // RESOURCE.000: one uncompressed resource.
  final volData = Uint8List(8 + soundBytes.length);
  final vbd = ByteData.sublistView(volData);
  vbd.setUint16(0, (SciResourceType.sound.typeCode << 11) | 1, Endian.little);
  vbd.setUint16(2, soundBytes.length + 4, Endian.little);
  vbd.setUint16(4, soundBytes.length, Endian.little);
  vbd.setUint16(6, 0, Endian.little);
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
  group('SciKernel AdLib device (Stage 6b)', () {
    late SciSegManager segMan;
    late SciKernel kernel;
    late SciVM vm;
    late AgiSoundPlayer player;
    late SciObject soundObj;
    late int stateSel;
    late int sigSel;
    late int loopSel;
    late Directory volumeDir;

    setUp(() {
      volumeDir = makeVolumeDir(syntheticSound(), loosePatch: bank1344());
      segMan = SciSegManager();
      kernel = SciKernel();
      final selectors = SciSelectors();
      kernel.selectors = selectors;
      vm = SciVM(segManager: segMan, kernel: kernel, selectors: selectors);
      player = AgiSoundPlayer();
      kernel.soundPlayer = player;
      kernel.volumeManager = SciVolumeManager.fromDirectory(volumeDir.path);

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
          const SciReg.fromInt(1), // number
          const SciReg.fromInt(1), // loop
          const SciReg.fromInt(0), // priority
          const SciReg.fromInt(0), // state
          const SciReg.fromInt(0), // signal
          SciReg.nullReg, // handle
          SciReg.nullReg, // nodePtr
        ],
        baseVars: [100, 101, 102, 103, 104, 105, 106],
      );
      soundObj = segMan.cloneObject(template);
    });

    tearDown(() {
      player.dispose();
      kernel.dispose();
      kernel.volumeManager?.close();
      if (volumeDir.existsSync()) volumeDir.deleteSync(recursive: true);
    });

    void setLoop(int loop) =>
        soundObj.setProp(segMan, loopSel, SciReg.fromInt(loop));

    /// `play`/`playPcmSource` complete asynchronously (sink
    /// initialization); poll for the playing state instead of a single
    /// fixed delay so the test is robust under full-suite load.
    Future<void> settle() async {
      for (var i = 0; i < 100 && player.status != SoundPlayerStatus.playing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(player.status, SoundPlayerStatus.playing);
    }

    void play() {
      // Align the host-stepped clock with wall time (currentSciTicks is
      // max(host, wall)); otherwise the wall skew captured at play makes
      // cue math nondeterministic under full-suite load.
      kernel.currentSciTicks = kernel.currentSciTicks;
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(1), soundObj.pos]);
    }

    void advanceTicks(int ticks) {
      // hostHz 60 => 1 tick per advance.
      for (var i = 0; i < ticks; i++) {
        kernel.advanceSciClock(hostHz: 60);
      }
    }

    /// Re-baselines the slot clock after [settle]'s wall time so stepped
    /// advances are exact regardless of scheduling load.
    void alignSlotClock() {
      kernel.currentSciTicks = kernel.currentSciTicks;
      kernel.soundSlots[soundObj.pos]!.startTick = kernel.currentSciTicks;
    }

    test('adLibOpl2 play uses the AdLib source; cues and finish work',
        () async {
      kernel.sciMusicDevice = SciMusicDevice.adLibOpl2;
      play();
      await settle();
      alignSlotClock();
      expect(kernel.activeAdLibSource, isNotNull);
      expect(kernel.adLibBankProvenance, SciAdlibBankProvenance.loosePatch);
      expect(kernel.adLibFallbackReason, isNull);
      expect(player.isGenericActive, isTrue);
      expect(player.status, SoundPlayerStatus.playing);

      // Cue 42 at tick 30.
      advanceTicks(30);
      kernel.updateSci0Cues(vm);
      expect(soundObj.getProp(segMan, sigSel).toUint16(), 42);
      expect(kernel.activeAdLibSource, isNotNull);

      // Finished at tick 40 stops playback and clears the source.
      soundObj.setProp(segMan, sigSel, const SciReg.fromInt(0));
      advanceTicks(10);
      kernel.updateSci0Cues(vm);
      expect(soundObj.getProp(segMan, sigSel).toUint16(), sciSoundFinished);
      expect(soundObj.getProp(segMan, stateSel).toUint16(), SciSoundStatus.stopped);
      expect(kernel.activeAdLibSource, isNull);
    });

    test('missing bank falls back to legacy and records the reason',
        () async {
      final bareDir = makeVolumeDir(syntheticSound());
      kernel.volumeManager?.close();
      kernel.volumeManager = SciVolumeManager.fromDirectory(bareDir.path);
      addTearDown(() {
        kernel.volumeManager?.close();
        if (bareDir.existsSync()) bareDir.deleteSync(recursive: true);
      });

      kernel.sciMusicDevice = SciMusicDevice.adLibOpl2;
      play();
      await settle();
      alignSlotClock();
      expect(kernel.activeAdLibSource, isNull);
      expect(kernel.adLibBankProvenance, SciAdlibBankProvenance.unavailable);
      expect(kernel.adLibFallbackReason, isNotNull);
      expect(player.isGenericActive, isFalse);
      expect(player.status, SoundPlayerStatus.playing);

      // Legacy cues still work.
      advanceTicks(30);
      kernel.updateSci0Cues(vm);
      expect(soundObj.getProp(segMan, sigSel).toUint16(), 42);
    });

    test('legacyPsg (default) never creates an AdLib source', () async {
      expect(kernel.sciMusicDevice, SciMusicDevice.legacyPsg);
      play();
      await settle();
      expect(kernel.activeAdLibSource, isNull);
      expect(kernel.adLibBankProvenance, isNull);
      expect(kernel.adLibFallbackReason, isNull);
      expect(player.isGenericActive, isFalse);
      expect(player.status, SoundPlayerStatus.playing);

      // Legacy master-volume routing is untouched.
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(8), const SciReg.fromInt(10)]);
      expect(player.volume, closeTo(10.0 / 15.0, 0.01));
    });

    test('master volume subop while AdLib active reaches the source',
        () async {
      int peakOf(Int16List b) {
        var p = 0;
        for (final s in b) {
          if (s.abs() > p) p = s.abs();
        }
        return p;
      }

      kernel.sciMusicDevice = SciMusicDevice.adLibOpl2;
      play();
      await settle();
      final source = kernel.activeAdLibSource!;
      // Audible at the initial SCI master volume (15).
      var buf = Int16List(4096);
      source.renderInto(buf, 2048);
      final loudPeak = peakOf(buf);
      expect(loudPeak, greaterThan(10000));

      // SCI master volume 0 attenuates the driver output strongly
      // (residual peak stays well below a few percent of loudPeak),
      // while player-level volume keeps carrying the user's own gain.
      final playerVolBefore = player.volume;
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(8), const SciReg.fromInt(0)]);
      expect(player.volume, playerVolBefore);
      // Skip the transition block (reprogrammed velocities still
      // settling), then sample steady state.
      source.renderInto(Int16List(4096), 2048);
      buf = Int16List(4096);
      source.renderInto(buf, 2048);
      final quietPeak = peakOf(buf);
      expect(quietPeak, greaterThan(0)); // residual, not a full stop
      expect(quietPeak, lessThan(loudPeak ~/ 10));
    });

    test('polyphony: 9 for adLibOpl2, legacy values otherwise', () {
      kernel.sciMusicDevice = SciMusicDevice.adLibOpl2;
      kernel.soundMode = PcmPlaybackMode.enhanced;
      expect(
        kernel.call(vm, 0x31, 1, [const SciReg.fromInt(11)]).toUint16(),
        9,
      );
      kernel.soundMode = PcmPlaybackMode.ibmPcSingleChannel;
      expect(
        kernel.call(vm, 0x31, 1, [const SciReg.fromInt(11)]).toUint16(),
        9,
      );
      kernel.sciMusicDevice = SciMusicDevice.legacyPsg;
      kernel.soundMode = PcmPlaybackMode.enhanced;
      expect(
        kernel.call(vm, 0x31, 1, [const SciReg.fromInt(11)]).toUint16(),
        16,
      );
    });

    test('loop=-1 replays with a NEW AdLib source instance', () async {
      kernel.sciMusicDevice = SciMusicDevice.adLibOpl2;
      setLoop(-1);
      play();
      await settle();
      alignSlotClock();
      final first = kernel.activeAdLibSource!;
      // Drain cue 42, then hit the finish cue -> loop replay.
      advanceTicks(30);
      kernel.updateSci0Cues(vm);
      soundObj.setProp(segMan, sigSel, const SciReg.fromInt(0));
      advanceTicks(10);
      kernel.updateSci0Cues(vm);
      expect(kernel.activeAdLibSource, isNotNull);
      expect(identical(kernel.activeAdLibSource, first), isFalse);
      expect(player.isGenericActive, isTrue);
      expect(soundObj.getProp(segMan, stateSel).toUint16(), SciSoundStatus.playing);
    });

    test('stop subop clears the active source', () async {
      kernel.sciMusicDevice = SciMusicDevice.adLibOpl2;
      play();
      await settle();
      expect(kernel.activeAdLibSource, isNotNull);
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(5), soundObj.pos]);
      expect(kernel.activeAdLibSource, isNull);
    });

    test('device switch mid-sound does not swap the playing source',
        () async {
      kernel.sciMusicDevice = SciMusicDevice.adLibOpl2;
      play();
      await settle();
      final first = kernel.activeAdLibSource!;
      kernel.sciMusicDevice = SciMusicDevice.legacyPsg;
      expect(identical(kernel.activeAdLibSource, first), isTrue);
      expect(player.isGenericActive, isTrue);

      // Next play uses the new device.
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(5), soundObj.pos]);
      play();
      await settle();
      expect(kernel.activeAdLibSource, isNull);
      expect(player.isGenericActive, isFalse);

      // And switching back is likewise next-sound only.
      kernel.sciMusicDevice = SciMusicDevice.adLibOpl2;
      expect(kernel.activeAdLibSource, isNull);
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(5), soundObj.pos]);
      play();
      await settle();
      expect(kernel.activeAdLibSource, isNotNull);
    });

    test('muted playback takes the legacy timer path, no AdLib source',
        () async {
      kernel.sciMusicDevice = SciMusicDevice.adLibOpl2;
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(4), const SciReg.fromInt(0)]);
      play();
      await settle();
      expect(kernel.activeAdLibSource, isNull);
      expect(player.isGenericActive, isFalse);
      expect(player.status, SoundPlayerStatus.playing);
    });
  });
}
