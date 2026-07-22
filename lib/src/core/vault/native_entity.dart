import 'dart:convert';

import 'package:intl/intl.dart';

enum NativeEntityKind { book, recipe, plant, tea, medicine, note }

enum EntityFieldType { text, number, multiline, choice, boolean, tags }

class EntityFieldDefinition {
  const EntityFieldDefinition({
    required this.key,
    required this.label,
    this.type = EntityFieldType.text,
    this.required = false,
    this.options = const [],
    this.hint,
  });
  final String key;
  final String label;
  final EntityFieldType type;
  final bool required;
  final List<String> options;
  final String? hint;
}

class NativeEntityDefinition {
  const NativeEntityDefinition({
    required this.kind,
    required this.label,
    required this.folder,
    required this.fields,
  });
  final NativeEntityKind kind;
  final String label;
  final String folder;
  final List<EntityFieldDefinition> fields;
}

const nativeEntityDefinitions = <NativeEntityDefinition>[
  NativeEntityDefinition(
    kind: NativeEntityKind.book,
    label: 'Книга',
    folder: 'Areas/Книги',
    fields: [
      EntityFieldDefinition(key: 'title', label: 'Название', required: true),
      EntityFieldDefinition(key: 'author', label: 'Автор', required: true),
      EntityFieldDefinition(
        key: 'year',
        label: 'Год',
        type: EntityFieldType.number,
      ),
      EntityFieldDefinition(
        key: 'genres',
        label: 'Жанры',
        type: EntityFieldType.tags,
        hint: 'Через запятую',
      ),
      EntityFieldDefinition(
        key: 'status',
        label: 'Статус',
        type: EntityFieldType.choice,
        options: ['unread', 'reading', 'finished', 'abandoned'],
      ),
      EntityFieldDefinition(
        key: 'rating',
        label: 'Оценка 1–10',
        type: EntityFieldType.number,
      ),
      EntityFieldDefinition(key: 'isbn', label: 'ISBN'),
      EntityFieldDefinition(key: 'cover', label: 'Ссылка на обложку'),
      EntityFieldDefinition(
        key: 'description',
        label: 'Описание',
        type: EntityFieldType.multiline,
      ),
      EntityFieldDefinition(
        key: 'notes',
        label: 'Мои заметки',
        type: EntityFieldType.multiline,
      ),
    ],
  ),
  NativeEntityDefinition(
    kind: NativeEntityKind.recipe,
    label: 'Рецепт',
    folder: 'Areas/Recipes',
    fields: [
      EntityFieldDefinition(key: 'title', label: 'Название', required: true),
      EntityFieldDefinition(key: 'category', label: 'Категория'),
      EntityFieldDefinition(key: 'cuisine', label: 'Кухня'),
      EntityFieldDefinition(
        key: 'difficulty',
        label: 'Сложность',
        type: EntityFieldType.choice,
        options: ['easy', 'medium', 'hard'],
      ),
      EntityFieldDefinition(
        key: 'servings',
        label: 'Порций',
        type: EntityFieldType.number,
      ),
      EntityFieldDefinition(
        key: 'prep_time',
        label: 'Подготовка, мин',
        type: EntityFieldType.number,
      ),
      EntityFieldDefinition(
        key: 'cook_time',
        label: 'Приготовление, мин',
        type: EntityFieldType.number,
      ),
      EntityFieldDefinition(
        key: 'favorite',
        label: 'Любимый рецепт',
        type: EntityFieldType.boolean,
      ),
      EntityFieldDefinition(
        key: 'ingredients',
        label: 'Ингредиенты',
        type: EntityFieldType.multiline,
        hint: 'Каждый ингредиент с новой строки',
      ),
      EntityFieldDefinition(
        key: 'instructions',
        label: 'Приготовление',
        type: EntityFieldType.multiline,
      ),
    ],
  ),
  NativeEntityDefinition(
    kind: NativeEntityKind.plant,
    label: 'Растение',
    folder: 'Areas/Растения',
    fields: [
      EntityFieldDefinition(key: 'title', label: 'Название', required: true),
      EntityFieldDefinition(key: 'latin', label: 'Латинское название'),
      EntityFieldDefinition(key: 'photo', label: 'Фото или ссылка'),
      EntityFieldDefinition(key: 'light', label: 'Освещение'),
      EntityFieldDefinition(key: 'watering', label: 'Полив'),
      EntityFieldDefinition(key: 'temperature', label: 'Температура'),
      EntityFieldDefinition(
        key: 'notes',
        label: 'Особенности ухода',
        type: EntityFieldType.multiline,
      ),
    ],
  ),
  NativeEntityDefinition(
    kind: NativeEntityKind.tea,
    label: 'Чай',
    folder: 'Areas/Чай',
    fields: [
      EntityFieldDefinition(key: 'title', label: 'Название', required: true),
      EntityFieldDefinition(key: 'category', label: 'Категория'),
      EntityFieldDefinition(
        key: 'year',
        label: 'Год',
        type: EntityFieldType.number,
      ),
      EntityFieldDefinition(key: 'origin', label: 'Происхождение'),
      EntityFieldDefinition(
        key: 'effect',
        label: 'Эффект',
        type: EntityFieldType.multiline,
      ),
      EntityFieldDefinition(
        key: 'taste',
        label: 'Вкус',
        type: EntityFieldType.multiline,
      ),
      EntityFieldDefinition(key: 'image', label: 'Изображение'),
      EntityFieldDefinition(
        key: 'brewing',
        label: 'Рекомендации по завариванию',
        type: EntityFieldType.multiline,
      ),
    ],
  ),
  NativeEntityDefinition(
    kind: NativeEntityKind.medicine,
    label: 'Лекарство',
    folder: 'Areas/Аптечка',
    fields: [
      EntityFieldDefinition(key: 'title', label: 'Название', required: true),
      EntityFieldDefinition(key: 'inn', label: 'МНН'),
      EntityFieldDefinition(key: 'format', label: 'Форма выпуска'),
      EntityFieldDefinition(key: 'dosage', label: 'Дозировка'),
      EntityFieldDefinition(key: 'package', label: 'Количество в упаковке'),
      EntityFieldDefinition(key: 'appointment', label: 'Назначение'),
      EntityFieldDefinition(
        key: 'remainder',
        label: 'Осталось',
        type: EntityFieldType.number,
      ),
      EntityFieldDefinition(key: 'manufacturer', label: 'Производитель'),
      EntityFieldDefinition(
        key: 'active',
        label: 'Сейчас принимаю',
        type: EntityFieldType.boolean,
      ),
      EntityFieldDefinition(
        key: 'dosagePerDay',
        label: 'В день',
        type: EntityFieldType.number,
      ),
      EntityFieldDefinition(
        key: 'notes',
        label: 'Примечания',
        type: EntityFieldType.multiline,
      ),
    ],
  ),
  NativeEntityDefinition(
    kind: NativeEntityKind.note,
    label: 'Заметка',
    folder: 'Входящие',
    fields: [
      EntityFieldDefinition(key: 'title', label: 'Название', required: true),
      EntityFieldDefinition(
        key: 'tags',
        label: 'Теги',
        type: EntityFieldType.tags,
      ),
      EntityFieldDefinition(
        key: 'body',
        label: 'Текст',
        type: EntityFieldType.multiline,
      ),
    ],
  ),
];

