import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/app_dock_bar.dart';
import '../../../core/utils/haptics.dart';
import '../../widgets/settings_card.dart';

class DockBarSettingsScreen extends StatefulWidget {
  const DockBarSettingsScreen({super.key});

  @override
  State<DockBarSettingsScreen> createState() => _DockBarSettingsScreenState();
}

class _DockBarSettingsScreenState extends State<DockBarSettingsScreen> {
  late List<DockBarItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.of(AppDockBar.current.value);
  }

  Future<void> _persist() async {
    await AppDockBar.save(_items);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Панель обновлена')),
      );
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    Haptics.selection();
    _persist();
  }

  void _toggle(int index) {
    setState(() {
      final item = _items[index];
      _items[index] = item.copyWith(visible: !item.visible);
    });
    Haptics.tap();
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Dock Bar'),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        onReorder: _onReorder,
        itemBuilder: (context, index) {
          final item = _items[index];
          return ListTile(
            key: ValueKey(item.id),
            leading: Icon(AppDockBar.iconFor(item), color: cs.onSurfaceVariant),
            title: Text(item.label),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: item.visible,
                  onChanged: (_) => _toggle(index),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Symbols.drag_indicator),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
