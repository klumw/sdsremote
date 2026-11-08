/// Host-managed level measurement at an explicit list of frequencies.
///
/// The service configures the signal generator, lets the scope implementation
/// adjust its timebase and vertical scale, records one level per frequency and
/// restores the previous device state. It is deterministic and independent of
/// the LLM; the AudioAgent only interprets the returned points.
library;

import 'dart:async';

import '../ai/cancellation.dart';
import '../ai/tools/audio/audio_analysis_context.dart';
import '../core/logger.dart';
import '../signal_generator/models.dart';
import '../signal_generator/signal_generator_service.dart';

/// Narrow scope interface used by the frequency series.
abstract class FrequencySeriesScope {
  /// Prepares the scope for the series and must restore every change later.
  Future<void> prepare({required int channel, required double amplitudeVpp});

  /// Runs Auto Setup (ASET) once after the generator is configured and on.
  ///
  /// The series calls this before the first measurement point so the scope
  /// timebase, vertical scale and trigger match the actual generator signal.
  Future<void> autoSet();

  /// Measures the level at [frequencyHz].
  ///
  /// Returns `null` when the scope could not produce a valid value.
  Future<double?> read({
    required int channel,
    required double frequencyHz,
    required String quantity,
  });

  /// Restores the state changed by [prepare] and [read].
  Future<void> restore();

  /// Reads several named measurements at [frequencyHz] after one preparation.
  ///
  /// The default implementation calls [read] once per quantity so existing
  /// adapters keep working. Adapters that can query several values after one
  /// timebase and vertical-scale adjustment override it.
  Future<Map<String, double?>> readMany({
    required int channel,
    required double frequencyHz,
    required List<String> quantities,
  }) async {
    final values = <String, double?>{};
    for (final quantity in quantities) {
      values[quantity] = await read(
        channel: channel,
        frequencyHz: frequencyHz,
        quantity: quantity,
      );
    }
    return values;
  }
}

/// Configuration of one frequency series.
class FrequencySeriesConfig {
  const FrequencySeriesConfig({
    required this.frequenciesHz,
    required this.channel,
    required this.quantity,
    this.amplitudeVpp,
    this.waveform = Jds6600Waveform.sine,
    this.offsetV = 0,
    this.useCurrentGeneratorSettings = false,
    this.generatorChannel = 1,
    this.settling = const Duration(milliseconds: 1000),
    this.turnOffOutputsAfterRun = true,
  });

  /// Frequencies in measurement order.
  final List<double> frequenciesHz;

  /// Scope channel number, 1-4.
  final int channel;

  /// `vpp` or `vrms`.
  final String quantity;

  /// Generator amplitude in Vpp when [useCurrentGeneratorSettings] is false.
  final double? amplitudeVpp;

  /// Generator waveform applied when the current settings are not kept.
  final Jds6600Waveform waveform;

  /// Generator offset applied when the current settings are not kept.
  final double offsetV;

  /// Whether generator waveform, amplitude and offset stay unchanged.
  ///
  /// Only the frequency is stepped in that case. The current amplitude is
  /// read before the series and used for the scope scaling.
  final bool useCurrentGeneratorSettings;

  /// Generator channel, 1 or 2.
  final int generatorChannel;
  final Duration settling;
  final bool turnOffOutputsAfterRun;
}

/// One measured point of a frequency series.
class FrequencySeriesPoint {
  const FrequencySeriesPoint({
    required this.frequencyHz,
    this.value,
    this.valid = true,
    this.note,
  });

  final double frequencyHz;
  final double? value;
  final bool valid;
  final String? note;
}

/// Result of one frequency series.
class FrequencySeriesResult {
  const FrequencySeriesResult({
    required this.points,
    required this.quantity,
    required this.configSummary,
  });

  final List<FrequencySeriesPoint> points;
  final String quantity;
  final String configSummary;
}

