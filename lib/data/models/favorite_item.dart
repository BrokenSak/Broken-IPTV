enum FavoriteType { live, vod, series }

class FavoriteItem {
  const FavoriteItem({
    required this.type,
    required this.id,
    required this.name,
    this.imageUrl,
    this.updatedAt = 0,
  });

  final FavoriteType type;
  final String id;
  final String name;
  final String? imageUrl;

  /// When this favourite was last added, epoch ms. Only the cross-device sync
  /// uses it (most recent change wins); 0 means "written before sync existed",
  /// which loses every conflict — the right answer for a legacy entry.
  final int updatedAt;

  String get key => '${type.name}:$id';

  FavoriteItem stamped(int atMs) => FavoriteItem(
        type: type,
        id: id,
        name: name,
        imageUrl: imageUrl,
        updatedAt: atMs,
      );

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'id': id,
        'name': name,
        'imageUrl': imageUrl,
        'updatedAt': updatedAt,
      };

  factory FavoriteItem.fromMap(Map<dynamic, dynamic> map) => FavoriteItem(
        type: FavoriteType.values.firstWhere((t) => t.name == map['type']),
        id: map['id'] as String,
        name: map['name'] as String,
        imageUrl: map['imageUrl'] as String?,
        updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      );
}
