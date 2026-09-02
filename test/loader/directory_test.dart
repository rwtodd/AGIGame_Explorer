import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/loader/dir_entry.dart';
import 'package:flutter_agigame/loader/resource_directory.dart';

void main() {
  group('ResourceDirectory', () {
    test('V2ResourceDirectory parses 3-byte entries', () {
      // 2 entries in logics:
      // Entry 0: vol 1, offset 0x001234 -> (0x10, 0x12, 0x34)
      // Entry 1: not present -> (0xFF, 0xFF, 0xFF)
      final logics = Uint8List.fromList([0x10, 0x12, 0x34, 0xFF, 0xFF, 0xFF]);
      final empty = Uint8List(0);

      final rdir = V2ResourceDirectory(
        logics: logics,
        pics: empty,
        views: empty,
        sounds: empty,
      );

      expect(rdir.logicCount, equals(2));
      final de0 = rdir.findLogic(0);
      expect(de0.isPresent, isTrue);
      expect(de0.volume, equals(1));
      expect(de0.offset, equals(0x1234));

      expect(rdir.hasLogic(0), isTrue);
      expect(rdir.hasLogic(1), isFalse);
      expect(rdir.hasLogic(2), isFalse);
      expect(rdir.presentLogicNumbers, equals([0]));
    });

    test('V3ResourceDirectory parses offsets and entries correctly and reports presence', () {
      // Header: logicOffs=8, picOffs=14, viewOffs=20, soundOffs=26
      // (8, 0), (14, 0), (20, 0), (26, 0)
      // logic entries: 2 entries ((14-8)/3 = 2)
      // pic entries: 2 entries ((20-14)/3 = 2)
      // view entries: 2 entries ((26-20)/3 = 2)
      // sound entries: 1 entry ((29-26)/3 = 1)
      final dirData = Uint8List.fromList([
        8, 0,   // logicOffs = 8
        14, 0,  // picOffs = 14
        20, 0,  // viewOffs = 20
        26, 0,  // soundOffs = 26
        // Logics (indices 8..13):
        0x00, 0x01, 0x00, // Logic 0: vol 0, offset 0x100
        0x00, 0x02, 0x00, // Logic 1: vol 0, offset 0x200
        // Pics (indices 14..19):
        0x10, 0x03, 0x00, // Pic 0: vol 1, offset 0x300
        0x10, 0x04, 0x00, // Pic 1: vol 1, offset 0x400
        // Views (indices 20..25):
        0x20, 0x05, 0x00, // View 0: vol 2, offset 0x500
        0x20, 0x06, 0x00, // View 1: vol 2, offset 0x600
        // Sounds (indices 26..28):
        0x30, 0x07, 0x00, // Sound 0: vol 3, offset 0x700
      ]);

      final rdir = V3ResourceDirectory(dirData);

      expect(rdir.logicCount, equals(2));
      expect(rdir.picCount, equals(2));
      expect(rdir.viewCount, equals(2));
      expect(rdir.soundCount, equals(1));

      expect(rdir.hasLogic(0), isTrue);
      expect(rdir.hasLogic(1), isTrue);
      expect(rdir.hasLogic(2), isFalse);
      expect(rdir.hasPic(0), isTrue);
      expect(rdir.hasPic(1), isTrue);
      expect(rdir.hasPic(2), isFalse);
      expect(rdir.hasView(0), isTrue);
      expect(rdir.hasView(1), isTrue);
      expect(rdir.hasView(2), isFalse);
      expect(rdir.hasSound(0), isTrue);
      expect(rdir.hasSound(1), isFalse);

      expect(rdir.presentLogicNumbers, equals([0, 1]));
      expect(rdir.presentPicNumbers, equals([0, 1]));
      expect(rdir.presentViewNumbers, equals([0, 1]));
      expect(rdir.presentSoundNumbers, equals([0]));

      expect(rdir.findLogic(0), equals(const DirEntry(0, 0x100)));
      expect(rdir.findLogic(1), equals(const DirEntry(0, 0x200)));
      expect(rdir.findPic(0), equals(const DirEntry(1, 0x300)));
      expect(rdir.findView(0), equals(const DirEntry(2, 0x500)));
      expect(rdir.findSound(0), equals(const DirEntry(3, 0x700)));
    });
  });
}