/// Configuration of a frequency series that reads several scope quantities.
///
/// Unlike [FrequencySeriesConfig], this variant does not force a sine waveform
/// or a fixed amplitude and offset. A `null` generator setting is preserved,
/// so the series can step the frequency of an existing digital signal.
class FrequencySeriesQuantitiesConfig {
  const FrequencySeriesQuantitiesConfig({
    required this.frequenciesHz,
    required this.channel,
    required this.quantities,
    this.generatorChannel = 1,
    this.generatorWaveform,
    this.amplitudeVpp,
    this.offsetV,
    this.settling = const Duration(milliseconds: 1000),
    this.enableOutput = true,
    this.turnOffOutputsAfterRun = true,
  });

  /// Frequencies in measurement order.
  final List<double> frequenciesHz;

  /// Scope channel number, 1-4.
  final int channel;

  /// Scope measurement names passed to [FrequencySeriesScope.readMany].
  final List<String> quantities;

  /// Generator channel, 1 or 2.
  final int generatorChannel;

  /// Waveform to apply, or `null` to keep the current waveform.
  final Jds6600Waveform? generatorWaveform;

  /// Amplitude to apply, or `null` to keep the current amplitude.
  final double? amplitudeVpp;

  /// Offset to apply, or `null` to keep the current offset.
  final double? offsetV;

  final Duration settling;

  /// Whether to switch the generator output on before the series.
  final bool enableOutput;

  /// Whether to switch both generator outputs off afterwards.
  final bool turnOffOutputsAfterRun;
}

/// One point of a multi-quantity frequency series.
class FrequencySeriesQuantitiesPoint {
  const FrequencySeriesQuantitiesPoint({
    required this.frequencyHz,
    required this.values,
    this.valid = true,
    this.note,
  });

  final double frequencyHz;

  /// Measured values by quantity name. A quantity that could not be read is
  /// `null`; the other quantities of the same point remain usable.
  final Map<String, double?> values;

  final bool valid;
  final String? note;
}

/// Result of a multi-quantity frequency series.
class FrequencySeriesQuantitiesResult {
  const FrequencySeriesQuantitiesResult({
    required this.points,
    required this.quantities,
    required this.configSummary,
  });

  final List<FrequencySeriesQuantitiesPoint> points;
  final List<String> quantities;
  final String configSummary;
}

/// Runs a frequency series and returns the measured levels.
class FrequencySeriesService {
  FrequencySeriesService({
    required this.signalGenerator,
    required this.scope,
    this.skipSettling = false,
  });

  final SignalGeneratorService signalGenerator;
  final FrequencySeriesScope scope;

  /// Test seam: skip the per-point settle delays.
  final bool skipSettling;

