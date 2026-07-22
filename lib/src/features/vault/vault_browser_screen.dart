import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/vault/native_entity.dart';
import '../../core/vault/vault_models.dart';
import '../../shared/entity_form_sheet.dart';
import '../../shared/page_scaffold.dart';
import '../../shared/cached_vault_image.dart';
import 'note_screen.dart';

class VaultBrowserScreen extends ConsumerStatefulWidget {
  const VaultBrowserScreen({super.key});
  @override
  ConsumerState<VaultBrowserScreen> createState() => _VaultBrowserScreenState();
}

class _VaultBrowserScreenState extends ConsumerState<VaultBrowserScreen> {
  var _query = '';
  var _category = 'Все';
  var _sort = _VaultSort.modifiedDesc;
  static const _categories = [
    'Все',
    'Книги',
    'Рецепты',
    'Растения',
    'Чай',
    'Аптечка',
    'Заметки',
    'Файлы',
  ];

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(vaultControllerProvider);
    final searched = controller.index.search(_query);
    final notes = searched.where(_matchesCategory).toList()
      ..sort(_compareNotes);
    final files =
        (_category == 'Все' || _category == 'Файлы'
              ? controller.index.searchFiles(_query).toList()
              : <VaultDocument>[])
          ..sort(_compareFiles);
    final narrow = MediaQuery.sizeOf(context).width < 380;
    return PageScaffold(
      title: 'Коллекции',
      subtitle: 'Книги, рецепты, растения и остальные данные',
      actions: [
        IconButton.filled(
          tooltip: 'Добавить',
          onPressed: () => showCreateEntityPicker(context, ref),
          icon: const Icon(Icons.add),
        ),
      ],
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                narrow ? 12 : 20,
                0,
                narrow ? 12 : 20,
                10,
              ),
              child: SearchBar(
                hintText: narrow ? 'Поиск' : 'Поиск по коллекциям',
                leading: const Icon(Icons.search),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 20),
              child: _VaultFilterBar(
                categories: _categories,
                category: _category,
                sort: _sort,
                onCategory: (value) => setState(() => _category = value),
                onSort: (value) => setState(() => _sort = value),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          if (notes.isEmpty && files.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('В этой коллекции пока ничего нет')),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                narrow ? 8 : 16,
                0,
                narrow ? 8 : 16,
                28,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: narrow ? 500 : 390,
                  mainAxisExtent: narrow ? 154 : 174,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: notes.length + files.length,
                  (context, index) => index < notes.length
                      ? _EntityCard(
                          note: notes[index],
                          onTap: () => _open(notes[index]),
                        )
                      : _FileCard(file: files[index - notes.length]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _matchesCategory(ParsedNote note) => switch (_category) {
    'Книги' => note.document.path.startsWith('Areas/Книги/'),
    'Рецепты' => note.document.path.startsWith('Areas/Recipes/'),
    'Растения' => note.document.path.startsWith('Areas/Растения/'),
    'Чай' => note.document.path.startsWith('Areas/Чай/'),
    'Аптечка' => note.document.path.startsWith('Areas/Аптечка/'),
    'Заметки' => !_isCollection(note.document.path),
    'Файлы' => false,
    _ => true,
  };

  bool _isCollection(String path) =>
      path.startsWith('Areas/Книги/') ||
      path.startsWith('Areas/Recipes/') ||
      path.startsWith('Areas/Растения/') ||
      path.startsWith('Areas/Чай/') ||
      path.startsWith('Areas/Аптечка/');

  int _compareNotes(ParsedNote a, ParsedNote b) => switch (_sort) {
    _VaultSort.nameAsc => _title(a).compareTo(_title(b)),
    _VaultSort.nameDesc => _title(b).compareTo(_title(a)),
    _VaultSort.modifiedDesc => _thenTitle(
      b.document.modifiedAt.compareTo(a.document.modifiedAt),
      a,
      b,
    ),
    _VaultSort.modifiedAsc => _thenTitle(
      a.document.modifiedAt.compareTo(b.document.modifiedAt),
      a,
      b,
    ),
    _VaultSort.createdDesc => _thenTitle(
      _created(b).compareTo(_created(a)),
      a,
      b,
    ),
    _VaultSort.createdAsc => _thenTitle(
      _created(a).compareTo(_created(b)),
      a,
      b,
    ),
    _VaultSort.ratingDesc => _thenTitle(_rating(b).compareTo(_rating(a)), a, b),
    _VaultSort.category => _thenTitle(
      _categoryRank(a.document.path).compareTo(_categoryRank(b.document.path)),
      a,
      b,
    ),
  };

  int _compareFiles(VaultDocument a, VaultDocument b) => switch (_sort) {
    _VaultSort.nameAsc => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
    _VaultSort.nameDesc => b.path.toLowerCase().compareTo(a.path.toLowerCase()),
    _VaultSort.createdAsc ||
    _VaultSort.modifiedAsc => a.modifiedAt.compareTo(b.modifiedAt),
    _VaultSort.createdDesc ||
    _VaultSort.modifiedDesc => b.modifiedAt.compareTo(a.modifiedAt),
    _VaultSort.ratingDesc ||
    _VaultSort.category => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
  };

  String _title(ParsedNote note) =>
      (note.frontmatter['title']?.toString() ?? note.title).toLowerCase();

  DateTime _created(ParsedNote note) => note.date ?? note.document.modifiedAt;

  double _rating(ParsedNote note) =>
      double.tryParse(
        note.frontmatter['rating']?.toString().replaceAll(',', '.') ?? '',
      ) ??
      -1;

  int _thenTitle(int result, ParsedNote a, ParsedNote b) =>
      result == 0 ? _title(a).compareTo(_title(b)) : result;

  int _categoryRank(String path) {
    if (path.startsWith('Areas/Книги/')) return 0;
    if (path.startsWith('Areas/Recipes/')) return 1;
    if (path.startsWith('Areas/Растения/')) return 2;
    if (path.startsWith('Areas/Чай/')) return 3;
    if (path.startsWith('Areas/Аптечка/')) return 4;
    return 5;
  }

  void _open(ParsedNote note) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => NoteScreen(note: note)));
}

