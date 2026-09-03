import 'dart:convert';
import 'package:equatable/equatable.dart';

class SyncMessage extends Equatable {
  final String messageId;
  final String deviceId;
  final String itemId;
  final int quantity;
  final int timestamp;
  final String roomId;

  const SyncMessage({
    required this.messageId,
    required this.deviceId,
    required this.itemId,
    required this.quantity,
    required this.timestamp,
    this.roomId = 'warehouse-main',
  });

  bool get isValid =>
      messageId.isNotEmpty &&
      deviceId.isNotEmpty &&
      itemId.isNotEmpty &&
      quantity >= 0 &&
      timestamp > 0;

  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'deviceId': deviceId,
      'itemId': itemId,
      'quantity': quantity,
      'timestamp': timestamp,
      'roomId': roomId,
    };
  }

  factory SyncMessage.fromMap(Map<dynamic, dynamic> map) {
    return SyncMessage(
      messageId: map['messageId'] as String? ?? '',
      deviceId: map['deviceId'] as String? ?? '',
      itemId: map['itemId'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      roomId: map['roomId'] as String? ?? 'warehouse-main',
    );
  }

  String toJson() => jsonEncode(toMap());

  factory SyncMessage.fromJson(String source) =>
      SyncMessage.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  List<Object?> get props => [
        messageId,
        deviceId,
        itemId,
        quantity,
        timestamp,
        roomId,
      ];
}
