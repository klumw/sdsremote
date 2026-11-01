import 'dart:io';

import 'spectrum_models.dart';

/// Builds the metadata header and column title of a spectrum CSV file.
///
/// All metadata lines start with `#`, the same convention as the waveform and
/// data-logger CSV exports. The header documents the analysis settings once
/// and the per-channel FFT parameters (size, sample rate, resolution and full
/// scale) that the rows cannot carry on their own.
String spectrumCsvHeader({
  required SpectrumResult result,
  required String deviceName,
  DateTime? timestamp,
}) {
  final saved = (timestamp ?? DateTime.now()).toUtc().toIso8601String();
  final settings = result.settings;
  final unit = _unitLabel(settings.unit);
  final buffer = StringBuffer()
    ..writeln('# SDS-Remote Spectrum Data')
    ..writeln('# Format Version: 1')
    ..writeln('# Saved: $saved')
    ..writeln('# Device: $deviceName')
    ..writeln('# Window: ${settings.window.name}')
    ..writeln(
      '# Requested FFT Size: '
      '${settings.fftSize == 0 ? 'auto' : settings.fftSize}',
    )
    ..writeln('# Max FFT Size: ${settings.maxFftSize}')
    ..writeln('# Unit: $unit')
    ..writeln('# DC Removed: ${settings.removeDc}')
    ..writeln('# Leading Samples Skipped: ${settings.leadingSamplesToSkip}')
    ..writeln('# Peak Count: ${settings.peakCount}')
    ..writeln('# Harmonic Count: ${settings.harmonicCount}');
  for (final trace in result.traces) {
    final label = trace.channel.toUpperCase();
    buffer
      ..writeln('# $label FFT Size: ${trace.fftSize}')
      ..writeln('# $label Sample Rate: ${_number(trace.sampleRate)} Sa/s')
      ..writeln(
        '# $label Frequency Resolution: '
        '${_number(trace.resolutionHz)} Hz',
      )
      ..writeln('# $label Full Scale: ${_number(trace.fullScaleVolts)} V');
  }
  buffer
    ..writeln('#')
    ..writeln('Channel,Frequency (Hz),Level ($unit),dBFS,Amplitude (Vpk)');
  return buffer.toString();
}

/// Generates one CSV row per FFT bin, grouped by channel.
///
/// The rows are produced lazily so a one-million-point FFT is streamed to disk
/// instead of being materialised as one large string.
Iterable<String> spectrumCsvRows(SpectrumResult result) sync* {
  for (final trace in result.traces) {
    final channel = trace.channel.toUpperCase();
    final frequencies = trace.frequenciesHz;
    final levels = trace.levelsDb;
    final dbfs = trace.dbfs;
    final amplitudes = trace.amplitudesVpk;
    for (var k = 0; k < frequencies.length; k++) {
      yield '$channel,${_number(frequencies[k])},'
          '${_number(levels[k])},${_number(dbfs[k])},'
          '${_number(amplitudes[k])}';
    }
  }
}

/// Builds the complete spectrum CSV as a string.
///
/// Intended for tests and small spectra; [writeSpectrumCsv] streams large
/// results to disk.
String buildSpectrumCsv({
  required SpectrumResult result,
  required String deviceName,
  DateTime? timestamp,
}) {
  final buffer = StringBuffer(
    spectrumCsvHeader(
      result: result,
      deviceName: deviceName,
      timestamp: timestamp,
    ),
  );
  for (final row in spectrumCsvRows(result)) {
    buffer.writeln(row);
  }
  return buffer.toString();
}

/// Streams the spectrum CSV to [file].
Future<void> writeSpectrumCsv({
  required File file,
  required SpectrumResult result,
  required String deviceName,
  DateTime? timestamp,
}) async {
  final sink = file.openWrite();
  try {
    sink.write(
      spectrumCsvHeader(
        result: result,
        deviceName: deviceName,
        timestamp: timestamp,
      ),
    );
    for (final row in spectrumCsvRows(result)) {
      sink.writeln(row);
    }
  } finally {
    await sink.close();
  }
}

String _unitLabel(SpectrumUnit unit) => switch (unit) {
  SpectrumUnit.dbfs => 'dBFS',
  SpectrumUnit.dbv => 'dBV',
  SpectrumUnit.dbm50 => 'dBm',
};

String _number(double value) => value.isFinite ? value.toString() : '';