  /// Runs [config] and restores the generator and scope state in every case.
  Future<FrequencySeriesResult> run(
    FrequencySeriesConfig config, {
    CancellationToken? cancelToken,
  }) async {
    _validate(config);
    final generator = signalGenerator;
    if (!generator.isConnected) {
      throw const AudioFrequencySeriesException(
        'The signal generator is not connected.',
        code: 'SERIES_GENERATOR_OFFLINE',
        hint: 'Check the USB connection and the selected serial port.',
      );
    }

    final generatorChannel = config.generatorChannel;
    final before = generator.channel(generatorChannel);
    final outputsBefore = generator.outputs;
    final effectiveAmplitude = config.useCurrentGeneratorSettings
        ? before.amplitudeVpp
        : config.amplitudeVpp!;
    if (!effectiveAmplitude.isFinite || effectiveAmplitude <= 0) {
      throw const AudioFrequencySeriesException(
        'The generator amplitude is not usable. Set a positive amplitude or '
        'choose the configure mode.',
        code: 'SERIES_INVALID_AMPLITUDE',
      );
    }
    final points = <FrequencySeriesPoint>[];

    try {
      if (!config.useCurrentGeneratorSettings) {
        await generator.setWaveform(generatorChannel, config.waveform);
        await generator.setAmplitude(generatorChannel, config.amplitudeVpp!);
        await generator.setOffset(generatorChannel, config.offsetV);
      }
      await generator.setFrequency(
        generatorChannel,
        config.frequenciesHz.first,
      );
      await generator.setOutput(generatorChannel, true);
      await _settle(config.settling);
      _throwIfCancelled(cancelToken);

      await scope.prepare(
        channel: config.channel,
        amplitudeVpp: effectiveAmplitude,
      );
      _throwIfCancelled(cancelToken);

      // The generator is configured and running at the first frequency before
      // this call, so ASET scales and triggers the scope for the real signal.
      await scope.autoSet();
      _throwIfCancelled(cancelToken);

      for (var index = 0; index < config.frequenciesHz.length; index++) {
        _throwIfCancelled(cancelToken);
        final frequency = config.frequenciesHz[index];
        if (index > 0) {
          await generator.setFrequency(generatorChannel, frequency);
          await _settle(config.settling);
        }
        double? value;
        String? note;
        try {
          value = await scope.read(
            channel: config.channel,
            frequencyHz: frequency,
            quantity: config.quantity,
          );
        } on Object catch (error) {
          note = 'Reading failed: $error';
        }
        final valid = value != null && value.isFinite && value > 0;
        points.add(
          FrequencySeriesPoint(
            frequencyHz: frequency,
            value: valid ? value : null,
            valid: valid,
            note: valid ? note : (note ?? 'No valid reading'),
          ),
        );
      }

      return FrequencySeriesResult(
        points: List<FrequencySeriesPoint>.unmodifiable(points),
        quantity: config.quantity,
        configSummary:
            '${points.length} points, ${config.amplitudeVpp} Vpp sine, '
            'scope channel ${config.channel}, generator channel '
            '$generatorChannel',
      );
    } on AudioFrequencySeriesException {
      rethrow;
    } on Object catch (error) {
      throw AudioFrequencySeriesException(
        'The frequency-series measurement failed ($error).',
        code: 'SERIES_FAILED',
      );
    } finally {
      await _restoreGenerator(
        generatorChannel: generatorChannel,
        before: before,
        outputsBefore: outputsBefore,
        turnOffOutputs: config.turnOffOutputsAfterRun,
      );
      try {
        await scope.restore();
      } on Object catch (error) {
        AppLogger(
          agentName: 'FrequencySeries',
          toolName: 'restore',
        ).error('Scope restore failed: $error');
      }
    }
  }

