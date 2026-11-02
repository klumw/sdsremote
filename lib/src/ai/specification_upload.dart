/// File selection and local text extraction for DUT specifications.
///
/// The Waveform Agent requests a specification through its
/// `request_specification_upload` tool. The chat panel shows the upload
/// control only while that tool is waiting, and this library turns the
/// selected document into plain text so the model never receives a binary
/// file.
library;

import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:pdfrx/pdfrx.dart';

import 'agents/spec_analyst_agent.dart';

/// File extensions offered in the specification file dialog.
const List<String> specificationFileExtensions = <String>[
  'pdf',
  'txt',
  'md',
  'csv',
  'tsv',
  'json',
  'log',
];

/// Extensions read as plain UTF-8 text without the PDF extractor.
const Set<String> _plainTextExtensions = <String>{
  'txt',
  'md',
  'csv',
  'tsv',
  'json',
  'log',
};

/// Large-file guard for plain-text specifications.
const int maxSpecificationFileBytes = 20 * 1024 * 1024;

/// Chooses a specification file with the platform file dialog.
///
/// Returns null when the user closes the dialog without a selection.
Future<XFile?> pickSpecificationFile() {
  return openFile(
    acceptedTypeGroups: const <XTypeGroup>[
      XTypeGroup(
        label: 'Specification documents',
        extensions: specificationFileExtensions,
      ),
    ],
  );
}

/// Reads [file] and returns the extracted text.
///
/// PDF files are converted with the bundled pdfium engine. Plain-text files
/// are decoded as UTF-8. The extracted text must not exceed
/// [SpecAnalystAgent.maxSpecTextCharacters] because the SpecAnalyst agent
/// rejects larger excerpts.
Future<UploadedSpecification> extractSpecificationText(XFile file) async {
  final fileName = file.name.trim().isEmpty ? file.path : file.name;
  final extension = _extensionOf(fileName);
  if (extension == 'pdf') {
    return _extractPdfText(file, fileName);
  }
  if (_plainTextExtensions.contains(extension)) {
    return _extractPlainText(file, fileName);
  }
  throw SpecificationUploadException(
    'Unsupported file type "$extension". Choose a PDF or a plain-text file '
    '(TXT, MD, CSV, TSV, JSON, LOG).',
  );
}

/// One specification file whose text was extracted locally.
class UploadedSpecification {
  const UploadedSpecification({
    required this.fileName,
    required this.text,
    this.pageCount,
  });

  /// File name shown to the user and used as the citation source.
  final String fileName;

  /// Extracted specification text.
  final String text;

  /// Number of pages when the file was a PDF.
  final int? pageCount;

  int get characterCount => text.length;
}

/// Reports a user-correctable problem with a selected specification file.
class SpecificationUploadException implements Exception {
  const SpecificationUploadException(this.message);

  /// Message shown in the upload control and returned to the agent.
  final String message;

  @override
  String toString() => message;
}

/// Opens the specification file dialog.
typedef SpecificationFilePicker = Future<XFile?> Function();

/// Extracts the text of a selected specification file.
typedef SpecificationTextExtractor =
    Future<UploadedSpecification> Function(XFile file);

Future<UploadedSpecification> _extractPlainText(
  XFile file,
  String fileName,
) async {
  try {
    final size = await file.length();
    if (size > maxSpecificationFileBytes) {
      throw SpecificationUploadException(
        'The file is ${_formatBytes(size)}; the maximum is '
        '${_formatBytes(maxSpecificationFileBytes)}. Reduce the document to '
        'the electrical characteristics section.',
      );
    }
    final bytes = await file.readAsBytes();
    final text = _validateText(
      utf8.decode(bytes, allowMalformed: true),
      fileName: fileName,
    );
    return UploadedSpecification(fileName: fileName, text: text);
  } on SpecificationUploadException {
    rethrow;
  } on Object catch (error) {
    throw SpecificationUploadException(
      'The file "$fileName" could not be read ($error).',
    );
  }
}

Future<UploadedSpecification> _extractPdfText(
  XFile file,
  String fileName,
) async {
  PdfDocument? document;
  try {
    await pdfrxFlutterInitialize();
    document = await PdfDocument.openFile(file.path);
    final buffer = StringBuffer();
    for (final page in document.pages) {
      final pageText = await page.loadText();
      final text = pageText?.fullText.trim() ?? '';
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(text);
    }
    final pageCount = document.pages.length;
    final text = _validateText(
      buffer.toString(),
      fileName: fileName,
      pageCount: pageCount,
    );
    return UploadedSpecification(
      fileName: fileName,
      text: text,
      pageCount: pageCount,
    );
  } on SpecificationUploadException {
    rethrow;
  } on Object catch (error) {
    throw SpecificationUploadException(
      'The PDF "$fileName" could not be read ($error). If it is '
      'password-protected, remove the protection first.',
    );
  } finally {
    await document?.dispose();
  }
}

String _validateText(String raw, {required String fileName, int? pageCount}) {
  final text = raw.replaceFirst('﻿', '').replaceAll('\r\n', '\n').trim();
  if (text.isEmpty) {
    throw SpecificationUploadException(
      pageCount == null
          ? 'The file "$fileName" does not contain any text.'
          : 'No text could be extracted from "$fileName". The document may '
                'be a scanned image; upload a searchable PDF or paste the '
                'electrical characteristics table.',
    );
  }
  if (text.length > SpecAnalystAgent.maxSpecTextCharacters) {
    final pages = pageCount == null ? '' : ' across $pageCount pages';
    throw SpecificationUploadException(
      'The extracted text is ${text.length} characters$pages; the maximum is '
      '${SpecAnalystAgent.maxSpecTextCharacters}. Upload only the electrical '
      'characteristics section of the document.',
    );
  }
  return text;
}

String _extensionOf(String fileName) {
  final name = fileName.toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1);
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} kB';
  }
  return '$bytes bytes';
}
