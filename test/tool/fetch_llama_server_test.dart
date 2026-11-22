import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/fetch_llama_server.dart' as fetch;

void main() {
  group('sha256OfFile', () {
    test('matches the known digest of fixed contents', () async {
      final dir = await Directory.systemTemp.createTemp('fetch_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/data.bin');
      await file.writeAsBytes('hello sha256 test'.codeUnits);
      // sha256 of the ASCII bytes 'hello sha256 test'
      // (verified with: printf 'hello sha256 test' | shasum -a 256).
      expect(
        await fetch.sha256OfFile(file),
        '6dd80ab65ee0ff6ec7ddc6557b6635efe899688d65e1564491d642861e29d02f',
      );
    });

    test('handles an empty file', () async {
      final dir = await Directory.systemTemp.createTemp('fetch_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/empty.bin');
      await file.writeAsBytes(const []);
      // sha256 of zero bytes.
      expect(
        await fetch.sha256OfFile(file),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });
  });

  group('expectedArchiveSha256', () {
    test('returns the pinned b11712 digests', () {
      expect(
        fetch.expectedArchiveSha256(
            'b11712', 'llama-b11712-bin-macos-arm64.tar.gz'),
        'fc2bdadcefee39c6b652707667d22ec8c959eaf7bf143e97a6d30226824852c1',
      );
      expect(
        fetch.expectedArchiveSha256(
            'b11712', 'llama-b11712-bin-win-cpu-x64.zip'),
        'cc8454164d885e6826a06abd6100aa040b5b5139d527ae49058ec7c449011b68',
      );
    });

    test('returns null for an unknown tag', () {
      expect(
        fetch.expectedArchiveSha256(
            'b99999', 'llama-b99999-bin-macos-arm64.tar.gz'),
        isNull,
      );
    });

    test('returns null for an unknown asset under a known tag', () {
      expect(
        fetch.expectedArchiveSha256('b11712', 'some-other-asset.tar.gz'),
        isNull,
      );
    });
  });
}
