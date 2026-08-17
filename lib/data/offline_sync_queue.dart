import 'dart:convert';

class PendingSyncAction {
  const PendingSyncAction({
    required this.id,
    required this.actionId,
    required this.actionType,
    required this.payload,
    required this.createdAt,
    required this.attempts,
    this.lastError,
  });

  final int id;
  final String actionId;
  final String actionType;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;

  factory PendingSyncAction.fromMap(Map<String, Object?> row) => PendingSyncAction(
        id: row['id'] as int,
        actionId: row['action_id'] as String,
        actionType: row['action_type'] as String,
        payload: (jsonDecode(row['payload_json'] as String) as Map).cast<String, dynamic>(),
        createdAt: DateTime.parse(row['created_at'] as String),
        attempts: (row['attempts'] as int?) ?? 0,
        lastError: row['last_error'] as String?,
      );
}
