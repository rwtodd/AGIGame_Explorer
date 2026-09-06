import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agigame/core/display_profile.dart';

void main() {
  group('DisplayProfile Tests', () {
    test('DisplayProfile.agi preset has expected parameters', () {
      const agi = DisplayProfile.agi;
      expect(agi.nativeWidth, equals(160));
      expect(agi.nativeHeight, equals(168));
      expect(agi.renderedWidth, equals(320));
      expect(agi.renderedHeight, equals(200));
      expect(agi.horizontalDouble, isTrue);
      expect(agi.picPortTop, equals(8));
      expect(agi.priorityBandCount, equals(16));
      expect(agi.scanControlLines, isTrue);
    });

    test('DisplayProfile.sci0 preset has expected parameters', () {
      const sci0 = DisplayProfile.sci0;
      expect(sci0.nativeWidth, equals(320));
      expect(sci0.nativeHeight, equals(200));
      expect(sci0.renderedWidth, equals(320));
      expect(sci0.renderedHeight, equals(200));
      expect(sci0.horizontalDouble, isFalse);
      expect(sci0.picPortTop, equals(10));
      expect(sci0.priorityBandCount, equals(16));
      expect(sci0.scanControlLines, isFalse);
    });

    test('DisplayProfile.sci0FullScreen preset has expected parameters', () {
      const sci0Full = DisplayProfile.sci0FullScreen;
      expect(sci0Full.nativeWidth, equals(320));
      expect(sci0Full.nativeHeight, equals(200));
      expect(sci0Full.renderedWidth, equals(320));
      expect(sci0Full.renderedHeight, equals(200));
      expect(sci0Full.horizontalDouble, isFalse);
      expect(sci0Full.picPortTop, equals(0));
      expect(sci0Full.priorityBandCount, equals(16));
      expect(sci0Full.scanControlLines, isFalse);
    });

    test('supports value equality and hashCode', () {
      const p1 = DisplayProfile(
        nativeWidth: 320,
        nativeHeight: 200,
        horizontalDouble: false,
        scanControlLines: false,
      );
      const p2 = DisplayProfile(
        nativeWidth: 320,
        nativeHeight: 200,
        horizontalDouble: false,
        scanControlLines: false,
      );
      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
      expect(p1, isNot(equals(DisplayProfile.agi)));
    });

    test('copyWith produces updated instance with identical untouched fields', () {
      const base = DisplayProfile.sci0;
      final modified = base.copyWith(picPortTop: 0);

      expect(modified.picPortTop, equals(0));
      expect(modified.nativeWidth, equals(base.nativeWidth));
      expect(modified.nativeHeight, equals(base.nativeHeight));
      expect(modified.renderedWidth, equals(base.renderedWidth));
      expect(modified.renderedHeight, equals(base.renderedHeight));
      expect(modified.horizontalDouble, equals(base.horizontalDouble));
      expect(modified.priorityBandCount, equals(base.priorityBandCount));
      expect(modified.scanControlLines, equals(base.scanControlLines));
    });

    test('toString formats all fields cleanly', () {
      final str = DisplayProfile.agi.toString();
      expect(str, contains('160x168 -> 320x200'));
      expect(str, contains('2x: true'));
      expect(str, contains('scanControl: true'));
    });
  });
}
