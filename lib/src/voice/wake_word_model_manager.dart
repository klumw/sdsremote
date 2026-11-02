import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import '../app/app_paths.dart';
import '../core/logger.dart';

/// Thrown when the wakeword model cannot be prepared. The [message] is meant
/// to be shown to the user.
class WakeWordException implements Exception {
  const WakeWordException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Downloads and extracts the sherpa-onnx keyword-spotting model used by the
/// wakeword detector.
///
/// The official release archive contains FP32 and int8 models plus test audio.
/// Only the small int8 model, its tokens and a generated keywords file are
/// extracted, which keeps the on-disk footprint at about 5.5 MB.
class WakeWordModelManager {
  WakeWordModelManager({
    http.Client? httpClient,
    Directory? modelDirectory,
    this.downloadUrl = defaultDownloadUrl,
    AppLogger? logger,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _modelDirectory = modelDirectory,
       _logger = logger ?? AppLogger(agentName: 'WakeWord', toolName: 'model');

  static const String defaultDownloadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/'
      'sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01.tar.bz2';

  static const String encoderFileName =
      'encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx';
  static const String decoderFileName =
      'decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx';
  static const String joinerFileName =
      'joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx';
  static const String tokensFileName = 'tokens.txt';
  static const String keywordsFileName = 'keywords.txt';

  /// Files the keyword spotter needs, relative to the model directory.
  static const List<String> requiredFileNames = [
    encoderFileName,
    decoderFileName,
    joinerFileName,
    tokensFileName,
  ];

  /// BPE token sequence for "HEY ASSISTANT", produced with the model's own
  /// `bpe.model` via SentencePiece.
  static const String wakeWordKeywordLine = '▁HE Y ▁AS S IST ANT';

  final String downloadUrl;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Directory? _modelDirectory;
  final AppLogger _logger;

  Directory get modelDirectory =>
      _modelDirectory ?? AppPaths.wakeWordModelDirectory;

  /// Ensures a complete model is available and returns its directory.
  ///
  /// [onProgress] receives a value between 0 and 1 while the archive is being
  /// downloaded. It is not called when the model already exists.
  Future<Directory> ensureModel({
    void Function(double progress)? onProgress,
  }) async {
    final target = modelDirectory;
    if (await _hasModelFiles(target)) {
      await _ensureKeywordsFile(target);
      return target;
    }

    await _logger.log('Wakeword model missing; downloading $downloadUrl');
    final parent = target.parent;
    await parent.create(recursive: true);

    final tempDirectory = Directory('${target.path}.tmp');
    final archiveFile = File(
      '${parent.path}${Platform.pathSeparator}wakeword-model.tar.bz2.download',
    );
    try {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
      await tempDirectory.create(recursive: true);

      await _download(archiveFile, onProgress: onProgress);
      await _extract(archiveFile, tempDirectory);

      if (await target.exists()) {
        await target.delete(recursive: true);
      }
      await tempDirectory.rename(target.path);
      await _ensureKeywordsFile(target);
      await _logger.log('Wakeword model ready at ${target.path}');
      return target;
    } on WakeWordException {
      rethrow;
    } catch (error) {
      throw WakeWordException('Could not prepare the wakeword model: $error');
    } finally {
      await _deleteIfExists(archiveFile);
      await _deleteIfExists(tempDirectory, recursive: true);
    }
  }

  /// Closes the HTTP client when this manager created it.
  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Future<bool> _hasModelFiles(Directory directory) async {
    if (!await directory.exists()) return false;
    for (final name in requiredFileNames) {
      final file = File('${directory.path}${Platform.pathSeparator}$name');
      if (!await file.exists()) return false;
      if (await file.length() == 0) return false;
    }
    return true;
  }

  Future<void> _download(
    File destination, {
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(downloadUrl));
    final response = await _httpClient
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      throw WakeWordException(
        'Wakeword model download failed (HTTP ${response.statusCode}).',
      );
    }

    final totalBytes = response.contentLength;
    final sink = destination.openWrite();
    var receivedBytes = 0;
    var lastReportedPercent = -1;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes != null && totalBytes > 0 && onProgress != null) {
          final percent = receivedBytes * 100 ~/ totalBytes;
          if (percent != lastReportedPercent) {
            lastReportedPercent = percent;
            onProgress(receivedBytes / totalBytes);
          }
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (totalBytes != null && totalBytes > 0 && receivedBytes != totalBytes) {
      throw const WakeWordException(
        'Wakeword model download was interrupted. Please try again.',
      );
    }
  }

  Future<void> _extract(File archiveFile, Directory destination) async {
    final archiveBytes = await archiveFile.readAsBytes();
    final tarBytes = BZip2Decoder().decodeBytes(archiveBytes);
    final tarArchive = TarDecoder().decodeBytes(tarBytes);

    final wantedNames = requiredFileNames.toSet();
    var extractedCount = 0;
    for (final entry in tarArchive) {
      if (!entry.isFile) continue;
      // Only accept the expected files by their base name. This also keeps a
      // crafted archive from escaping the destination directory.
      final name = entry.name.split('/').last;
      if (!wantedNames.contains(name)) continue;
      final content = entry.content;
      if (content.isEmpty) continue;
      await File(
        '${destination.path}${Platform.pathSeparator}$name',
      ).writeAsBytes(content, flush: true);
      extractedCount++;
    }

    if (extractedCount != wantedNames.length) {
      throw const WakeWordException(
        'The wakeword model archive is incomplete.',
      );
    }
  }

  Future<void> _ensureKeywordsFile(Directory directory) async {
    final file = File(
      '${directory.path}${Platform.pathSeparator}$keywordsFileName',
    );
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.contains(wakeWordKeywordLine)) return;
      final separator = content.isEmpty || content.endsWith('\n') ? '' : '\n';
      await file.writeAsString(
        '$content$separator$wakeWordKeywordLine\n',
        flush: true,
      );
      return;
    }
    await file.writeAsString('$wakeWordKeywordLine\n', flush: true);
  }

  Future<void> _deleteIfExists(
    FileSystemEntity entity, {
    bool recursive = false,
  }) async {
    try {
      if (await entity.exists()) {
        await entity.delete(recursive: recursive);
      }
    } catch (error) {
      await _logger.debug('Could not remove ${entity.path}: $error');
    }
  }
}