  /// Runs a multi-quantity series and restores the device state in every case.
  ///
  /// Only the frequency is changed when the optional waveform, amplitude and
  /// offset are omitted. This keeps an existing digital signal intact while
  /// the series steps through the requested frequencies.
  Future<FrequencySeriesQuantitiesResult> runQuantities(
    FrequencySeriesQuantitiesConfig config, {
    CancellationToken? cancelToken,
  }) async {
    _validateQuantities(config);
    final generator = signalGenerator;
    if (!generator.isConnected) {
      throw const AudioFrequencySeriesException(
        'The signal generator is not connected.',
        code: 'SERIES_GENERATOR_OFFLINE',
        hint: 'Check the USB connection and the selected serial port.',
      );
    }

    final generatorChannel = config.generatorChannel;
    final before = generator.channel(generatorChannel);
    final outputsBefore = generator.outputs;
    final effectiveAmplitude = config.amplitudeVpp ?? before.amplitudeVpp;
    if (!effectiveAmplitude.isFinite || effectiveAmplitude <= 0) {
      throw const AudioFrequencySeriesException(
        'The current generator amplitude is not usable. Set a positive '
        'amplitude or choose the configure mode.',
        code: 'SERIES_INVALID_AMPLITUDE',
      );
    }
    final points = <FrequencySeriesQuantitiesPoint>[];

    try {
      if (config.generatorWaveform != null) {
        await generator.setWaveform(
          generatorChannel,
          config.generatorWaveform!,
        );
      }
      if (config.amplitudeVpp != null) {
        await generator.setAmplitude(generatorChannel, config.amplitudeVpp!);
      }
      if (config.offsetV != null) {
        await generator.setOffset(generatorChannel, config.offsetV!);
      }
      await generator.setFrequency(
        generatorChannel,
        config.frequenciesHz.first,
      );
      if (config.enableOutput) {
        await generator.setOutput(generatorChannel, true);
      }
      await _settle(config.settling);
      _throwIfCancelled(cancelToken);

      await scope.prepare(
        channel: config.channel,
        amplitudeVpp: effectiveAmplitude,
      );
      _throwIfCancelled(cancelToken);

      // The generator is configured and running at the first frequency before
      // this call, so ASET scales and triggers the scope for the real signal.
      await scope.autoSet();
      _throwIfCancelled(cancelToken);

      for (var index = 0; index < config.frequenciesHz.length; index++) {
        _throwIfCancelled(cancelToken);
        final frequency = config.frequenciesHz[index];
        if (index > 0) {
          await generator.setFrequency(generatorChannel, frequency);
          await _settle(config.settling);
        }
        Map<String, double?> values = const <String, double?>{};
        String? note;
        try {
          values = await scope.readMany(
            channel: config.channel,
            frequencyHz: frequency,
            quantities: config.quantities,
          );
        } on Object catch (error) {
          note = 'Reading failed: $error';
        }
        final valid = values.values.any(
          (value) => value != null && value.isFinite,
        );
        points.add(
          FrequencySeriesQuantitiesPoint(
            frequencyHz: frequency,
            values: values,
            valid: valid,
            note: valid ? note : (note ?? 'No valid reading'),
          ),
        );
      }

      return FrequencySeriesQuantitiesResult(
        points: List<FrequencySeriesQuantitiesPoint>.unmodifiable(points),
        quantities: List<String>.unmodifiable(config.quantities),
        configSummary:
            '${points.length} points, ${config.quantities.join('/')}, '
            'scope channel ${config.channel}, generator channel '
            '$generatorChannel',
      );
    } on AudioFrequencySeriesException {
      rethrow;
    } on Object catch (error) {
      throw AudioFrequencySeriesException(
        'The frequency-series measurement failed ($error).',
        code: 'SERIES_FAILED',
      );
    } finally {
      await _restoreGenerator(
        generatorChannel: generatorChannel,
        before: before,
        outputsBefore: outputsBefore,
        turnOffOutputs: config.turnOffOutputsAfterRun,
      );
      try {
        await scope.restore();
      } on Object catch (error) {
        AppLogger(
          agentName: 'FrequencySeries',
          toolName: 'restore',
        ).error('Scope restore failed: $error');
      }
    }
  }

  Future<void> _restoreGenerator({
    required int generatorChannel,
    required Jds6600ChannelState before,
    required Jds6600OutputState outputsBefore,
    required bool turnOffOutputs,
  }) async {
    final generator = signalGenerator;
    try {
      await generator.setWaveform(generatorChannel, before.waveform);
      await generator.setAmplitude(generatorChannel, before.amplitudeVpp);
      await generator.setOffset(generatorChannel, before.offsetV);
      await generator.setFrequency(generatorChannel, before.frequencyHz);
    } on Object catch (error) {
      AppLogger(
        agentName: 'FrequencySeries',
        toolName: 'restore',
      ).warning('Generator restore failed: $error');
    }
    try {
      if (turnOffOutputs) {
        await generator.setOutput(1, false);
        await generator.setOutput(2, false);
      } else {
        await generator.setOutput(1, outputsBefore.ch1);
        await generator.setOutput(2, outputsBefore.ch2);
      }
    } on Object catch (error) {
      AppLogger(
        agentName: 'FrequencySeries',
        toolName: 'restore',
      ).warning('Generator output restore failed: $error');
    }
  }

  Future<void> _settle(Duration duration) async {
    if (skipSettling || duration <= Duration.zero) return;
    await Future<void>.delayed(duration);
  }

