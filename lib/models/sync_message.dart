import 'dart:convert';
import 'package:equatable/equatable.dart';

class SyncMessage extends Equatable {
  final String messageId;
  final String deviceId;
  final String itemId;
  final int delta;
  final int quantity;
  final int timestamp;
  final String roomId;

  const SyncMessage({
    required this.messageId,
    required this.deviceId,
    required this.itemId,
    this.delta = 0,
    required this.quantity,
    required this.timestamp,
    this.roomId = 'warehouse-main',
  });

  bool get isValid =>
      messageId.isNotEmpty &&
      deviceId.isNotEmpty &&
      itemId.isNotEmpty &&
      timestamp > 0;

  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'deviceId': deviceId,
      'itemId': itemId,
      'delta': delta,
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
      delta: (map['delta'] as num?)?.toInt() ?? 0,
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
        delta,
        quantity,
        timestamp,
        roomId,
      ];
}
