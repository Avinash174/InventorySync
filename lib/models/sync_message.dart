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
    final op = delta > 0
        ? 'increment'
        : delta < 0
            ? 'decrement'
            : 'set';
    return {
      'messageId': messageId,
      'deviceId': deviceId,
      'itemId': itemId,
      'delta': delta,
      'quantity': quantity,
      'timestamp': timestamp,
      'roomId': roomId,
      'operation': op,
      'amount': delta.abs(),
    };
  }

  factory SyncMessage.fromMap(Map<dynamic, dynamic> map) {
    int parsedDelta = (map['delta'] as num?)?.toInt() ?? 0;
    if (parsedDelta == 0 && map.containsKey('operation')) {
      final op = map['operation'] as String?;
      final amount = (map['amount'] as num?)?.toInt() ?? 1;
      if (op == 'increment') {
        parsedDelta = amount;
      } else if (op == 'decrement') {
        parsedDelta = -amount;
      }
    }

    return SyncMessage(
      messageId: map['messageId'] as String? ?? '',
      deviceId: map['deviceId'] as String? ?? '',
      itemId: map['itemId'] as String? ?? '',
      delta: parsedDelta,
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
