/// Markdown device knowledge: parsing, section lookup and search.
///
/// A knowledge document starts with a metadata comment that binds it to one
/// device profile. The loader refuses a document whose `device_profile` does
/// not match the command package, which prevents mixing (for example) the
/// FY6900 command package with the JDS6600 knowledge.
library;

import 'device_profile_models.dart';

/// Metadata from the leading HTML comment of a knowledge document.
class DeviceKnowledgeMetadata {
  const DeviceKnowledgeMetadata({
    required this.profileId,
    required this.version,
    required this.source,
    required this.validationStatus,
    this.fields = const {},
  });

  final String profileId;
  final String version;
  final String source;
  final String validationStatus;
  final Map<String, String> fields;

  Map<String, dynamic> toJson() => {
    'profile': profileId,
    'knowledge_version': version,
    'source': source,
    'validation_status': validationStatus,
    if (fields.isNotEmpty) 'fields': fields,
  };
}

/// One heading section of a knowledge document.
class DeviceKnowledgeSection {
  const DeviceKnowledgeSection({
    required this.id,
    required this.title,
    required this.level,
    required this.startLine,
    required this.endLine,
    required this.body,
    required this.content,
    required this.path,
  });

  /// Slug derived from [title], for example `1-device-profile`.
  final String id;

  final String title;
  final int level;

  /// 1-based line numbers in the source document.
  final int startLine;
  final int endLine;

  /// Section text without the heading.
  final String body;

  /// Heading line plus [body].
  final String content;

  /// Parent headings, outermost first.
  final List<String> path;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'level': level,
    'start_line': startLine,
    'end_line': endLine,
    'content': content,
  };
}

/// One search hit in a knowledge document.
class DeviceKnowledgeSearchResult {
  const DeviceKnowledgeSearchResult({
    required this.section,
    required this.score,
  });

  final DeviceKnowledgeSection section;
  final int score;

  Map<String, dynamic> toJson() => {
    'section': section.title,
    'id': section.id,
    'score': score,
    'content': section.content,
  };
}

/// Parsed knowledge document bound to one profile.
class DeviceKnowledgeDocument {
  const DeviceKnowledgeDocument({
    required this.metadata,
    required this.rawMarkdown,
    required this.bodyMarkdown,
    required this.sections,
    required this.sourcePath,
  });

  final DeviceKnowledgeMetadata metadata;

  /// Complete file content, including the metadata comment.
  final String rawMarkdown;

  /// Markdown after the metadata comment, suitable for prompt context.
  final String bodyMarkdown;

  final List<DeviceKnowledgeSection> sections;
  final String sourcePath;

  /// Returns a section by id, title, number prefix (`1`, `1.`) or id prefix.
  DeviceKnowledgeSection? getSection(String key) {
    final query = key.trim().toLowerCase();
    if (query.isEmpty) return null;
    for (final section in sections) {
      final title = section.title.toLowerCase();
      if (section.id == query || title == query) return section;
      if (title.startsWith('$query.') || title.startsWith('$query ')) {
        return section;
      }
      if (section.id.startsWith('$query-')) return section;
    }
    return null;
  }

  /// Searches section titles and bodies with a simple whole-word score.
  ///
  /// The implementation deliberately mirrors the AI Chat knowledgebase search:
  /// words longer than two characters, title matches weighted higher, no
  /// external index. It is sufficient for documents of a few dozen sections.
  List<DeviceKnowledgeSearchResult> search(String query, {int limit = 5}) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9_]+'))
        .where((word) => word.length > 2)
        .toSet();
    if (words.isEmpty) return const [];

    final results = <DeviceKnowledgeSearchResult>[];
    for (final section in sections) {
      final title = section.title.toLowerCase();
      final content = section.content.toLowerCase();
      var score = 0;
      for (final word in words) {
        if (title.contains(word)) score += 3;
        if (content.contains(word)) score += 1;
      }
      if (score > 0) {
        results.add(
          DeviceKnowledgeSearchResult(section: section, score: score),
        );
      }
    }
    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.section.startLine.compareTo(b.section.startLine);
    });
    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }

  /// Returns section titles that mention one command id or command name.
  List<String> referencesFor(String commandIdOrName) {
    final needle = commandIdOrName.trim().toLowerCase();
    if (needle.length < 2) return const [];
    return [
      for (final section in sections)
        if (section.content.toLowerCase().contains(needle)) section.title,
    ];
  }

  Map<String, dynamic> toJson() => {
    'metadata': metadata.toJson(),
    'source': sourcePath,
    'section_count': sections.length,
    'sections': [for (final section in sections) section.toJson()],
  };
}

