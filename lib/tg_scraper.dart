import 'dart:convert';
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
    final ts = DateTime.now().millisecondsSinceEpoch;
    final directUrl = 'https://t.me/s/$channel?t=$ts';

    // Список путей: сначала прямой, затем зеркала/прокси на случай блокировки/зависания
    final List<String> endpoints = [
      directUrl,
      'https://api.allorigins.win/raw?url=${Uri.encodeComponent(directUrl)}',
      'https://api.codetabs.com/v1/proxy?quest=${Uri.encodeComponent(directUrl)}',
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await http.get(
          Uri.parse(endpoint),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14; SM-S928B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
            'Accept-Language': 'ru-RU,ru;q=0.9',
            'Cache-Control': 'no-cache',
          },
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200 && response.body.contains('tgme_widget_message')) {
          return _parseHtml(response.body, channel);
        }
      } catch (_) {
        // Переходим к следующему зеркалу без зависания
        continue;
      }
    }

    return [];
  }

  static List<ScrapedMessage> _parseHtml(String htmlBody, String channel) {
    final List<ScrapedMessage> results = [];
    try {
      final document = html_parser.parse(utf8.decode(htmlBody.runes.toList(), allowMalformed: true));
      final nodes = document.querySelectorAll('.tgme_widget_message_wrap');

      final recentNodes =
          nodes.length > 12 ? nodes.sublist(nodes.length - 12) : nodes;

      for (final node in recentNodes) {
        final msgBox = node.querySelector('.tgme_widget_message');
        final postId = msgBox?.attributes['data-post'] ?? '';
        if (postId.isEmpty) continue;

        final textNode = node.querySelector('.tgme_widget_message_text');
        final rawText = textNode?.text.trim() ?? '';
        if (rawText.isEmpty) continue;

        DateTime postTime = DateTime.now();
        final timeElement = node.querySelector('time');
        final dtAttr = timeElement?.attributes['datetime'];
        if (dtAttr != null) {
          final parsed = DateTime.tryParse(dtAttr);
          if (parsed != null) postTime = parsed.toLocal();
        }

        // Отсекаем посты старше 45 минут
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
    } catch (_) {}

    return results;
  }
}