class NativeEntityTemplate {
  String build(NativeEntityKind kind, Map<String, Object?> values) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final title = values['title']?.toString().trim() ?? 'Без названия';
    String scalar(String key, [Object? fallback = '']) =>
        _yaml(values[key] ?? fallback);
    String text(String key) => values[key]?.toString().trim() ?? '';
    return switch (kind) {
      NativeEntityKind.book =>
        '''---
title: ${_yaml(title)}
author: ${scalar('author')}
year: ${scalar('year')}
genres: ${_list(values['genres'])}
status: ${scalar('status', 'unread')}
rating: ${scalar('rating')}
isbn: ${scalar('isbn')}
cover: ${scalar('cover')}
tags: [book]
---

## 🧠 Описание

${text('description')}

## 💬 Мои заметки

${text('notes')}
''',
      NativeEntityKind.recipe =>
        '''---
created: $today
updated: $today
type: recipe
tags: [рецепт]
category: ${_list(values['category'])}
cuisine: ${_list(values['cuisine'])}
difficulty: ${scalar('difficulty', 'easy')}
servings: ${scalar('servings')}
prep_time: ${scalar('prep_time')}
cook_time: ${scalar('cook_time')}
total_time: ${_sum(values['prep_time'], values['cook_time'])}
favorite: ${scalar('favorite', false)}
---

# 🍳 $title

## 📝 Ингредиенты

${_bulletLines(text('ingredients'))}

## 🍳 Приготовление

${text('instructions')}
''',
      NativeEntityKind.plant =>
        '''---
Название: ${_yaml(title)}
Латинское название: ${scalar('latin')}
Фото: ${scalar('photo')}
---

# $title

## Требования к содержанию

- **Освещение:** ${text('light')}
- **Полив:** ${text('watering')}
- **Температура:** ${text('temperature')}

## Примечания

${text('notes')}
''',
      NativeEntityKind.tea =>
        '''---
type: tea
category: ${scalar('category')}
year: ${scalar('year')}
origin: ${scalar('origin')}
effect: ${scalar('effect')}
taste: ${scalar('taste')}
image: ${scalar('image')}
---

## $title

**Эффект:** ${text('effect')}

**Вкус:** ${text('taste')}

### Рекомендации по завариванию

${text('brewing')}
''',
      NativeEntityKind.medicine =>
        '''---
tags: [аптечка, лекарства]
МНН: ${scalar('inn')}
format: ${scalar('format')}
dosage: ${scalar('dosage')}
package: ${scalar('package')}
appointment: ${scalar('appointment')}
remainder: ${scalar('remainder', 0)}
manufacturer: ${scalar('manufacturer')}
active: ${scalar('active', false)}
dosagePerDay: ${scalar('dosagePerDay', 0)}
created: $today
updated: $today
---

# 💊 $title

## 📦 Основное

- **Название:** $title
- **МНН:** ${text('inn')}
- **Форма выпуска:** ${text('format')}
- **Дозировка:** ${text('dosage')}
- **Упаковка:** ${text('package')}

## 📋 Назначение

${text('appointment')}

## 🗂️ Примечания

${text('notes')}
''',
      NativeEntityKind.note =>
        '''---
created: $today
modified: $today
tags: ${_list(values['tags'])}
aliases: []
---

# $title

${text('body')}
''',
    };
  }

  String _yaml(Object? value) {
    if (value == null || value.toString().trim().isEmpty) return '';
    if (value is bool || value is num) return value.toString();
    return jsonEncode(value.toString());
  }

  String _list(Object? value) {
    final items = value is List
        ? value
        : value
                  ?.toString()
                  .split(',')
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .toList() ??
              const [];
    return '[${items.map(_yaml).join(', ')}]';
  }

  num _sum(Object? left, Object? right) =>
      (num.tryParse(left?.toString() ?? '') ?? 0) +
      (num.tryParse(right?.toString() ?? '') ?? 0);

  String _bulletLines(String source) => source
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) => '- $line')
      .join('\n');
}