  void _throwIfCancelled(CancellationToken? cancelToken) {
    if (cancelToken?.isCancelled == true) {
      throw const AudioFrequencySeriesException(
        'The frequency-series measurement was cancelled.',
        code: 'SERIES_CANCELLED',
      );
    }
  }

  void _validate(FrequencySeriesConfig config) {
    if (config.frequenciesHz.isEmpty) {
      throw const AudioFrequencySeriesException(
        'At least one frequency is required.',
        code: 'SERIES_NO_FREQUENCIES',
      );
    }
    if (config.frequenciesHz.length > 50) {
      throw const AudioFrequencySeriesException(
        'At most 50 frequencies are supported.',
        code: 'SERIES_TOO_MANY_POINTS',
      );
    }
    for (final frequency in config.frequenciesHz) {
      if (!frequency.isFinite || frequency <= 0) {
        throw const AudioFrequencySeriesException(
          'Every frequency must be a positive finite number.',
          code: 'SERIES_INVALID_FREQUENCY',
        );
      }
    }
    if (config.channel < 1 || config.channel > 4) {
      throw const AudioFrequencySeriesException(
        'The scope channel must be between 1 and 4.',
        code: 'SERIES_INVALID_CHANNEL',
      );
    }
    if (config.quantity != 'vpp' && config.quantity != 'vrms') {
      throw const AudioFrequencySeriesException(
        'The quantity must be vpp or vrms.',
        code: 'SERIES_INVALID_QUANTITY',
      );
    }
    if (!config.useCurrentGeneratorSettings) {
      final amplitude = config.amplitudeVpp;
      if (amplitude == null || !amplitude.isFinite || amplitude <= 0) {
        throw const AudioFrequencySeriesException(
          'The generator amplitude must be a positive number when the '
          'current generator settings are not kept.',
          code: 'SERIES_INVALID_AMPLITUDE',
        );
      }
    }
    if (config.generatorChannel != 1 && config.generatorChannel != 2) {
      throw const AudioFrequencySeriesException(
        'The generator channel must be 1 or 2.',
        code: 'SERIES_INVALID_GENERATOR_CHANNEL',
      );
    }
  }

  void _validateQuantities(FrequencySeriesQuantitiesConfig config) {
    if (config.frequenciesHz.isEmpty) {
      throw const AudioFrequencySeriesException(
        'At least one frequency is required.',
        code: 'SERIES_NO_FREQUENCIES',
      );
    }
    if (config.frequenciesHz.length > 50) {
      throw const AudioFrequencySeriesException(
        'At most 50 frequencies are supported.',
        code: 'SERIES_TOO_MANY_POINTS',
      );
    }
    for (final frequency in config.frequenciesHz) {
      if (!frequency.isFinite || frequency <= 0) {
        throw const AudioFrequencySeriesException(
          'Every frequency must be a positive finite number.',
          code: 'SERIES_INVALID_FREQUENCY',
        );
      }
    }
    if (config.channel < 1 || config.channel > 4) {
      throw const AudioFrequencySeriesException(
        'The scope channel must be between 1 and 4.',
        code: 'SERIES_INVALID_CHANNEL',
      );
    }
    if (config.generatorChannel != 1 && config.generatorChannel != 2) {
      throw const AudioFrequencySeriesException(
        'The generator channel must be 1 or 2.',
        code: 'SERIES_INVALID_GENERATOR_CHANNEL',
      );
    }
    if (config.quantities.isEmpty ||
        config.quantities.any((quantity) => quantity.trim().isEmpty)) {
      throw const AudioFrequencySeriesException(
        'At least one scope quantity is required.',
        code: 'SERIES_INVALID_QUANTITY',
      );
    }
    final amplitude = config.amplitudeVpp;
    if (amplitude != null && (!amplitude.isFinite || amplitude <= 0)) {
      throw const AudioFrequencySeriesException(
        'The generator amplitude must be a positive number.',
        code: 'SERIES_INVALID_AMPLITUDE',
      );
    }
  }
}
