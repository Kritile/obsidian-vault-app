import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class RichClipboard {
  static const _channel = MethodChannel('dev.pavelvault/clipboard');

  static Future<void> pasteInto(TextEditingController controller) async {
    String? value;
    try {
      final html = await _channel.invokeMethod<String>('getHtml');
      if (html != null && html.trim().isNotEmpty) {
        value = htmlToMarkdown(html);
      }
    } on MissingPluginException {
      // Desktop and tests use Flutter's plain-text clipboard fallback.
    } on PlatformException {
      // Clipboard access can be denied while the app is not focused.
    }
    value ??= (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (value == null) return;

    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : controller.text.length;
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
  }

  static String htmlToMarkdown(String html) {
    var value = html
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAll(
          RegExp(r'<(script|style)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false),
          '',
        );

    value = value.replaceAllMapped(
      RegExp(r'<h([1-6])\b[^>]*>([\s\S]*?)</h\1>', caseSensitive: false),
      (match) =>
          '${'#' * int.parse(match.group(1)!)} ${match.group(2)!.trim()}\n\n',
    );
    value = value.replaceAllMapped(
      RegExp(
        r'''<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>''',
        caseSensitive: false,
      ),
      (match) => '[${match.group(2)}](${_decodeEntities(match.group(1)!)})',
    );
    value = value.replaceAllMapped(
      RegExp(r'''<span\b([^>]*)>([\s\S]*?)</span>''', caseSensitive: false),
      (match) {
        final attributes = match.group(1)!.toLowerCase();
        var content = match.group(2)!;
        if (RegExp(r'font-weight\s*:\s*(bold|[6-9]00)').hasMatch(attributes)) {
          content = '**$content**';
        }
        if (RegExp(r'font-style\s*:\s*italic').hasMatch(attributes)) {
          content = '*$content*';
        }
        if (RegExp(
          r'text-decoration[^;]*(line-through)',
        ).hasMatch(attributes)) {
          content = '~~$content~~';
        }
        if (RegExp(r'text-decoration[^;]*(underline)').hasMatch(attributes)) {
          content = '<u>$content</u>';
        }
        return content;
      },
    );
    value = _wrap(value, const ['strong', 'b'], '**');
    value = _wrap(value, const ['em', 'i'], '*');
    value = _wrap(value, const ['del', 's', 'strike'], '~~');
    value = _wrap(value, const ['code'], '`');
    value = value.replaceAllMapped(
      RegExp(r'<u\b[^>]*>([\s\S]*?)</u>', caseSensitive: false),
      (match) => '<u>${match.group(1)}</u>',
    );
    value = value.replaceAllMapped(
      RegExp(r'<li\b[^>]*>([\s\S]*?)</li>', caseSensitive: false),
      (match) => '- ${match.group(1)!.trim()}\n',
    );
    value = value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|blockquote|pre)>', caseSensitive: false),
          '\n\n',
        )
        .replaceAll(RegExp(r'<(?!/?u\b)[^>]+>', caseSensitive: false), '');
    value = _decodeEntities(value)
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return value.trim();
  }

  static String _wrap(String source, List<String> tags, String marker) {
    var result = source;
    for (final tag in tags) {
      result = result.replaceAllMapped(
        RegExp('<$tag\\b[^>]*>([\\s\\S]*?)</$tag>', caseSensitive: false),
        (match) => '$marker${match.group(1)}$marker',
      );
    }
    return result;
  }

  static String _decodeEntities(String source) => source
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (match) => String.fromCharCode(int.parse(match.group(1)!)),
      );
}
