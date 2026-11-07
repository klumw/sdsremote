import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

/// HTTP client wrapper that disables DeepSeek's thinking mode.
///
/// DeepSeek V4 models enable thinking by default and accept a top-level
/// `thinking` object in the OpenAI-compatible `/chat/completions` request
/// body. `openai_dart` has no field for that parameter, so this wrapper adds
/// it to every DeepSeek request before forwarding the request to [inner].
///
/// The wrapper only touches JSON object bodies and preserves an explicitly
/// configured `thinking` value.
class DeepSeekThinkingClient extends http.BaseClient {
  /// Creates a client that wraps [inner].
  DeepSeekThinkingClient({required this.inner});

  /// The client that performs the HTTP request.
  final http.Client inner;

  static final Logger _logger = Logger('dartantic.deepseek.thinking');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is http.Request &&
        request.url.host.toLowerCase().contains('deepseek.com')) {
      _disableThinking(request);
    }
    return inner.send(request);
  }

  @override
  void close() => inner.close();

  void _disableThinking(http.Request request) {
    if (request.bodyBytes.isEmpty) return;

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(request.bodyBytes));
    } on FormatException {
      return;
    }

    if (decoded is! Map<String, dynamic>) return;
    if (decoded.containsKey('thinking')) return;

    decoded['thinking'] = <String, dynamic>{'type': 'disabled'};
    request.body = jsonEncode(decoded);
    // The body length changed; let the HTTP client recompute the header.
    request.headers.remove('content-length');
    _logger.fine('Disabled DeepSeek thinking for ${request.url.path}');
  }
}
