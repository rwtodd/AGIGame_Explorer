// Stage 7: kernel session debug-override plumbing.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/audio/agi_sound_player.dart';
import 'package:flutter_agigame/audio/opl/sci_adlib_driver.dart';
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
  final data = Uint8List(1344);
  for (var i = 0; i < 48; i++) {
    data.setRange(28 * i, 28 * i + 28, sineRecord());
  }
  return data;
}

Uint8List syntheticSound() {
  final header = Uint8List(33);
  header[0] = 0;
  header[1] = 1;
  header[2] = 0x14;
  header[31] = 1;
  header[32] = 0;
  final bb = BytesBuilder()
    ..add(header)
    ..add([
      0x00, 0xC0, 0,
      0x00, 0x90, 60, 100,
      0x1E, 0x80, 60, 0,
      0x00, 0xCF, 42,
      0x0A, 0xFC,
    ]);
  return bb.toBytes();
}

Directory makeVolumeDir(Uint8List soundBytes, {Uint8List? loosePatch}) {
  final dir = Directory.systemTemp.createTempSync('sci_adlib_debug_test_');
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
  group('SciKernel AdLib debug overrides (Stage 7)', () {
    late SciSegManager segMan;
    late SciKernel kernel;
    late SciVM vm;
    late AgiSoundPlayer player;
    late SciObject soundObj;
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
    });

    tearDown(() {
      player.dispose();
      kernel.volumeManager?.close();
      if (volumeDir.existsSync()) volumeDir.deleteSync(recursive: true);
    });

    Future<void> settle() async {
      for (var i = 0; i < 100 && player.status != SoundPlayerStatus.playing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    void play() {
      kernel.currentSciTicks = kernel.currentSciTicks;
      kernel.call(vm, 0x31, 2, [const SciReg.fromInt(1), soundObj.pos]);
    }

    test('stored overrides are passed into a newly started AdLib source', () async {
      kernel.sciMusicDevice = SciMusicDevice.adLibOpl2;
      kernel.setSciAdLibDebugOverrides(
        SciAdLibDebugOverrides(gainSteps: {2: 9}, stereoWidth: 0.3),
      );
      play();
      await settle();
      final source = kernel.activeAdLibSource;
      expect(source, isNotNull);
      expect(source!.debugOverrides.gainSteps, {2: 9});
      expect(source.debugOverrides.stereoWidth, 0.3);
    });

    test('setter applies to the active source immediately; reset keeps them', () async {
      kernel.sciMusicDevice = SciMusicDevice.adLibOpl2;
      play();
      await settle();
      expect(kernel.activeAdLibSource, isNotNull);
      kernel.setSciAdLibDebugOverrides(
        SciAdLibDebugOverrides(mutedChannels: {3}),
      );
      expect(
        kernel.activeAdLibSource!.debugDriver.debugOverrides.mutedChannels,
        {3},
      );
      expect(kernel.sciAdLibDebugOverrides.mutedChannels, {3});
      kernel.reset();
      expect(kernel.sciAdLibDebugOverrides.mutedChannels, {3});
    });

    test('ensureAdLibBankLoaded returns the cached bank', () {
      final load = kernel.ensureAdLibBankLoaded();
      expect(load.bank, isNotNull);
      expect(load.bank!.instrumentCount, 48);
    });
  });
}
