/// Represents an inventory object in an AGI game.
class AgiObject {
  final String name;
  final int startingRoom;

  const AgiObject({
    required this.name,
    required this.startingRoom,
  });

  @override
  String toString() => 'AgiObject(name: "$name", room: $startingRoom)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgiObject &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          startingRoom == other.startingRoom;

  @override
  int get hashCode => Object.hash(name, startingRoom);
}

/// Represents an item carried by the player, bundling its item index and [AgiObject] definition.
class CarriedItem {
  final int index;
  final AgiObject object;

  const CarriedItem({
    required this.index,
    required this.object,
  });

  String get name => object.name;

  @override
  String toString() => 'CarriedItem(#$index: "${object.name}")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CarriedItem &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          object == other.object;

  @override
  int get hashCode => Object.hash(index, object);
}
