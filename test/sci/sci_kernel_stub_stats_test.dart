import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_kernel.dart';
import 'package:flutter_agigame/sci/engine/sci_seg_manager.dart';
import 'package:flutter_agigame/sci/engine/sci_selectors.dart';
import 'package:flutter_agigame/sci/engine/sci_vm.dart';

void main() {
  group('SCI kernel stub-hit stats', () {
    late SciKernel kernel;
    late SciVM vm;

    setUp(() {
      kernel = SciKernel();
      final seg = SciSegManager();
      final selectors = SciSelectors();
      vm = SciVM(segManager: seg, kernel: kernel, selectors: selectors);
    });

    test('stub flags mark _kStub ops but not implemented ones', () {
      expect(kernel.isStubKernel(0x57), isTrue, reason: 'SetDebug');
      expect(kernel.isStubKernel(0x62), isTrue, reason: 'GetCWD');
      expect(kernel.isStubKernel(0x08), isFalse, reason: 'DrawPic');
      expect(kernel.isStubKernel(0x03), isFalse, reason: 'DisposeScript');
      expect(kernel.isStubKernel(0x6B), isFalse, reason: 'FlushResources');
      expect(kernel.isStubKernel(0xFF), isTrue, reason: 'unknown id');
    });

    test('stub and unknown calls are counted; ranking and reset work', () {
      kernel.call(vm, 0x57, 0, []);
      kernel.call(vm, 0x57, 0, []);
      kernel.call(vm, 0x62, 0, []);
      kernel.call(vm, 0xFF, 0, []);

      expect(kernel.stubHitCounts[0x57], 2);
      expect(kernel.stubHitCounts[0x62], 1);
      expect(kernel.stubHitCounts[0xFF], 1);
      expect(kernel.stubHitTotal, 4);

      final top = kernel.topStubHits();
      expect(top.first.id, 0x57);
      expect(top.first.name, 'SetDebug');
      expect(top.first.hits, 2);
      expect(kernel.topStubHits(2), hasLength(2));

      kernel.clearStubStats();
      expect(kernel.stubHitTotal, 0);
      expect(kernel.topStubHits(), isEmpty);
    });
  });
}
