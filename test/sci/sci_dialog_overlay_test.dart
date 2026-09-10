import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_game_engine.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';
import 'package:flutter_agigame/sci/engine/sci_window_manager.dart';
import 'package:flutter_agigame/sci/loader/resource_type.dart';
import 'package:flutter_agigame/sci/loader/volume.dart';
import 'package:flutter_agigame/sci/parser/sci_vocab.dart';
import 'package:flutter_agigame/sci/script/sci_object.dart';
import 'package:flutter_agigame/ui/models/sci_window_overlay.dart';

class _FakeVolumeManager implements SciVolumeManager {
  final Map<int, Uint8List> textResources;
  _FakeVolumeManager(this.textResources);

  @override
  Uint8List getResource(SciResourceType type, int number) {
    if (type == SciResourceType.text && textResources.containsKey(number)) {
      return textResources[number]!;
    }
    throw Exception('Resource $type.$number not found');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}


void main() {
  group('SciWindowManager Tests', () {
    test('openWindow and closeWindow manage window stack and ports', () {
      final wm = SciWindowManager();
      expect(wm.getPort(), equals(SciWindowManager.picWindId));
      expect(wm.windowStack, isEmpty);

      // Open a window
      final wnd1 = wm.openWindow(
        dims: const Rect.fromLTWH(50, 40, 200, 100),
        title: 'Inventory',
        colorPen: 1,
        colorBack: 15,
      );

      expect(wnd1.id, equals(SciWindowManager.firstScriptWindowId));
      expect(wm.getPort(), equals(wnd1.id));
      expect(wm.windowStack.length, equals(1));
      expect(wm.currentPort.id, equals(wnd1.id));

      // Open a second window
      final wnd2 = wm.openWindow(
        dims: const Rect.fromLTWH(80, 60, 150, 80),
        title: 'Dialog',
      );

      expect(wnd2.id, equals(SciWindowManager.firstScriptWindowId + 1));
      expect(wm.getPort(), equals(wnd2.id));
      expect(wm.windowStack.length, equals(2));

      // Close top window
      final closed2 = wm.closeWindow(wnd2.id);
      expect(closed2, isTrue);
      expect(wm.windowStack.length, equals(1));
      expect(wm.getPort(), equals(wnd1.id));

      // Close remaining window
      final closed1 = wm.closeWindow(wnd1.id);
      expect(closed1, isTrue);
      expect(wm.windowStack, isEmpty);
      expect(wm.getPort(), equals(SciWindowManager.picWindId));
    });

    test('openWindow clips dimensions against screen bounds (320x200)', () {
      final wm = SciWindowManager();
      final wnd = wm.openWindow(
        dims: const Rect.fromLTWH(250, 150, 100, 80), // Exceeds 320x200
      );

      expect(wnd.dims.right, lessThanOrEqualTo(320));
      expect(wnd.dims.bottom, lessThanOrEqualTo(200));
      expect(wnd.dims.left, greaterThanOrEqualTo(0));
      expect(wnd.dims.top, greaterThanOrEqualTo(0));
    });

    test('controls can be added, updated, and converted to overlays', () {
      final wm = SciWindowManager();
      final wnd = wm.openWindow(dims: const Rect.fromLTWH(20, 20, 200, 100));

      final btn = const SciButtonControl(
        rect: Rect.fromLTWH(10, 10, 50, 20),
        text: 'OK',
      );
      wm.setControl(controlRefOffset: 0x100, controlItem: btn);

      expect(wnd.controls.length, equals(1));
      expect((wnd.controls.first as SciButtonControl).text, equals('OK'));

      // Update control (e.g. hilite)
      final btnFocused = const SciButtonControl(
        rect: Rect.fromLTWH(10, 10, 50, 20),
        text: 'OK',
        isFocused: true,
      );
      wm.setControl(controlRefOffset: 0x100, controlItem: btnFocused);

      expect(wnd.controls.length, equals(1));
      expect((wnd.controls.first as SciButtonControl).isFocused, isTrue);

      final overlays = wm.toOverlays();
      expect(overlays.length, equals(1));
      expect(overlays.first.controls.length, equals(1));
    });

    test('transient display items can be added and restored with handle', () {
      final wm = SciWindowManager();
      final wnd = wm.openWindow(dims: const Rect.fromLTWH(0, 0, 320, 200));

      const item = SciTextControl(
        rect: Rect.fromLTWH(10, 10, 100, 12),
        text: 'Score: 100',
      );
      final handle = wm.addDisplay(item, saveUnder: true);
      expect(handle, greaterThan(0));
      expect(wnd.controls.contains(item), isTrue);

      wm.restoreDisplay(handle);
      expect(wnd.controls.contains(item), isFalse);
    });
  });

  group('SciSegManager Word Access Tests', () {
    test('writeWord and readWord work on globals', () {
      final segMan = SciSegManager();
      segMan.globals = List.filled(10, const SciReg.fromInt(0));

      final globalPtr = const SciReg.pointer(1, 4); // global 2
      segMan.writeWord(globalPtr, 0, const SciReg.fromInt(42));
      segMan.writeWord(globalPtr, 1, const SciReg.fromInt(99)); // global 3

      expect(segMan.readWord(globalPtr, 0).toUint16(), equals(42));
      expect(segMan.readWord(globalPtr, 1).toUint16(), equals(99));
      expect(segMan.globals[2].toUint16(), equals(42));
      expect(segMan.globals[3].toUint16(), equals(99));
    });

    test('writeWord and readWord work on stack temps/params', () {
      final segMan = SciSegManager();
      final stack = <SciReg>[
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
      ];

      final tempPtr = const SciReg.pointer(SciSegManager.listSegmentId, 2); // stack[1]
      segMan.writeWord(tempPtr, 0, const SciReg.fromInt(101), stack: stack);
      segMan.writeWord(tempPtr, 1, const SciReg.fromInt(202), stack: stack);

      expect(segMan.readWord(tempPtr, 0, stack: stack).toUint16(), equals(101));
      expect(segMan.readWord(tempPtr, 1, stack: stack).toUint16(), equals(202));
      expect(stack[1].toUint16(), equals(101));
      expect(stack[2].toUint16(), equals(202));
    });

    test('writeWord and readWord work on hunk buffers', () {
      final segMan = SciSegManager();
      final hunkReg = segMan.allocHunk(16);

      segMan.writeWord(hunkReg, 0, const SciReg.fromInt(0x1234));
      segMan.writeWord(hunkReg, 1, const SciReg.fromInt(0x5678));

      expect(segMan.readWord(hunkReg, 0).toUint16(), equals(0x1234));
      expect(segMan.readWord(hunkReg, 1).toUint16(), equals(0x5678));
    });

    test('writeString and getString pack characters into 16-bit stack words', () {
      final segMan = SciSegManager();
      final stack = <SciReg>[
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
      ];

      final stackPtr = const SciReg.pointer(SciSegManager.listSegmentId, 2); // stack[1]
      segMan.writeString(stackPtr, 'AB', stack: stack);

      // Verify that 'A' (65) and 'B' (66) are packed into stack[1] as 0x4241
      expect(stack[1].toUint16(), equals(65 | (66 << 8)));
      // And null terminator is at even byte in stack[2]
      expect(stack[2].toUint16() & 0xFF, equals(0));

      expect(segMan.getString(stackPtr, stack: stack), equals('AB'));
      expect(segMan.strlen(stackPtr, stack: stack), equals(2));
    });
  });

  group('SciKernel Window & Control Kernel Opcodes', () {
    late SciKernel kernel;
    late SciSegManager segMan;
    late SciVM vm;

    setUp(() {
      kernel = SciKernel();
      segMan = SciSegManager();
      vm = SciVM(kernel: kernel, segManager: segMan, selectors: kernel.selectors);
      kernel.windowManager.reset();
    });

    test('kNewWindow and kDisposeWindow invoke callbacks and manage ports', () {
      int? openedId;
      int? disposedId;
      kernel.onNewWindow = (id, top, left, bottom, right) {
        openedId = id;
      };
      kernel.onDisposeWindow = (id) {
        disposedId = id;
      };

      // (kNewWindow 10 20 80 160 "Test Title" 0 15 1 15)
      final titleReg = vm.segManager.allocString('Test Title');
      final res = kernel.call(
        vm,
        0x13,
        8,
        [
          const SciReg.fromInt(10), // top
          const SciReg.fromInt(20), // left
          const SciReg.fromInt(80), // bottom
          const SciReg.fromInt(160), // right
          titleReg,
          const SciReg.fromInt(0), // style
          const SciReg.fromInt(15), // priority
          const SciReg.fromInt(1), // colorPen
        ],
      );

      expect(res.toUint16(), equals(openedId));
      expect(kernel.currentPort, equals(res.toUint16()));
      expect(kernel.windowManager.windowStack.length, equals(1));
      expect(kernel.windowManager.windowStack.first.title, equals('Test Title'));

      // kDisposeWindow
      kernel.call(vm, 0x16, 1, [res]);
      expect(disposedId, equals(res.toUint16()));
      expect(kernel.windowManager.windowStack, isEmpty);
      expect(kernel.currentPort, equals(SciWindowManager.picWindId));
    });

    test('kTextSize calculates wrapped dimensions and writes rectangle', () {
      final destPtr = vm.segManager.allocHunk(8);
      final textPtr = vm.segManager.allocString('Hello World of Sierra SCI');

      // (kTextSize @dest textPtr fontId=0 maxWidth=100)
      kernel.call(vm, 0x1A, 4, [
        destPtr,
        textPtr,
        const SciReg.fromInt(0),
        const SciReg.fromInt(100),
      ]);

      final top = vm.segManager.readWord(destPtr, 0).toUint16();
      final left = vm.segManager.readWord(destPtr, 1).toUint16();
      final bottom = vm.segManager.readWord(destPtr, 2).toUint16();
      final right = vm.segManager.readWord(destPtr, 3).toUint16();

      expect(top, equals(0));
      expect(left, equals(0));
      expect(bottom, greaterThan(0)); // Height
      expect(right, greaterThan(0)); // Width
      expect(right, lessThanOrEqualTo(100));
    });

    test('kDrawControl and kHiliteControl add controls to active window', () {
      // Create window
      kernel.call(vm, 0x13, 4, [
        const SciReg.fromInt(20),
        const SciReg.fromInt(20),
        const SciReg.fromInt(100),
        const SciReg.fromInt(200),
      ]);

      // Construct a mock control object in VM
      final controlReg = const SciReg.pointer(1, 0);
      final textReg = vm.segManager.allocString('OK');
      final obj = SciObject(
        pos: controlReg,
        variables: [
          const SciReg.fromInt(0), // 0: species
          const SciReg.fromInt(0), // 1: superClass
          const SciReg.fromInt(0), // 2: info
          const SciReg.fromInt(0), // 3: name
          const SciReg.fromInt(0), // 4: y
          const SciReg.fromInt(0), // 5: x
          const SciReg.fromInt(0), // 6: view
          const SciReg.fromInt(0), // 7: loop
          const SciReg.fromInt(0), // 8: cel
          const SciReg.fromInt(0), // 9: underBits
          const SciReg.fromInt(50), // 10: nsTop
          const SciReg.fromInt(40), // 11: nsLeft
          const SciReg.fromInt(70), // 12: nsBottom
          const SciReg.fromInt(100), // 13: nsRight
          const SciReg.fromInt(0), // 14: lsTop
          const SciReg.fromInt(0), // 15: lsLeft
          const SciReg.fromInt(0), // 16: lsBottom
          const SciReg.fromInt(0), // 17: lsRight
          const SciReg.fromInt(0), // 18: signal
          const SciReg.fromInt(0), // 19: illegalBits
          const SciReg.fromInt(0), // 20: brTop
          const SciReg.fromInt(0), // 21: brLeft
          const SciReg.fromInt(0), // 22: brBottom
          const SciReg.fromInt(0), // 23: brRight
          const SciReg.fromInt(1), // 24: type (Button)
          const SciReg.fromInt(0), // 25: state
          const SciReg.fromInt(0), // 26: font
          textReg, // 27: text
        ],
        baseVars: List.generate(28, (i) => i),
      );

      // Set standard selectors for test
      kernel.selectors.type = 24;
      kernel.selectors.state = 25;
      kernel.selectors.font = 26;
      kernel.selectors.text = 27;

      // Register obj in segManager
      vm.segManager.clones[controlReg.offset] = obj;
      final cloneReg = SciReg.pointer(SciSegManager.cloneSegmentId, controlReg.offset);

      // (kDrawControl cloneReg)
      kernel.call(vm, 0x17, 1, [cloneReg]);

      final wnd = kernel.windowManager.windowStack.first;
      expect(wnd.controls.length, equals(1));
      expect(wnd.controls.first, isA<SciButtonControl>());
      final btn = wnd.controls.first as SciButtonControl;
      expect(btn.text, equals('OK'));
      expect(btn.isFocused, isFalse);

      // (kHiliteControl cloneReg)
      kernel.call(vm, 0x18, 1, [cloneReg]);
      final hilitedBtn = wnd.controls.first as SciButtonControl;
      expect(hilitedBtn.isFocused, isTrue);
    });

    test('kDisplay creates and restores text overlays with tag parameters', () {
      // Create window
      kernel.call(vm, 0x13, 4, [
        const SciReg.fromInt(0),
        const SciReg.fromInt(0),
        const SciReg.fromInt(200),
        const SciReg.fromInt(320),
      ]);

      final textReg = vm.segManager.allocString('Important Alert');

      // (kDisplay textReg p_at 30 40 p_color 4 p_save)
      final handleReg = kernel.call(vm, 0x1B, 7, [
        textReg,
        const SciReg.fromInt(100), // p_at
        const SciReg.fromInt(30),
        const SciReg.fromInt(40),
        const SciReg.fromInt(102), // p_color
        const SciReg.fromInt(4), // Red
        const SciReg.fromInt(107), // p_save
      ]);

      final handle = handleReg.toUint16();
      expect(handle, greaterThan(0));

      final wnd = kernel.windowManager.windowStack.first;
      expect(wnd.controls.length, equals(1));
      final textControl = wnd.controls.first as SciTextControl;
      expect(textControl.text, equals('Important Alert'));
      expect(textControl.colorPen, equals(4));
      expect(textControl.rect.left, equals(30.0));
      expect(textControl.rect.top, equals(40.0));

      // (kDisplay 0 p_restore handle)
      kernel.call(vm, 0x1B, 3, [
        const SciReg.fromInt(0),
        const SciReg.fromInt(108), // p_restore
        SciReg.fromInt(handle),
      ]);

      expect(wnd.controls, isEmpty);
    });

    test('kGetFarText retrieves message from volumeManager and writes to stack buffer', () {
      final fakeVm = _FakeVolumeManager({
        35: Uint8List.fromList('Line zero\x00You don\'t have it.\x00Line two\x00'.codeUnits),
      });
      kernel.volumeManager = fakeVm;

      // Allocate space on stack:
      final destPtr = const SciReg.pointer(SciSegManager.listSegmentId, 2); // stack[1]

      // (kGetFarText 35 1 destPtr)
      final res = kernel.call(vm, 0x4D, 3, [
        const SciReg.fromInt(35),
        const SciReg.fromInt(1),
        destPtr,
      ]);

      expect(res, equals(destPtr));
      expect(vm.segManager.getString(destPtr, stack: vm.stack), equals('You don\'t have it.'));
    });

    test('kFormat formats strings with specifiers and width padding into destination buffer', () {
      final destPtr = vm.segManager.allocHunk(64);
      final strPtr = vm.segManager.allocString('Sierra');

      // (kFormat destPtr "%s scored %d points (%x hex, char %c) [%-10s]" strPtr 42 255 65 strPtr)
      final formatPtr = vm.segManager.allocString('%s scored %d points (%x hex, char %c) [%-10s]');

      final res = kernel.call(vm, 0x4C, 7, [
        destPtr,
        formatPtr,
        strPtr,
        const SciReg.fromInt(42),
        const SciReg.fromInt(255),
        const SciReg.fromInt(65),
        strPtr,
      ]);

      expect(res, equals(destPtr));
      final formatted = vm.segManager.getString(destPtr);
      expect(formatted, equals('Sierra scored 42 points (ff hex, char A) [Sierra    ]'));
    });

    test('kEditControl modifies destination buffer in-place on keystrokes and moves cursor', () {
      final bufferPtr = vm.segManager.allocHunk(32);
      vm.segManager.writeString(bufferPtr, 'l');

      kernel.selectors.type = 24;
      kernel.selectors.state = 25;
      kernel.selectors.cursor = 26;
      kernel.selectors.max = 27;
      kernel.selectors.text = 28;
      kernel.selectors.message = 29;

      // Create EditControl object
      final editObjReg = const SciReg.pointer(SciSegManager.cloneSegmentId, 1);
      final editObj = SciObject(
        pos: editObjReg,
        variables: List.filled(16, const SciReg.fromInt(0)),
      );
      vm.segManager.clones[1] = editObj;
      editObj.baseVars.addAll([
        kernel.selectors.type,
        kernel.selectors.state,
        kernel.selectors.cursor,
        kernel.selectors.max,
        kernel.selectors.text,
        kernel.selectors.nsLeft,
        kernel.selectors.nsTop,
        kernel.selectors.nsRight,
        kernel.selectors.nsBottom,
      ]);
      editObj.setProp(vm.segManager, kernel.selectors.type, const SciReg.fromInt(3)); // DEdit
      editObj.setProp(vm.segManager, kernel.selectors.cursor, const SciReg.fromInt(1));
      editObj.setProp(vm.segManager, kernel.selectors.max, const SciReg.fromInt(20));
      editObj.setProp(vm.segManager, kernel.selectors.text, bufferPtr);

      // Create Event object
      final eventReg = const SciReg.pointer(SciSegManager.cloneSegmentId, 2);
      final eventObj = SciObject(
        pos: eventReg,
        variables: List.filled(16, const SciReg.fromInt(0)),
      );
      vm.segManager.clones[2] = eventObj;
      eventObj.baseVars.addAll([kernel.selectors.type, kernel.selectors.message]);

      // Post 'o'
      eventObj.setProp(vm.segManager, kernel.selectors.type, const SciReg.fromInt(SciEventType.keyDown));
      eventObj.setProp(vm.segManager, kernel.selectors.message, const SciReg.fromInt(111)); // 'o'
      kernel.call(vm, 0x19, 2, [editObjReg, eventReg]);

      expect(vm.segManager.getString(bufferPtr), equals('lo'));
      expect(editObj.getProp(vm.segManager, kernel.selectors.cursor).toUint16(), equals(2));

      // Post 'o', 'k'
      eventObj.setProp(vm.segManager, kernel.selectors.message, const SciReg.fromInt(111)); // 'o'
      kernel.call(vm, 0x19, 2, [editObjReg, eventReg]);
      eventObj.setProp(vm.segManager, kernel.selectors.message, const SciReg.fromInt(107)); // 'k'
      kernel.call(vm, 0x19, 2, [editObjReg, eventReg]);

      expect(vm.segManager.getString(bufferPtr), equals('look'));
      expect(editObj.getProp(vm.segManager, kernel.selectors.cursor).toUint16(), equals(4));

      // Post Backspace (8)
      eventObj.setProp(vm.segManager, kernel.selectors.message, const SciReg.fromInt(8));
      kernel.call(vm, 0x19, 2, [editObjReg, eventReg]);

      expect(vm.segManager.getString(bufferPtr), equals('loo'));
      expect(editObj.getProp(vm.segManager, kernel.selectors.cursor).toUint16(), equals(3));
    });

    test('full SCI0 modal input and dialog dismissal round trip in PQ2', () {
      final vol = SciVolumeManager.fromDirectory('reference_games/police-quest-2');
      final engine = SciGameEngine(volumeManager: vol);
      engine.kernel.captureDebugLogs = true;
      engine.initializeGame();

      final vocabBytes = vol.getResource(SciResourceType.vocab, 0);
      engine.kernel.vocab = SciVocab();
      engine.kernel.vocab!.loadVocab000(vocabBytes);

      engine.restartGame();

      for (int i = 0; i < 100; i++) {
        engine.tick();
        if (engine.isInputEnabled) break;
      }

      expect(engine.isInputEnabled, isTrue);

      // 1. Post 'l'
      engine.handleKeyPress(108, ascii: 108);
      for (int t = 0; t < 5; t++) {
        engine.tick();
        if (engine.sciWindows.isNotEmpty) break;
      }

      expect(engine.sciWindows.isNotEmpty, isTrue, reason: 'Modal input window should open');

      // 2. Type 'ook'
      for (final ch in 'ook'.codeUnits) {
        engine.handleKeyPress(ch, ascii: ch);
        engine.tick();
      }

      final editControl = engine.sciWindows.last.controls.whereType<SciEditControl>().firstOrNull;
      expect(editControl?.text, equals('look'));

      // 3. Press Enter (13) to submit command
      engine.handleKeyPress(13, ascii: 13);
      for (int t = 0; t < 5; t++) {
        engine.tick();
        if (engine.sciWindows.isNotEmpty) {
          final textCtrl = engine.sciWindows.last.controls.whereType<SciTextControl>().firstOrNull;
          if (textCtrl != null && textCtrl.text.contains("don't have it")) {
            break;
          }
        }
      }

      expect(engine.sciWindows.isNotEmpty, isTrue, reason: 'Response message box should open');
      final responseText = engine.sciWindows.last.controls.whereType<SciTextControl>().firstOrNull?.text;
      expect(responseText, contains("don't have it"));

      // 4. Dismiss response dialog by pressing Enter (13)
      engine.handleKeyPress(13, ascii: 13);
      for (int t = 0; t < 5; t++) {
        engine.tick();
        if (engine.sciWindows.isEmpty) break;
      }

      expect(engine.sciWindows.isEmpty, isTrue, reason: 'Dialog should be dismissed');
    });
  });
}
