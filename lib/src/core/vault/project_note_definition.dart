import 'package:flutter/material.dart';

class ProjectNoteSection {
  const ProjectNoteSection(this.heading, {this.hint = '', this.lines = 3});
  final String heading;
  final String hint;
  final int lines;
}

class ProjectNoteDefinition {
  const ProjectNoteDefinition({
    required this.key,
    required this.label,
    required this.templateName,
    required this.icon,
    required this.color,
    required this.sections,
  });
  final String key;
  final String label;
  final String templateName;
  final IconData icon;
  final Color color;
  final List<ProjectNoteSection> sections;
}

const projectNoteDefinitions = <ProjectNoteDefinition>[
  ProjectNoteDefinition(
    key: 'general',
    label: 'Общая заметка',
    templateName: 'General',
    icon: Icons.notes_outlined,
    color: Color(0xff4dabf7),
    sections: [
      ProjectNoteSection('Заметка', hint: 'Основной контекст', lines: 5),
      ProjectNoteSection('Следующие шаги', hint: '- [ ] Действие'),
      ProjectNoteSection('Связанные материалы', hint: '- [[Ссылка]]'),
    ],
  ),
  ProjectNoteDefinition(
    key: 'meeting',
    label: 'Встреча',
    templateName: 'Meeting',
    icon: Icons.groups_outlined,
    color: Color(0xff20c997),
    sections: [
      ProjectNoteSection('Участники', hint: '- Имя'),
      ProjectNoteSection('Повестка', hint: '- Вопрос'),
      ProjectNoteSection('Решения', hint: '- Решение'),
      ProjectNoteSection('Задачи', hint: '- [ ] Действие'),
    ],
  ),
  ProjectNoteDefinition(
    key: 'decision',
    label: 'Решение',
    templateName: 'Decision',
    icon: Icons.alt_route_outlined,
    color: Color(0xff845ef7),
    sections: [
      ProjectNoteSection('Решение', hint: 'Что решили', lines: 4),
      ProjectNoteSection('Причины', hint: '- Причина'),
      ProjectNoteSection('Последствия', hint: '- Последствие'),
      ProjectNoteSection('Связанные материалы', hint: '- [[Ссылка]]'),
    ],
  ),
  ProjectNoteDefinition(
    key: 'brief',
    label: 'Бриф',
    templateName: 'Brief',
    icon: Icons.assignment_outlined,
    color: Color(0xffff922b),
    sections: [
      ProjectNoteSection('Цель', hint: 'Цель работы', lines: 4),
      ProjectNoteSection('Контекст', hint: 'Исходная ситуация', lines: 4),
      ProjectNoteSection('Требования', hint: '- Требование'),
      ProjectNoteSection('Ограничения', hint: '- Ограничение'),
      ProjectNoteSection('Ожидаемый результат', hint: 'Критерии результата'),
    ],
  ),
  ProjectNoteDefinition(
    key: 'reference',
    label: 'Справочник',
    templateName: 'Reference',
    icon: Icons.menu_book_outlined,
    color: Color(0xff22b8cf),
    sections: [
      ProjectNoteSection('Назначение', hint: 'Для чего нужен материал'),
      ProjectNoteSection('Данные', hint: 'Справочная информация', lines: 6),
      ProjectNoteSection('Связанные материалы', hint: '- [[Ссылка]]'),
    ],
  ),
  ProjectNoteDefinition(
    key: 'report',
    label: 'Отчёт',
    templateName: 'Report',
    icon: Icons.analytics_outlined,
    color: Color(0xfff06595),
    sections: [
      ProjectNoteSection('Результат', hint: 'Главный результат', lines: 4),
      ProjectNoteSection('Выполнено', hint: '- Пункт'),
      ProjectNoteSection('Метрики', hint: '- Метрика: значение'),
      ProjectNoteSection('Риски и ограничения', hint: '- Риск'),
    ],
  ),
];

ProjectNoteDefinition projectNoteDefinition(String key) =>
    projectNoteDefinitions.firstWhere(
      (item) => item.key == key,
      orElse: () => projectNoteDefinitions.first,
    );
