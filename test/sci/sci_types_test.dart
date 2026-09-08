import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/sci/engine/sci_types.dart';

void main() {
  group('SciReg Core Tests', () {
    test('Immediate integer numbers', () {
      const reg0 = SciReg.fromInt(0);
      expect(reg0.isNumber, isTrue);
      expect(reg0.isNull, isTrue);
      expect(reg0.isPointer, isFalse);
      expect(reg0.toUint16(), 0);
      expect(reg0.toSint16(), 0);

      const regPositive = SciReg.fromInt(1234);
      expect(regPositive.isNumber, isTrue);
      expect(regPositive.isNull, isFalse);
      expect(regPositive.toUint16(), 1234);
      expect(regPositive.toSint16(), 1234);

      const regNegative = SciReg.fromInt(-50);
      expect(regNegative.isNumber, isTrue);
      expect(regNegative.toSint16(), -50);
      expect(regNegative.toUint16(), 65536 - 50);

      const regMaxU = SciReg.fromInt(0xFFFF);
      expect(regMaxU.toUint16(), 0xFFFF);
      expect(regMaxU.toSint16(), -1);
    });

    test('Pointers', () {
      const ptr = SciReg.pointer(1, 0x0D26);
      expect(ptr.isNumber, isFalse);
      expect(ptr.isPointer, isTrue);
      expect(ptr.isNull, isFalse);
      expect(ptr.segment, 1);
      expect(ptr.offset, 0x0D26);
      expect(ptr.toString(), '0001:0d26');
    });

    test('Sentinel values', () {
      expect(SciReg.nullReg.isNull, isTrue);
      expect(SciReg.uninitialized.isInitialized, isFalse);
      expect(SciReg.uninitialized.isPointer, isFalse);
    });

    test('Arithmetic operations', () {
      const r1 = SciReg.fromInt(100);
      const r2 = SciReg.fromInt(30);

      expect((r1 + r2).toSint16(), 130);
      expect((r1 - r2).toSint16(), 70);
      expect((r1 * r2).toSint16(), 3000);
      expect((r1 ~/ r2).toSint16(), 3);
      expect((r1 % r2).toSint16(), 10);

      // Pointer arithmetic offset increment
      const ptr = SciReg.pointer(2, 0x100);
      expect((ptr + 16).segment, 2);
      expect((ptr + 16).offset, 0x110);
      expect((ptr - 16).offset, 0x0F0);
    });

    test('Bitwise operations', () {
      const r1 = SciReg.fromInt(0x00FF);
      const r2 = SciReg.fromInt(0x0F0F);

      expect((r1 & r2).toUint16(), 0x000F);
      expect((r1 | r2).toUint16(), 0x0FFF);
      expect((r1 ^ r2).toUint16(), 0x0FF0);
      expect((~r1).toUint16(), 0xFF00);
      expect((r1 << 4).toUint16(), 0x0FF0);
      expect((r1 >> 4).toUint16(), 0x000F);
    });

    test('Signed and unsigned comparisons', () {
      const positive = SciReg.fromInt(10);
      const negative = SciReg.fromInt(-10);

      // Signed
      expect(negative < positive, isTrue);
      expect(negative <= positive, isTrue);
      expect(positive > negative, isTrue);
      expect(positive >= negative, isTrue);

      // Unsigned: negative is 0xFFF6 (65526), so negative is unsigned greater than 10
      expect(negative.gtU(positive), isTrue);
      expect(positive.ltU(negative), isTrue);
      expect(positive.leU(positive), isTrue);
      expect(negative.geU(negative), isTrue);
    });
  });

  group('SciExecStack Tests', () {
    test('Call stack frame initialization', () {
      final frame = SciExecStack(
        objp: const SciReg.pointer(1, 0x100),
        pc: const SciReg.pointer(1, 0x200),
        localSegment: 1,
        sp: 10,
        fp: 10,
        argc: 2,
        selector: 87,
      );

      expect(frame.type, SciExecStackType.call);
      expect(frame.objp.segment, 1);
      expect(frame.pc.offset, 0x200);
      expect(frame.argc, 2);
      expect(frame.selector, 87);
    });
  });
}
