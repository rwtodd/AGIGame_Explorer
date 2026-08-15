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
