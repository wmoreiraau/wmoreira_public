/// A shopping-list item the user added by hand (name only), separate from the
/// items derived from an issue's AI look-up.
class ManualShoppingItem {
  ManualShoppingItem({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name};

  factory ManualShoppingItem.fromJson(Map<String, dynamic> json) {
    return ManualShoppingItem(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? json['id'] as String
          : DateTime.now().microsecondsSinceEpoch.toString(),
      name: (json['name'] as String?)?.trim() ?? '',
    );
  }
}
