import 'dart:math';

class IdGenerator {
  IdGenerator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  String newId(String prefix) {
    final timestamp = DateTime.now()
        .toUtc()
        .microsecondsSinceEpoch
        .toRadixString(36);
    final first = _random.nextInt(0x3fffffff).toRadixString(36).padLeft(6, '0');
    final second = _random
        .nextInt(0x3fffffff)
        .toRadixString(36)
        .padLeft(6, '0');

    return '${prefix}_${timestamp}_$first$second';
  }
}
