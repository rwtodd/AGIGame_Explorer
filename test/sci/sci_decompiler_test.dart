import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/script/sci_decompiler.dart';
import 'package:flutter_agigame/sci/script/sci_disassembler.dart';

void main() {
  group('SciDecompiler Unit Tests', () {
    test('Decompiles PQ2 Script 0 into Sierra Script Language representation', () {
      final pq2Dir = Directory('reference_games/police-quest-2');
      if (!pq2Dir.existsSync()) {
        markTestSkipped('PQ2 reference directory missing');
        return;
      }

      final volumeMgr = SciVolumeManager.fromDirectory(pq2Dir.path);
      final segMan = SciSegManager();
      final kernel = SciKernel();
      final selectors = SciSelectors();

      // Load vocabs
      final v996 = volumeMgr.getResource(SciResourceType.vocab, 996);
      segMan.loadClassTable(v996);

      final v997 = volumeMgr.getResource(SciResourceType.vocab, 997);
      selectors.loadVocab997(v997);

      final script0 = segMan.instantiateScript(0, volumeMgr);

      final ctx = SciDisassemblyContext(
        script: script0,
        selectors: selectors,
        segManager: segMan,
        kernel: kernel,
      );

      final decompiler = SciDecompiler(ctx);
      final decompiledText = decompiler.decompileScript();

      expect(decompiledText.isNotEmpty, isTrue);
      expect(decompiledText.contains('(script 0)'), isTrue);
      expect(decompiledText.contains('(exports'), isTrue);
      expect(decompiledText.contains('(local'), isTrue);
      expect(decompiledText.contains('instance PQ of'), isTrue);
      expect(decompiledText.contains('(properties'), isTrue);
      expect(decompiledText.contains('(method'), isTrue);
    });
  });
}
