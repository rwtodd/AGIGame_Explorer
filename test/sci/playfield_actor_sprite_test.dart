import 'package:flutter_agigame/ui/widgets/agi_picture_canvas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlayfieldActorSprite', () {
    test('defaults preserve authentic AGI double-width and zero displacement', () {
      const sprite = PlayfieldActorSprite(
        priority: 7,
        baselineY: 120,
        objectNumber: 0,
        isUpdating: true,
        position: Offset(50, 100),
        viewNumber: 1,
        loopNumber: 0,
        celNumber: 0,
      );

      expect(sprite.scaleX, equals(2.0));
      expect(sprite.scaleY, equals(1.0));
      expect(sprite.displaceX, equals(0.0));
      expect(sprite.displaceY, equals(0.0));
      expect(sprite.z, equals(0));
      expect(sprite.sortY, equals(120));
      expect(sprite.renderPosition, equals(const Offset(50, 100)));
    });

    test('supports SCI 1:1 scale, elevation z, and displacement', () {
      const sprite = PlayfieldActorSprite(
        priority: 8,
        baselineY: 150,
        objectNumber: 2,
        isUpdating: true,
        position: Offset(80, 120),
        viewNumber: 10,
        loopNumber: 1,
        celNumber: 3,
        scaleX: 1.0,
        scaleY: 1.0,
        displaceX: -2,
        displaceY: 4,
        z: 15,
      );

      expect(sprite.scaleX, equals(1.0));
      expect(sprite.scaleY, equals(1.0));
      expect(sprite.displaceX, equals(-2));
      expect(sprite.displaceY, equals(4));
      expect(sprite.z, equals(15));
      // sortY = baselineY - z = 150 - 15 = 135
      expect(sprite.sortY, equals(135));
      // renderPosition = (80 - 2, 120 + 4 - 15) = (78, 109)
      expect(sprite.renderPosition, equals(const Offset(78, 109)));
    });

    test('typedef AgiActorSprite is an alias for PlayfieldActorSprite', () {
      const AgiActorSprite sprite = AgiActorSprite(
        priority: 5,
        baselineY: 80,
        objectNumber: 1,
        isUpdating: false,
        position: Offset(20, 60),
        viewNumber: 2,
        loopNumber: 0,
        celNumber: 0,
      );

      expect(sprite, isA<PlayfieldActorSprite>());
      expect(sprite.scaleX, equals(2.0));
    });

    test('compareDrawOrder sorts by priority first', () {
      const a = PlayfieldActorSprite(
        priority: 4,
        baselineY: 100,
        objectNumber: 0,
        isUpdating: true,
        position: Offset(0, 0),
        viewNumber: 0,
        loopNumber: 0,
        celNumber: 0,
      );
      const b = PlayfieldActorSprite(
        priority: 8,
        baselineY: 50,
        objectNumber: 0,
        isUpdating: true,
        position: Offset(0, 0),
        viewNumber: 0,
        loopNumber: 0,
        celNumber: 0,
      );

      expect(PlayfieldActorSprite.compareDrawOrder(a, b), lessThan(0));
      expect(PlayfieldActorSprite.compareDrawOrder(b, a), greaterThan(0));
    });

    test('compareDrawOrder sorts static (stop.update) actors before moving actors', () {
      const staticActor = PlayfieldActorSprite(
        priority: 7,
        baselineY: 100,
        objectNumber: 3,
        isUpdating: false,
        position: Offset(0, 0),
        viewNumber: 0,
        loopNumber: 0,
        celNumber: 0,
      );
      const movingActor = PlayfieldActorSprite(
        priority: 7,
        baselineY: 100,
        objectNumber: 2,
        isUpdating: true,
        position: Offset(0, 0),
        viewNumber: 0,
        loopNumber: 0,
        celNumber: 0,
      );

      expect(PlayfieldActorSprite.compareDrawOrder(staticActor, movingActor), lessThan(0));
      expect(PlayfieldActorSprite.compareDrawOrder(movingActor, staticActor), greaterThan(0));
    });

    test('compareDrawOrder sorts by sortY (taking elevation z into account)', () {
      // Actor 1 baseline 100, z 0 -> sortY 100
      const a = PlayfieldActorSprite(
        priority: 7,
        baselineY: 100,
        objectNumber: 1,
        isUpdating: true,
        position: Offset(0, 0),
        viewNumber: 0,
        loopNumber: 0,
        celNumber: 0,
        z: 0,
      );
      // Actor 2 baseline 110, z 25 -> sortY 85 (further back than Actor 1!)
      const b = PlayfieldActorSprite(
        priority: 7,
        baselineY: 110,
        objectNumber: 2,
        isUpdating: true,
        position: Offset(0, 0),
        viewNumber: 0,
        loopNumber: 0,
        celNumber: 0,
        z: 25,
      );

      expect(PlayfieldActorSprite.compareDrawOrder(b, a), lessThan(0));
      expect(PlayfieldActorSprite.compareDrawOrder(a, b), greaterThan(0));
    });

    test('compareDrawOrder draws Ego (object 0) last when priority and sortY tie', () {
      const ego = PlayfieldActorSprite(
        priority: 7,
        baselineY: 100,
        objectNumber: 0,
        isUpdating: true,
        position: Offset(0, 0),
        viewNumber: 0,
        loopNumber: 0,
        celNumber: 0,
      );
      const other = PlayfieldActorSprite(
        priority: 7,
        baselineY: 100,
        objectNumber: 4,
        isUpdating: true,
        position: Offset(0, 0),
        viewNumber: 0,
        loopNumber: 0,
        celNumber: 0,
      );

      expect(PlayfieldActorSprite.compareDrawOrder(other, ego), lessThan(0));
      expect(PlayfieldActorSprite.compareDrawOrder(ego, other), greaterThan(0));
    });

    test('equality and hashCode handle all fields', () {
      const a1 = PlayfieldActorSprite(
        priority: 7,
        baselineY: 100,
        objectNumber: 1,
        isUpdating: true,
        position: Offset(10, 20),
        viewNumber: 3,
        loopNumber: 1,
        celNumber: 2,
        scaleX: 1.0,
        scaleY: 1.0,
        displaceX: 1,
        displaceY: -1,
        z: 5,
      );
      const a2 = PlayfieldActorSprite(
        priority: 7,
        baselineY: 100,
        objectNumber: 1,
        isUpdating: true,
        position: Offset(10, 20),
        viewNumber: 3,
        loopNumber: 1,
        celNumber: 2,
        scaleX: 1.0,
        scaleY: 1.0,
        displaceX: 1,
        displaceY: -1,
        z: 5,
      );
      const diff = PlayfieldActorSprite(
        priority: 7,
        baselineY: 100,
        objectNumber: 1,
        isUpdating: true,
        position: Offset(10, 20),
        viewNumber: 3,
        loopNumber: 1,
        celNumber: 2,
        scaleX: 1.0,
        scaleY: 1.0,
        displaceX: 1,
        displaceY: -1,
        z: 10, // different elevation
      );

      expect(a1, equals(a2));
      expect(a1.hashCode, equals(a2.hashCode));
      expect(a1, isNot(equals(diff)));
    });
  });
}