class _VaultFilterBar extends StatelessWidget {
  const _VaultFilterBar({
    required this.categories,
    required this.category,
    required this.sort,
    required this.onCategory,
    required this.onSort,
  });
  final List<String> categories;
  final String category;
  final _VaultSort sort;
  final ValueChanged<String> onCategory;
  final ValueChanged<_VaultSort> onSort;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final strip = _CategoryStrip(
        categories: categories,
        selected: category,
        onSelected: onCategory,
      );
      final sortButton = _VaultSortButton(value: sort, onSelected: onSort);
      if (constraints.maxWidth < 430) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            strip,
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerRight, child: sortButton),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: strip),
          const SizedBox(width: 8),
          sortButton,
        ],
      );
    },
  );
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: categories
          .map(
            (category) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(category),
                selected: selected == category,
                onSelected: (_) => onSelected(category),
              ),
            ),
          )
          .toList(growable: false),
    ),
  );
}

class _VaultSortButton extends StatelessWidget {
  const _VaultSortButton({required this.value, required this.onSelected});
  final _VaultSort value;
  final ValueChanged<_VaultSort> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_VaultSort>(
    tooltip: 'Сортировка',
    initialValue: value,
    onSelected: onSelected,
    itemBuilder: (context) => _VaultSort.values
        .map(
          (item) => PopupMenuItem(
            value: item,
            child: Row(
              children: [
                SizedBox(width: 28, child: Icon(item.icon, size: 19)),
                Expanded(child: Text(item.label)),
                if (item == value) const Icon(Icons.check, size: 18),
              ],
            ),
          ),
        )
        .toList(growable: false),
    child: Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sort, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
      ),
    ),
  );
}

