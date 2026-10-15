class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime timestamp;
  const ChatMessage({required this.id, required this.senderId, required this.text, required this.timestamp});
  Map<String, dynamic> toJson() => {'id': id, 'senderId': senderId, 'text': text, 'timestamp': timestamp.toIso8601String()};
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String? ?? '',
    senderId: json['senderId'] as String? ?? '',
    text: json['text'] as String? ?? '',
    timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
  );
}
