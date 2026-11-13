import 'dart:async';

import 'package:flutter/foundation.dart' show compute;

import '../core/logger.dart';
import '../instrument/dart_vxi11.dart';
import '../instrument/scpi_parser.dart';
import '../spectrum/spectrum_controller.dart';
import 'reference_waveform_controller.dart';
import 'waveform_acquisition.dart';
import 'waveform_acquisition_controller.dart';
import 'waveform_models.dart';
import 'waveform_processing.dart';

/// Drives the screen-dump and waveform acquisition flows.
///
/// The orchestrator owns the sequencing (panel switching, live-screen
/// handover, SCPI transfer, result application); the home page supplies the
/// instrument access, the state setters, and the controllers that hold the
/// resulting data.
class AcquisitionOrchestrator {
  AcquisitionOrchestrator({
    required this.acquisition,
    required this.spectrum,
    required this.reference,
    required this.getInstrument,
    required this.closeInstrument,
    required this.host,
    required this.channelCount,
    required this.isChannelEnabled,
    required this.isTimelapseRunning,
    required this.isDataLoggerPanelActive,
    required this.isMounted,
    required this.resetPanels,
    required this.stopDataLogger,
    required this.stopBode,
    required this.stopAutoCapture,
    required this.stopLive,
    required this.refreshLive,
    required this.setOnline,
    required this.setDeviceParams,
    required this.setWaveformAcquired,
    required this.setTriggerSourceChannel,
    required this.isSpectrumView,
    required this.hasEnoughSpectrumData,
    required this.resetViewMode,
    required this.resetZoom,
    required this.recordWaveformHistory,
    required this.recomputeReferenceAnalysis,
    required this.showError,
    required this.notify,
  });

  final WaveformAcquisitionController acquisition;
  final SpectrumController spectrum;
  final ReferenceWaveformController reference;

  final Future<Vxi11Instrument?> Function() getInstrument;
  final void Function() closeInstrument;
  final String Function() host;
  final int Function() channelCount;
  final bool Function(int channel) isChannelEnabled;
  final bool Function() isTimelapseRunning;
  final bool Function() isDataLoggerPanelActive;
  final bool Function() isMounted;

  final void Function() resetPanels;
  final void Function() stopDataLogger;
  final void Function() stopBode;
  final void Function() stopAutoCapture;
  final void Function() stopLive;
  final Future<void> Function() refreshLive;

  final void Function(bool online) setOnline;
  final void Function(DeviceParams? params) setDeviceParams;
  final void Function(bool acquired) setWaveformAcquired;
  final void Function(String? channel) setTriggerSourceChannel;
  final bool Function() isSpectrumView;
  final bool Function() hasEnoughSpectrumData;
  final void Function() resetViewMode;
  final void Function() resetZoom;

  final void Function() recordWaveformHistory;
  final void Function() recomputeReferenceAnalysis;
  final void Function(String message) showError;
  final void Function() notify;

  Future<void> acquireScreenDump({bool keepPanels = false}) async {
    if (acquisition.isAcquiring ||
        acquisition.isAcquiringWaveform ||
        isTimelapseRunning()) {
      return;
    }

    // Stop the Data Logger immediately when switching away from it
    if (!keepPanels && isDataLoggerPanelActive()) {
      stopDataLogger();
      stopBode();
    }

    acquisition.isAcquiring = true;
    if (!keepPanels) resetPanels();
    notify();

    try {
      final instr = await getInstrument();
      if (instr == null) return;

      setOnline(true);
      notify();
      final data = await instr.getScreenDump();

      final processedData = await compute(processScreenDump, data);

      if (isMounted()) {
        acquisition.screenDump = processedData;
        acquisition.screenDumpCapturedAt = DateTime.now();
        acquisition.ch1 = null;
        acquisition.ch2 = null;
        acquisition.ch3 = null;
        acquisition.ch4 = null;
        acquisition.measurementsCh1 = null;
        acquisition.measurementsCh2 = null;
        acquisition.measurementsCh3 = null;
        acquisition.measurementsCh4 = null;
        acquisition.historyCh1.clear();
        acquisition.historyCh2.clear();
        acquisition.historyCh3.clear();
        acquisition.historyCh4.clear();
        reference.clearAnalysis();
        setDeviceParams(null);
        setOnline(true);
        setWaveformAcquired(false);
        notify();
        // Opening the Control Panel is the moment the Live toggle matters;
        // probe right away instead of waiting for the next ping tick, and
        // restore the live screen when it was active before.
        if (!keepPanels) {
          unawaited(refreshLive());
        }
      }
    } catch (e) {
      if (isMounted()) {
        AppLogger().error('Acquire display error: $e');
        // If it's a connection error, close the instrument so we retry next time
        closeInstrument();
      }
      setOnline(false);
      notify();
      stopLive();
    } finally {
      if (isMounted()) {
        acquisition.isAcquiring = false;
        notify();
      }
    }
  }

