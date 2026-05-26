/// A user-defined library shelf — a named grouping of series.
class Collection {
  const Collection({
    required this.id,
    required this.name,
    required this.seriesIds,
    required this.createdAt,
  });

  /// Stable id (microsecond timestamp at create-time).
  final String id;

  final String name;

  /// OPDS ids of the series in this collection, in insertion order.
  final List<int> seriesIds;

  final DateTime createdAt;

  int get count => seriesIds.length;

  Collection copyWith({
    String? name,
    List<int>? seriesIds,
  }) => Collection(
    id: id,
    name: name ?? this.name,
    seriesIds: seriesIds ?? this.seriesIds,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'seriesIds': seriesIds,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Collection.fromJson(Map<String, dynamic> json) => Collection(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    seriesIds:
        (json['seriesIds'] as List?)
            ?.whereType<num>()
            .map((n) => n.toInt())
            .toList() ??
        const [],
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}