/// Parses and validates one knowledge document.
abstract final class DeviceKnowledgeParser {
  static final RegExp _metadataPattern = RegExp(r'^\s*<!--([\s\S]*?)-->');

  static DeviceKnowledgeDocument parse({
    required String expectedProfileId,
    required String markdown,
    required String sourcePath,
  }) {
    // A Windows checkout (core.autocrlf) or a Windows editor can deliver CRLF
    // line endings. Normalize them once: the heading pattern anchors with `$`,
    // which does not match before a trailing `\r`, and stored prompts should
    // not carry platform-specific line endings.
    final normalized = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final metadataMatch = _metadataPattern.firstMatch(normalized);
    if (metadataMatch == null) {
      throw DeviceCommandException(
        DeviceErrorCode.knowledgeFileInvalid,
        'The knowledge file "$sourcePath" must start with a metadata comment '
        'containing "device_profile".',
        profile: expectedProfileId,
        details: {'source': sourcePath},
      );
    }

    final fields = <String, String>{};
    for (final rawLine in metadataMatch.group(1)!.split('\n')) {
      final line = rawLine.trim();
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) fields[key] = value;
    }

    final declaredProfile = DeviceProfileIds.normalize(
      fields['device_profile'],
    );
    if (declaredProfile == null) {
      throw DeviceCommandException(
        DeviceErrorCode.knowledgeFileInvalid,
        'The knowledge file "$sourcePath" does not declare "device_profile".',
        profile: expectedProfileId,
        details: {'source': sourcePath},
      );
    }
    if (declaredProfile != expectedProfileId) {
      throw DeviceCommandException(
        DeviceErrorCode.knowledgeProfileMismatch,
        'The knowledge file "$sourcePath" belongs to profile '
        '"$declaredProfile", not "$expectedProfileId".',
        profile: expectedProfileId,
        requestedValue: declaredProfile,
        details: {'source': sourcePath},
      );
    }

    final body = normalized.substring(metadataMatch.end).trimLeft();
    final sections = _parseSections(body);
    if (sections.isEmpty) {
      throw DeviceCommandException(
        DeviceErrorCode.knowledgeFileInvalid,
        'The knowledge file "$sourcePath" contains no Markdown sections.',
        profile: expectedProfileId,
        details: {'source': sourcePath},
      );
    }

    return DeviceKnowledgeDocument(
      metadata: DeviceKnowledgeMetadata(
        profileId: declaredProfile,
        version: fields['knowledge_version'] ?? 'unversioned',
        source: fields['source'] ?? sourcePath,
        validationStatus: fields['validation_status'] ?? 'not_specified',
        fields: Map.unmodifiable(fields),
      ),
      rawMarkdown: normalized,
      bodyMarkdown: body,
      sections: sections,
      sourcePath: sourcePath,
    );
  }

  static List<DeviceKnowledgeSection> _parseSections(String markdown) {
    final lines = markdown.split('\n');
    final headings = <({int index, int level, String title})>[];
    final headingPattern = RegExp(r'^(#{1,6})\s+(.*)$');
    for (var index = 0; index < lines.length; index++) {
      final match = headingPattern.firstMatch(lines[index]);
      if (match == null) continue;
      headings.add((
        index: index,
        level: match.group(1)!.length,
        title: match.group(2)!.trim(),
      ));
    }
    if (headings.isEmpty) return const [];

    final sections = <DeviceKnowledgeSection>[];
    final ids = <String>{};
    final stack = <({int level, String title})>[];
    for (var position = 0; position < headings.length; position++) {
      final heading = headings[position];
      final nextLine = position + 1 < headings.length
          ? headings[position + 1].index
          : lines.length;
      while (stack.isNotEmpty && stack.last.level >= heading.level) {
        stack.removeLast();
      }
      final path = stack.map((entry) => entry.title).toList(growable: false);
      stack.add((level: heading.level, title: heading.title));

      final body = lines.sublist(heading.index + 1, nextLine).join('\n').trim();
      final content = [heading.title, if (body.isNotEmpty) body].join('\n\n');
      var id = _slug(heading.title);
      if (id.isEmpty) id = 'section-${sections.length + 1}';
      var uniqueId = id;
      var suffix = 2;
      while (!ids.add(uniqueId)) {
        uniqueId = '$id-$suffix';
        suffix++;
      }

      sections.add(
        DeviceKnowledgeSection(
          id: uniqueId,
          title: heading.title,
          level: heading.level,
          startLine: heading.index + 1,
          endLine: nextLine,
          body: body,
          content: content,
          path: path,
        ),
      );
    }
    return List.unmodifiable(sections);
  }

  static String _slug(String title) => title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
