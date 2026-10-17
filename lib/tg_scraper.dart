import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

class ScrapedMessage {
  final String postId;
  final String channel;
  final String text;
  final DateTime timestamp;

  ScrapedMessage({
    required this.postId,
    required this.channel,
    required this.text,
    required this.timestamp,
  });
}

class TelegramWebScraper {
  static final Set<String> _processedIds = {};

  static Future<List<ScrapedMessage>> fetchChannel(
    String channel, {
    bool isInitialLoad = false,
  }) async {
    final List<ScrapedMessage> results = [];
    // Параметр t обходит кэширование прокси
    final uri = Uri.parse(
      'https://t.me/s/$channel?t=${DateTime.now().millisecondsSinceEpoch}',
    );

    try {
      final response = await http.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14; SM-S928B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
          'Accept-Language': 'ru-RU,ru;q=0.9',
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return results;

      final document = html_parser.parse(response.body);
      final nodes = document.querySelectorAll('.tgme_widget_message_wrap');

      // Берем последние 12 постов в канале
      final recentNodes = nodes.length > 12 ? nodes.sublist(nodes.length - 12) : nodes;

      for (final node in recentNodes) {
        final msgBox = node.querySelector('.tgme_widget_message');
        final postId = msgBox?.attributes['data-post'] ?? '';
        if (postId.isEmpty) continue;

        final textNode = node.querySelector('.tgme_widget_message_text');
        final rawText = textNode?.text.trim() ?? '';
        if (rawText.isEmpty) continue;

        // Достаем реальное время публикации из тега <time datetime="...">
        DateTime postTime = DateTime.now();
        final timeElement = node.querySelector('time');
        final dtAttr = timeElement?.attributes['datetime'];
        if (dtAttr != null) {
          final parsed = DateTime.tryParse(dtAttr);
          if (parsed != null) postTime = parsed.toLocal();
        }

        // Отсекаем сообщения старше 45 минут
        if (DateTime.now().difference(postTime).inMinutes > 45) {
          _processedIds.add(postId);
          continue;
        }

        if (!_processedIds.contains(postId)) {
          _processedIds.add(postId);
          results.add(
            ScrapedMessage(
              postId: postId,
              channel: channel,
              text: rawText,
              timestamp: postTime,
            ),
          );
        }
      }
    } catch (_) {
      // При потере сети приложение не падает, а ждет следующего цикла
    }

    return results;
  }
}