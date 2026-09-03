import 'package:equatable/equatable.dart';

class InventoryItem extends Equatable {
  final String id;
  final String name;
  final int quantity;

  const InventoryItem({
    required this.id,
    required this.name,
    required this.quantity,
  }) : assert(quantity >= 0, 'Quantity cannot be negative');

  InventoryItem copyWith({
    String? id,
    String? name,
    int? quantity,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      quantity: (quantity ?? this.quantity) < 0 ? 0 : (quantity ?? this.quantity),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'quantity': quantity,
    };
  }

  factory InventoryItem.fromMap(Map<dynamic, dynamic> map) {
    return InventoryItem(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [id, name, quantity];
}
