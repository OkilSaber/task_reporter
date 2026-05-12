import 'package:flutter/material.dart';

class Category {
  final String id;
  String name;
  Color color;
  final bool isLocked;

  Category({
    required this.id,
    required this.name,
    required this.color,
    this.isLocked = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color.toARGB32(),
        'isLocked': isLocked,
      };

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'],
        name: json['name'],
        color: Color(json['color']),
        isLocked: json['isLocked'] ?? false,
      );
}