enum _VaultSort {
  modifiedDesc('Сначала недавно изменённые', Icons.update),
  modifiedAsc('Сначала давно изменённые', Icons.history),
  nameAsc('Название: А — Я', Icons.sort_by_alpha),
  nameDesc('Название: Я — А', Icons.sort_by_alpha),
  createdDesc('Сначала новые', Icons.calendar_month),
  createdAsc('Сначала старые', Icons.calendar_today_outlined),
  ratingDesc('Сначала с высоким рейтингом', Icons.star_outline),
  category('По типу коллекции', Icons.category_outlined);

  const _VaultSort(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _EntityCard extends ConsumerWidget {
  const _EntityCard({required this.note, required this.onTap});
  final ParsedNote note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = _kind(note.document.path);
    final details = _details(note, kind);
    final image = _image(note, kind);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 92,
              height: double.infinity,
              child: image == null
                  ? ColoredBox(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: Icon(entityKindIcon(kind), size: 38),
                    )
                  : CachedVaultImage(
                      source: image,
                      notePath: note.document.path,
                      fit: BoxFit.cover,
                      placeholder: Icon(entityKindIcon(kind), size: 38),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _label(kind),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      note.frontmatter['title']?.toString() ?? note.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (note.tags.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        note.tags.take(3).map((tag) => '#$tag').join(' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  NativeEntityKind _kind(String path) {
    if (path.startsWith('Areas/Книги/')) return NativeEntityKind.book;
    if (path.startsWith('Areas/Recipes/')) return NativeEntityKind.recipe;
    if (path.startsWith('Areas/Растения/')) return NativeEntityKind.plant;
    if (path.startsWith('Areas/Чай/')) return NativeEntityKind.tea;
    if (path.startsWith('Areas/Аптечка/')) return NativeEntityKind.medicine;
    return NativeEntityKind.note;
  }

  String _label(NativeEntityKind kind) => nativeEntityDefinitions
      .firstWhere((item) => item.kind == kind)
      .label
      .toUpperCase();

  String _details(ParsedNote note, NativeEntityKind kind) => switch (kind) {
    NativeEntityKind.book => [
      note.frontmatter['author'],
      note.frontmatter['status'],
      note.frontmatter['rating'] == null
          ? null
          : '★ ${note.frontmatter['rating']}',
    ].whereType<Object>().join(' · '),
    NativeEntityKind.recipe =>
      '${note.frontmatter['difficulty'] ?? '—'} · ${note.frontmatter['total_time'] ?? '—'} мин · ${note.frontmatter['servings'] ?? '—'} порц.',
    NativeEntityKind.plant =>
      note.frontmatter['Латинское название']?.toString() ?? 'Карточка ухода',
    NativeEntityKind.tea =>
      '${note.frontmatter['category'] ?? 'Чай'} · ${note.frontmatter['origin'] ?? ''}',
    NativeEntityKind.medicine =>
      '${note.frontmatter['dosage'] ?? ''} · остаток ${note.frontmatter['remainder'] ?? '—'}${note.frontmatter['active'] == true ? ' · принимаю' : ''}',
    NativeEntityKind.note => note.document.path,
  };

  String? _image(ParsedNote note, NativeEntityKind kind) => switch (kind) {
    NativeEntityKind.book => note.frontmatter['cover']?.toString(),
    NativeEntityKind.plant => note.frontmatter['Фото']?.toString(),
    NativeEntityKind.tea => note.frontmatter['image']?.toString(),
    _ => null,
  };
}

class _FileCard extends StatelessWidget {
  const _FileCard({required this.file});
  final VaultDocument file;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.attachment),
          const Spacer(),
          Text(
            file.path.split('/').last,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(file.path, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    ),
  );
}
