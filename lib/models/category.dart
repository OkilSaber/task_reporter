import 'package:flutter/material.dart';

class Category {
  final String id;
  String name;
  Color color;
  final bool isLocked;
  bool isHidden;
  bool isFavorite;

  Category({
    required this.id,
    required this.name,
    required this.color,
    this.isLocked = false,
    this.isHidden = false,
    this.isFavorite = false,
  });

  static const _clientSeparator = ' – ';

  /// Client part of a "Client – Project" name, or null when there is none.
  String? get client {
    final i = name.indexOf(_clientSeparator);
    return i > 0 ? name.substring(0, i).trim() : null;
  }

  /// Project part of the name, without the client prefix nor the client name
  /// repeated at its start ("C-log – C-Log Crossroad - RUN" → "Crossroad - RUN").
  String get project {
    final c = client;
    if (c == null) return name;
    var p = name
        .substring(name.indexOf(_clientSeparator) + _clientSeparator.length)
        .trim();
    // Only strip a whole word: "C-log – C-Logistics" must stay untouched.
    if (p.toLowerCase().startsWith(c.toLowerCase()) &&
        (p.length == c.length || RegExp(r'[\s\-–]').hasMatch(p[c.length]))) {
      final rest = p.substring(c.length).replaceFirst(RegExp(r'^[\s\-–]+'), '');
      if (rest.isNotEmpty) p = rest;
    }
    return p;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color.toARGB32(),
    'isLocked': isLocked,
    'isHidden': isHidden,
    'isFavorite': isFavorite,
  };

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'],
    name: json['name'],
    // The old near-black palette entry was invisible on the dark UI.
    color: Color(json['color'] == 0xFF263238 ? 0xFF78909C : json['color']),
    isLocked: json['isLocked'] ?? false,
    isHidden: json['isHidden'] ?? false,
    isFavorite: json['isFavorite'] ?? false,
  );
}