  /// Acquires a new waveform and updates the analysis view.
  ///
  /// [keepPanels] keeps the currently open panel (for example the main AI
  /// chat) instead of switching to the waveform view. Background refreshes
  /// triggered by an AI scope command use it so the acquisition never
  /// navigates the user away from the conversation.
  Future<void> acquireWaveform({bool keepPanels = false}) async {
    if (isTimelapseRunning()) return;
    // Stop the Data Logger immediately when switching away from it
    stopDataLogger();
    stopBode();
    stopAutoCapture();
    stopLive();

    acquisition.isAcquiringWaveform = true;
    if (!keepPanels) resetPanels();
    // Clear the previous capture immediately: while the new acquisition is
    // in flight the chart and measurement cards must not keep showing the
    // old trace. The device parameters stay so the grid and axes remain.
    acquisition.ch1 = null;
    acquisition.ch2 = null;
    acquisition.ch3 = null;
    acquisition.ch4 = null;
    acquisition.measurementsCh1 = null;
    acquisition.measurementsCh2 = null;
    acquisition.measurementsCh3 = null;
    acquisition.measurementsCh4 = null;
    acquisition.lastRawData = null;
    spectrum.clearResultSilently();
    reference.clearAnalysis();
    notify();

    try {
      final instr = await getInstrument();
      final bool fourChannel = channelCount() >= 4;
      final raw = await WaveformAcquisition(host()).acquire(
        ch1: isChannelEnabled(1),
        ch2: isChannelEnabled(2),
        ch3: fourChannel && isChannelEnabled(3),
        ch4: fourChannel && isChannelEnabled(4),
        instr: instr,
      );

      String? triggerSourceChannel;
      var triggerSourceQueried = false;
      try {
        final triggerResponse = await instr?.queryString('TRSE?');
        if (triggerResponse != null) {
          triggerSourceChannel = ScpiParser.parseTriggerSourceChannel(
            triggerResponse,
          );
          triggerSourceQueried = true;
        }
      } catch (e) {
        AppLogger().warning('Failed to query trigger source: $e');
      }

      // Run conversion on the main thread instead of via compute() because
      // Dart's isolate serialization does not support record types
      // ((double, double) pairs) — they get silently truncated to ~726 points
      // instead of the full 1201 points sent by the scope (WFSU NP=1201).
      final result = convertRawData(raw);
      // Measure the raw samples before the display decimation so rise/fall
      // times and overshoot keep the full acquisition resolution.
      final measurements = acquisition.measureRawChannels(raw);

      acquisition.ch1 = result.$1;
      acquisition.ch2 = result.$2;
      acquisition.ch3 = result.$3;
      acquisition.ch4 = result.$4;
      acquisition.measurementsCh1 = measurements.$1;
      acquisition.measurementsCh2 = measurements.$2;
      acquisition.measurementsCh3 = measurements.$3;
      acquisition.measurementsCh4 = measurements.$4;
      acquisition.recordMeasurementHistory(measurements);
      setDeviceParams(result.$5);
      if (triggerSourceQueried) {
        setTriggerSourceChannel(triggerSourceChannel);
      }
      acquisition.screenDump = null;
      acquisition.screenDumpCapturedAt = null;
      setOnline(true);
      setWaveformAcquired(true);
      acquisition.lastRawData = raw;
      // Invalidate an in-flight spectrum computation from the previous
      // acquisition so it cannot publish stale FFT values.
      spectrum.invalidateSilently();
      if (isSpectrumView() && !hasEnoughSpectrumData()) {
        resetViewMode();
      }
      acquisition.acquisitionGeneration++;
      // Reset zoom state on every new acquisition so the user sees the full
      // waveform (14 divisions) instead of a zoomed-in view from a previous
      // interaction that showed only ~4 waves.
      resetZoom();
      notify();

      acquisition.logWaveformMeasurements();
      recomputeReferenceAnalysis();
      recordWaveformHistory();
      if (isSpectrumView()) {
        unawaited(spectrum.recompute());
      }
    } catch (e) {
      AppLogger().error('Acquire waveform error: $e');
      final reason = e is AcquisitionException ? e.reason : e.toString();
      AppLogger().error('Popup: Waveform error: $reason');
      showError('Waveform error: $reason');
    } finally {
      if (isMounted()) {
        acquisition.isAcquiringWaveform = false;
        notify();
      }
    }
  }
}
