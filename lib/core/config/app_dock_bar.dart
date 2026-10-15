import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_symbols_icons/symbols.dart';

class DockBarItem {
  final String id;
  final String label;
  final int iconCodePoint;
  final bool visible;

  const DockBarItem({
    required this.id,
    required this.label,
    required this.iconCodePoint,
    this.visible = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'icon': iconCodePoint,
        'visible': visible,
      };

  factory DockBarItem.fromJson(Map<String, dynamic> json) => DockBarItem(
        id: json['id'] as String,
        label: json['label'] as String,
        iconCodePoint: json['icon'] as int,
        visible: json['visible'] as bool? ?? true,
      );

  DockBarItem copyWith({
    String? id,
    String? label,
    int? iconCodePoint,
    bool? visible,
  }) =>
      DockBarItem(
        id: id ?? this.id,
        label: label ?? this.label,
        iconCodePoint: iconCodePoint ?? this.iconCodePoint,
        visible: visible ?? this.visible,
      );
}

class AppDockBar {
  AppDockBar._();

  static const _prefsKey = 'dock_bar_items_v1';

  static final ValueNotifier<List<DockBarItem>> current =
      ValueNotifier(_defaults);

  static const List<DockBarItem> _defaults = [
    DockBarItem(
      id: 'chats',
      label: 'Чаты',
      iconCodePoint: 0xe0b7, // Symbols.chat_bubble
    ),
    DockBarItem(
      id: 'calls',
      label: 'Звонки',
      iconCodePoint: 0xe0b0, // Symbols.call
    ),
    DockBarItem(
      id: 'contacts',
      label: 'Контакты',
      iconCodePoint: 0xf0e8, // Symbols.person_pin approx
    ),
    DockBarItem(
      id: 'settings',
      label: 'Настройки',
      iconCodePoint: 0xe8b8, // Symbols.settings
    ),
  ];

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) {
      current.value = List.of(_defaults);
      return;
    }
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => DockBarItem.fromJson(e as Map<String, dynamic>))
          .toList();
      current.value = list;
    } catch (_) {
      current.value = List.of(_defaults);
    }
  }

  static Future<void> save(List<DockBarItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
    current.value = List.of(items);
  }

  static List<DockBarItem> get visible =>
      current.value.where((e) => e.visible).toList();

  static IconData iconFor(DockBarItem item) {
    // Fallback mapping; real icons come from Symbols
    switch (item.id) {
      case 'chats':
        return Symbols.chat_bubble;
      case 'calls':
        return Symbols.call;
      case 'contacts':
        return Symbols.person_pin;
      case 'settings':
        return Symbols.settings;
      default:
        return Symbols.apps;
    }
  }
}
