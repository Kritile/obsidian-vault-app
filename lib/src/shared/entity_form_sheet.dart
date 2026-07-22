import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/vault/native_entity.dart';

Future<void> showCreateEntityPicker(BuildContext context, WidgetRef ref) async {
  final definition = await showModalBottomSheet<NativeEntityDefinition>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        children: [
          Text('Что добавить?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final item in nativeEntityDefinitions)
            ListTile(
              leading: CircleAvatar(child: Icon(entityKindIcon(item.kind))),
              title: Text(item.label),
              subtitle: Text(item.folder),
              onTap: () => Navigator.pop(context, item),
            ),
        ],
      ),
    ),
  );
  if (definition == null || !context.mounted) return;
  final values = await Navigator.of(context).push<Map<String, Object?>>(
    MaterialPageRoute(builder: (_) => EntityFormScreen(definition: definition)),
  );
  if (values == null || !context.mounted) return;
  try {
    final path = await ref
        .read(nativeEntityServiceProvider)
        .create(definition.kind, values);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Создано: $path')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

IconData entityKindIcon(NativeEntityKind kind) => switch (kind) {
  NativeEntityKind.book => Icons.menu_book_outlined,
  NativeEntityKind.recipe => Icons.restaurant_menu,
  NativeEntityKind.plant => Icons.local_florist_outlined,
  NativeEntityKind.tea => Icons.emoji_food_beverage_outlined,
  NativeEntityKind.medicine => Icons.medication_outlined,
  NativeEntityKind.note => Icons.note_add_outlined,
};

class EntityFormScreen extends StatefulWidget {
  const EntityFormScreen({required this.definition, super.key});
  final NativeEntityDefinition definition;
  @override
  State<EntityFormScreen> createState() => _EntityFormScreenState();
}

class _EntityFormScreenState extends State<EntityFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, Object?> _values = {};

  @override
  void initState() {
    super.initState();
    for (final field in widget.definition.fields) {
      if (field.type == EntityFieldType.boolean) {
        _values[field.key] = false;
      } else if (field.type == EntityFieldType.choice) {
        _values[field.key] = field.options.firstOrNull;
      } else {
        _controllers[field.key] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 380;
    return Scaffold(
      appBar: AppBar(title: Text('Новая запись · ${widget.definition.label}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(narrow ? 12 : 24),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  for (final field in widget.definition.fields) ...[
                    _field(field),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.save_outlined),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Создать'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(EntityFieldDefinition field) {
    if (field.type == EntityFieldType.boolean) {
      return SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(field.label),
        value: _values[field.key] as bool? ?? false,
        onChanged: (value) => setState(() => _values[field.key] = value),
      );
    }
    if (field.type == EntityFieldType.choice) {
      return DropdownButtonFormField<String>(
        initialValue: _values[field.key] as String?,
        decoration: InputDecoration(labelText: field.label),
        items: field.options
            .map(
              (option) => DropdownMenuItem(value: option, child: Text(option)),
            )
            .toList(growable: false),
        onChanged: (value) => _values[field.key] = value,
      );
    }
    return TextFormField(
      controller: _controllers[field.key],
      minLines: field.type == EntityFieldType.multiline ? 4 : 1,
      maxLines: field.type == EntityFieldType.multiline ? 10 : 1,
      keyboardType: field.type == EntityFieldType.number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.hint,
        alignLabelWithHint: field.type == EntityFieldType.multiline,
      ),
      validator: field.required
          ? (value) => value == null || value.trim().isEmpty
                ? 'Обязательное поле'
                : null
          : null,
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    for (final entry in _controllers.entries) {
      final field = widget.definition.fields.firstWhere(
        (item) => item.key == entry.key,
      );
      final raw = entry.value.text.trim();
      _values[entry.key] = switch (field.type) {
        EntityFieldType.number => num.tryParse(raw.replaceAll(',', '.')) ?? raw,
        EntityFieldType.tags =>
          raw
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(),
        _ => raw,
      };
    }
    Navigator.pop(context, Map<String, Object?>.from(_values));
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
