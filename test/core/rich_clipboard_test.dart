import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/shared/rich_clipboard.dart';

void main() {
  test('converts common rich clipboard HTML to Markdown', () {
    final markdown = RichClipboard.htmlToMarkdown(
      '<h2>Заголовок</h2><p><strong>Жирный</strong> и <em>курсив</em></p>'
      '<ul><li>Первый</li><li><a href="https://example.com">Ссылка</a></li></ul>',
    );

    expect(markdown, contains('## Заголовок'));
    expect(markdown, contains('**Жирный** и *курсив*'));
    expect(markdown, contains('- Первый'));
    expect(markdown, contains('- [Ссылка](https://example.com)'));
  });

  test('preserves common inline CSS styles from mobile clipboards', () {
    final markdown = RichClipboard.htmlToMarkdown(
      '<p><span style="font-weight: 700">Важно</span> '
      '<span style="text-decoration: underline">сейчас</span></p>',
    );

    expect(markdown, '**Важно** <u>сейчас</u>');
  });
}
