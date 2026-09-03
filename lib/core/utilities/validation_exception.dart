class ValidationException implements Exception {
  const ValidationException(this.messages);

  final List<String> messages;

  String get message => messages.join('\n');

  @override
  String toString() => message;
}
