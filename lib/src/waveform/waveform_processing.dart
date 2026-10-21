import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'waveform_converter.dart';
import 'waveform_models.dart';

/// Processes a raw screen dump (BMP) by decoding it, applying slight contrast
/// reduction, and re-encoding as PNG.
///
/// This function is designed to be used with [Isolate.spawn] / [compute].
Uint8List processScreenDump(Uint8List data) {
  final img.Image? decoded = img.decodeImage(data);
  if (decoded == null) return data;
  // Apply slight contrast reduction for better visibility
  img.contrast(decoded, contrast: 90);
  return Uint8List.fromList(img.encodePng(decoded));
}

/// Converts raw waveform data for a single channel into a [WaveformData].
///
/// Returns `null` if any required parameter is missing or [rawData] is empty.
WaveformData? convertChannel({
  required Uint8List? rawData,
  required double? vdiv,
  required double? voffset,
  required double trdl,
  required double timebase,
  required double sampleRate,
  required int triggerPosition,
}) {
  if (rawData == null || vdiv == null || voffset == null || rawData.isEmpty) {
    return null;
  }
  final voltages = WaveformConverter.convertVoltages(rawData, vdiv, voffset);
  final times = WaveformConverter.computeTimeAxis(
    voltages.length,
    trdl,
    timebase,
    sampleRate,
    triggerPosition: triggerPosition,
  );
  var combined = WaveformConverter.combine(times, voltages);
  // The first samples of the acquisition memory can contain a transient
  // artifact (visible as a vertical spike/offset at the left plot edge).
  // Drop them while keeping the time axis aligned.
  const int leadingSamplesToSkip = 8;
  if (combined.length > leadingSamplesToSkip * 4) {
    combined = combined.sublist(leadingSamplesToSkip);
  }
  // Downsample to 50% by taking every 2nd point
  final downsampled = <(double, double)>[
    for (var i = 0; i < combined.length; i += 2) combined[i],
  ];
  return WaveformData(points: downsampled);
}

/// Converts raw waveform data for all channels into [WaveformData] objects
/// and a [DeviceParams] snapshot.
///
/// Channels that were not acquired come back as `null`.
(WaveformData?, WaveformData?, WaveformData?, WaveformData?, DeviceParams)
convertRawData(WaveformRawData raw) {
  final ch1 = convertChannel(
    rawData: raw.ch1Raw,
    vdiv: raw.vdivCh1,
    voffset: raw.voffsetCh1,
    trdl: raw.trdl,
    timebase: raw.timebase,
    sampleRate: raw.sampleRate,
    triggerPosition: raw.triggerPosition,
  );
  final ch2 = convertChannel(
    rawData: raw.ch2Raw,
    vdiv: raw.vdivCh2,
    voffset: raw.voffsetCh2,
    trdl: raw.trdl,
    timebase: raw.timebase,
    sampleRate: raw.sampleRate,
    triggerPosition: raw.triggerPosition,
  );
  final ch3 = convertChannel(
    rawData: raw.ch3Raw,
    vdiv: raw.vdivCh3,
    voffset: raw.voffsetCh3,
    trdl: raw.trdl,
    timebase: raw.timebase,
    sampleRate: raw.sampleRate,
    triggerPosition: raw.triggerPosition,
  );
  final ch4 = convertChannel(
    rawData: raw.ch4Raw,
    vdiv: raw.vdivCh4,
    voffset: raw.voffsetCh4,
    trdl: raw.trdl,
    timebase: raw.timebase,
    sampleRate: raw.sampleRate,
    triggerPosition: raw.triggerPosition,
  );

  final params = DeviceParams(
    vdivCh1: raw.vdivCh1,
    voffsetCh1: raw.voffsetCh1,
    vdivCh2: raw.vdivCh2,
    voffsetCh2: raw.voffsetCh2,
    vdivCh3: raw.vdivCh3,
    voffsetCh3: raw.voffsetCh3,
    vdivCh4: raw.vdivCh4,
    voffsetCh4: raw.voffsetCh4,
    timebase: raw.timebase,
    trdl: raw.trdl,
    sampleRate: raw.sampleRate,
  );

  return (ch1, ch2, ch3, ch4, params);
}
