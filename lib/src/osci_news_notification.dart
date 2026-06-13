import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import '../logger.dart';

class SdsNotification {
  final int id;
  final String title;
  final String description;
  final bool forceShow;

  SdsNotification({
    required this.id,
    required this.title,
    required this.description,
    required this.forceShow,
  });

  factory SdsNotification.fromJson(Map<String, dynamic> json) {
    final n = json['notification'];
    return SdsNotification(
      id: n['id'],
      title: n['title'],
      description: n['description'],
      forceShow: n['force_show'] ?? false,
    );
  }
}

class NewsNotificationService {
  static const String _url =
      'https://drive.google.com/uc?export=download&id=1Ra5ScXp8KdcuLaCgJeiXLB_eFM7xzVaC';
  static const String _prefKey = 'news_last_read_id';

  Future<SdsNotification?> fetchNotification() async {
    try {
      final response = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return SdsNotification.fromJson(json);
      }
    } catch (e) {
      AppLogger().log('Failed to fetch news notification: $e');
    }
    return null;
  }

  Future<int?> getLastReadId() async {
    return AppPreferences.getInt(_prefKey);
  }

  Future<void> markAsRead(int id) async {
    await AppPreferences.setInt(_prefKey, id);
  }
}

class IconSyntax extends md.InlineSyntax {
  IconSyntax() : super(r':([a-zA-Z_]+):');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final iconName = match[1]!;
    parser.addNode(md.Element.text('icon', iconName));
    return true;
  }
}

class IconMarkdownBuilder extends MarkdownElementBuilder {
  static const Map<String, IconData> _iconMap = {
    'info': Icons.info,
    'warning': Icons.warning,
    'error': Icons.error,
    'check': Icons.check_circle,
    'settings': Icons.settings,
    'home': Icons.home,
    'search': Icons.search,
    'star': Icons.star,
    'favorite': Icons.favorite,
    'help': Icons.help,
    'update': Icons.system_update,
    'download': Icons.download,
    'new_release': Icons.new_releases,
    'bug': Icons.bug_report,
    'light': Icons.lightbulb,
    'tip': Icons.tips_and_updates,
  };

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final iconData = _iconMap[element.textContent];
    if (iconData != null) {
      return Icon(iconData, size: 16, color: Colors.cyanAccent);
    }
    return null;
  }
}

class NewsNotificationDialog extends StatelessWidget {
  final SdsNotification notification;
  final VoidCallback onDismiss;

  const NewsNotificationDialog({
    super.key,
    required this.notification,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0A192F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: Markdown(
                data: notification.description,
                extensionSet: md.ExtensionSet(
                  md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                  [
                    IconSyntax(),
                    ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                  ],
                ),
                builders: {'icon': IconMarkdownBuilder()},
                onTapLink: (text, href, title) {
                  if (href != null) {
                    launchUrl(
                      Uri.parse(href),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () {
                  onDismiss();
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
