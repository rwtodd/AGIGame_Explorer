import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/loader/dir_entry.dart';
import 'package:flutter_agigame/loader/volume_manager.dart';

/// Builds a minimal `VOL.0` containing one resource whose raw bytes are
/// [resource], written at offset 100.
Uint8List _writeVol0(Directory dir, Uint8List resource) {
  final file = File('${dir.path}/VOL.0');
  final bytes = Uint8List(100 + 5 + resource.length);
  bytes[100] = 0x12;
  bytes[100 + 1] = 0x34;
  bytes[100 + 2] = 0;
  bytes[100 + 3] = resource.length & 0xFF;
  bytes[100 + 4] = (resource.length >> 8) & 0xFF;
  bytes.setRange(105, 105 + resource.length, resource);
  file.writeAsBytesSync(bytes);
  return bytes;
}

void main() {
  group('V2VolumeManager buffer aliasing', () {
    late Directory tempDir;
    late V2VolumeManager vmgr;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('vol_test');
      _writeVol0(tempDir, Uint8List.fromList([10, 20, 30, 40]));
      vmgr = V2VolumeManager(tempDir.path);
    });

    tearDown(() {
      vmgr.close();
      tempDir.deleteSync(recursive: true);
    });

    test('mutating a returned resource does not corrupt the cache', () {
      const de = DirEntry(0, 100);
      final first = vmgr.getResource(de);
      expect(first.toList(), equals([10, 20, 30, 40]));

      // Attack the buffer handed out to the caller.
      try {
        first[0] = 99;
      } catch (_) {
        // Unmodifiable views throw UnsupportedError; either the throw or a
        // pristine second call is acceptable evidence of isolation.
      }

      final second = vmgr.getResource(de);
      expect(second.toList(), equals([10, 20, 30, 40]));
    });

    test('freshly read (uncached) buffers are also isolated', () {
      const de = DirEntry(0, 100);
      // Two distinct entries over the same bytes? Entries are keyed by
      // volume+offset, so instead verify the first (cache-warming) call is
      // detached from the cache by mutating it and re-reading.
      final first = vmgr.getResource(de);
      try {
        first[1] = 99;
      } catch (_) {}
      expect(vmgr.getResource(de).toList(), equals([10, 20, 30, 40]));
    });
  });
}
