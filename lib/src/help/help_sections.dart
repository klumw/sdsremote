/// Section index of the user manual.
///
/// The help window renders `assets/manuals/sds_manual.md` and scrolls to
/// headings through their anchor slugs; the AI help assistant must emit
/// exactly those slugs so its links land on the same headings. Both sides
/// therefore share the slug rules and the section extraction in this file.
library;

/// One heading of the manual: its display title and the anchor slug that
/// scrolls to it.
typedef HelpSection = ({String title, String slug});

/// GitHub-style anchor slug of a heading: lower-cased, punctuation removed
/// and every space turned into a dash, so "4.1 AI Model Configuration"
/// becomes `41-ai-model-configuration`.
///
/// Fragments of in-document links are written by hand and resolved against
/// these slugs — see [resolveHeadingAnchor].
String markdownHeadingSlug(String headingText) {
  return headingText
      .trim()
      .toLowerCase()
      // Emoji and other non-ASCII symbols are not part of the anchor.
      .replaceAll(RegExp(r'[^\x00-\x7F]'), '')
      // Punctuation is dropped while `-` and `_` survive, mirroring the slugs
      // GitHub generates — which is what a cross-reference is copied from.
      .replaceAll(RegExp(r'''[!"#$%&'()*+,./:;<=>?@\[\\\]^`{|}~]'''), '')
      .replaceAll(' ', '-')
      // Removing a trailing symbol can leave a dash; hand-written links omit
      // it, so trim the edges.
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Returns the slug from [slugs] that the link fragment [fragment] points at,
/// or `null` when no heading matches.
///
/// The exact slug wins.  As a fallback the collapsed fragment is tried, since
/// dropping a punctuation character leaves two dashes behind: the heading
/// "1. Introduction & Overview" generates `1-introduction--overview`, while a
/// hand-written link is likely to spell it `1-introduction-overview`.
String? resolveHeadingAnchor(String fragment, Iterable<String> slugs) {
  final collapsed = fragment.replaceAll(RegExp(r'-+'), '-');
  String? fallback;
  for (final slug in slugs) {
    if (slug == fragment) return slug;
    if (fallback == null && slug.replaceAll(RegExp(r'-+'), '-') == collapsed) {
      fallback = slug;
    }
  }
  return fallback;
}

/// Extracts every ATX heading of [markdown] as a [HelpSection] in document
/// order.
///
/// Fenced code blocks are skipped so `#` lines inside examples are not
/// mistaken for headings. Headings without text (such as the manual's bare
/// leading `#`) produce an empty slug and are dropped.
List<HelpSection> extractHelpSections(String markdown) {
  final sections = <HelpSection>[];
  var inCodeBlock = false;
  for (final line in markdown.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inCodeBlock = !inCodeBlock;
      continue;
    }
    if (inCodeBlock) continue;

    final match = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (match == null) continue;
    final title = match.group(2)!.trim();
    final slug = markdownHeadingSlug(title);
    if (title.isEmpty || slug.isEmpty) continue;
    sections.add((title: title, slug: slug));
  }
  return sections;
}
