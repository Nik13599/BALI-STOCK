class StockPurchaseRequest {
  const StockPurchaseRequest({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.lines,
    this.supplierId,
    this.createdBy,
    this.comment,
  });

  final String id;
  final String? supplierId;
  final String status;
  final String? createdBy;
  final String? comment;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<StockPurchaseRequestLine> lines;

  String get shortNumber {
    final date = createdAt;
    final suffix = id.replaceAll('-', '').toUpperCase();
    final tail = suffix.length >= 4 ? suffix.substring(0, 4) : suffix;
    return 'ЗАК-${date.year}-${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}-$tail';
  }

  /// Only a confirmed/sent/partial request is a real outstanding order.
  /// A draft must not reduce the automatic purchase recommendation.
  bool get isOpen => const {'confirmed', 'sent', 'partial'}.contains(status);
  bool get countsAsOrdered => isOpen;
  bool get canReceive => isOpen;

  String get statusLabel => switch (status) {
        'confirmed' => 'Подтверждена',
        'sent' => 'Отправлена',
        'partial' => 'Частично поставлена',
        'completed' => 'Выполнена',
        'cancelled' => 'Отменена',
        _ => 'Черновик',
      };

  factory StockPurchaseRequest.fromJson(Map<dynamic, dynamic> json) => StockPurchaseRequest(
        id: '${json['id'] ?? ''}',
        supplierId: _text(json['supplier_id']),
        status: '${json['status'] ?? 'draft'}',
        createdBy: _text(json['created_by']),
        comment: _text(json['comment']),
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal() ?? DateTime.now(),
        updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}')?.toLocal() ?? DateTime.now(),
        lines: (json['lines'] is List)
            ? (json['lines'] as List)
                .whereType<Map>()
                .map(StockPurchaseRequestLine.fromJson)
                .toList(growable: false)
            : const [],
      );
}

class StockPurchaseRequestLine {
  const StockPurchaseRequestLine({
    required this.productKey,
    required this.suggestedQuantity,
    required this.requestedQuantity,
    this.receivedQuantity = 0,
    this.unitCost,
    this.comment,
  });

  final String productKey;
  final int suggestedQuantity;
  final int requestedQuantity;
  final int receivedQuantity;
  final double? unitCost;
  final String? comment;

  int get outstandingQuantity => (requestedQuantity - receivedQuantity).clamp(0, 1 << 60);

  factory StockPurchaseRequestLine.fromJson(Map<dynamic, dynamic> json) => StockPurchaseRequestLine(
        productKey: '${json['product_key'] ?? ''}',
        suggestedQuantity: _int(json['suggested_quantity']),
        requestedQuantity: _int(json['requested_quantity']),
        receivedQuantity: _int(json['received_quantity']),
        unitCost: _double(json['unit_cost']),
        comment: _text(json['comment']),
      );
}

class PurchaseRequestDraftLine {
  const PurchaseRequestDraftLine({
    required this.productKey,
    required this.suggestedQuantity,
    required this.requestedQuantity,
    this.unitCost,
    this.comment,
  });

  final String productKey;
  final int suggestedQuantity;
  final int requestedQuantity;
  final double? unitCost;
  final String? comment;
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double? _double(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty || text == 'null' ? null : text;
}
