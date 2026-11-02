/// Deterministic fault analysis over the complete raw waveform record.
///
/// The analyzer never decimates the capture. Every finding is derived from the
/// supplied samples, the acquisition context or the caller's specification.
/// Tests without a specification report measurements and clear anomalies but
/// do not claim a confirmed violation.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'waveform_analysis_models.dart';
import 'waveform_fault_models.dart';
import 'waveform_math.dart';

/// Runs the twenty waveform fault tests on a complete raw capture.
class WaveformFaultAnalyzer {
  const WaveformFaultAnalyzer();

  WaveformFaultReport analyze(
    WaveformFaultContext context,
    List<WaveformFaultRequest> requests,
  ) {
    final profile = _SignalProfile.from(context);
    final artifacts = _measurementArtifacts(context, profile);
    final requested = requests.isEmpty
        ? [
            for (final test in WaveformFaultTest.values)
              WaveformFaultRequest(test: test),
          ]
        : requests;
    final findings = <WaveformFaultFinding>[
      for (final request in requested)
        _run(request, context, profile, artifacts),
    ];
    if (!findings.any(
          (finding) => finding.test == WaveformFaultTest.measurementArtifacts,
        ) &&
        (artifacts.status == WaveformFaultStatus.warning ||
            artifacts.status == WaveformFaultStatus.fail)) {
      findings.add(artifacts);
    }
    final limitations = <String>{
      ...profile.limitations,
      ...artifacts.limitations,
    }.toList();
    return WaveformFaultReport(
      channel: context.channel,
      sampleCount: context.trace.length,
      durationSeconds: context.trace.durationSeconds,
      sampleRateHz: context.sampleRateHz,
      fundamentalFrequencyHz: profile.fundamentalHz,
      overallStatus: _overallStatus(findings),
      findings: findings,
      context: _contextMap(context, profile),
      limitations: limitations,
    );
  }

  WaveformFaultFinding _run(
    WaveformFaultRequest request,
    WaveformFaultContext context,
    _SignalProfile profile,
    WaveformFaultFinding measuredArtifacts,
  ) => switch (request.test) {
    WaveformFaultTest.amplitude => _amplitude(request, profile),
    WaveformFaultTest.signalLoss => _signalLoss(request, profile),
    WaveformFaultTest.transients => _transients(request, profile),
    WaveformFaultTest.clipping => _clipping(request, profile),
    WaveformFaultTest.frequencyError => _frequencyError(request, profile),
    WaveformFaultTest.noise => _noise(request, profile),
    WaveformFaultTest.ringing => _ringing(request, profile),
    WaveformFaultTest.dutyCycle => _dutyCycle(request, profile),
    WaveformFaultTest.glitches => _glitches(request, profile),
    WaveformFaultTest.jitter => _jitter(request, profile),
    WaveformFaultTest.dcOffset => _dcOffset(request, profile),
    WaveformFaultTest.distortion => _distortion(request, profile),
    WaveformFaultTest.spuriousFrequencies => _spuriousFrequencies(
      request,
      profile,
    ),
    WaveformFaultTest.edgeTimes => _edgeTimes(request, profile),
    WaveformFaultTest.amplitudeStability => _amplitudeStability(
      request,
      profile,
    ),
    WaveformFaultTest.settling => _settling(request, profile),
    WaveformFaultTest.phaseDelay => _phaseDelay(request, context, profile),
    WaveformFaultTest.crosstalk => _crosstalk(request, context, profile),
    WaveformFaultTest.intermittent => _intermittent(request, profile),
    WaveformFaultTest.measurementArtifacts => measuredArtifacts,
  };

  WaveformFaultFinding _amplitude(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final measured = <String, dynamic>{
      'vppVolts': _finite(profile.vPp),
      'vmaxVolts': _finite(profile.vMax),
      'vminVolts': _finite(profile.vMin),
      'rmsVolts': _finite(profile.vRms),
      'meanVolts': _finite(profile.vMean),
    };
    final expectedVpp = request.number('expectedVppVolts');
    final toleranceVolts = request.number('toleranceVolts');
    final tolerancePercent = request.number('tolerancePercent');
    final minVpp = request.number('minVppVolts');
    final maxVpp = request.number('maxVppVolts');
    final expectedVmax = request.number('expectedVmaxVolts');
    final expectedVmin = request.number('expectedVminVolts');

    if (expectedVpp != null) {
      final tolerance = _tolerance(
        toleranceVolts,
        tolerancePercent,
        expectedVpp,
      );
      if (tolerance == null) {
        return _finding(
          test: WaveformFaultTest.amplitude,
          status: WaveformFaultStatus.inconclusive,
          summary:
              'Vpp is ${_formatVolts(profile.vPp)}, but no tolerance was '
              'supplied for the specified ${_formatVolts(expectedVpp)}.',
          measured: measured,
          expected: {'vppVolts': _finite(expectedVpp)},
          missingInputs: const [
            'toleranceVolts or tolerancePercent for expectedVppVolts',
          ],
        );
      }
      final deviation = profile.vPp - expectedVpp;
      final passed = deviation.abs() <= tolerance;
      return _finding(
        test: WaveformFaultTest.amplitude,
        status: passed ? WaveformFaultStatus.pass : WaveformFaultStatus.fail,
        severity: passed
            ? WaveformFaultSeverity.none
            : _severityForRatio(deviation.abs() / tolerance),
        summary: passed
            ? 'Vpp is ${_formatVolts(profile.vPp)} and within the specified '
                  '${_formatVolts(expectedVpp)} ± ${_formatVolts(tolerance)}.'
            : 'Vpp is ${_formatVolts(profile.vPp)}, '
                  '${_formatSignedVolts(deviation)} from the specified '
                  '${_formatVolts(expectedVpp)} '
                  '(${_formatSignedPercent(_percent(deviation, expectedVpp))}).',
        measured: measured,
        expected: {
          'vppVolts': _finite(expectedVpp),
          'toleranceVolts': _finite(tolerance),
        },
        deviation: {
          'vppVolts': _finite(deviation),
          'percent': _finite(_percent(deviation, expectedVpp)),
        },
      );
    }

    if (minVpp != null || maxVpp != null) {
      final below = minVpp != null && profile.vPp < minVpp;
      final above = maxVpp != null && profile.vPp > maxVpp;
      final violated = below || above;
      return _finding(
        test: WaveformFaultTest.amplitude,
        status: violated ? WaveformFaultStatus.fail : WaveformFaultStatus.pass,
        severity: violated
            ? WaveformFaultSeverity.high
            : WaveformFaultSeverity.none,
        summary: violated
            ? 'Vpp is ${_formatVolts(profile.vPp)} and lies outside the '
                  'allowed range.'
            : 'Vpp is ${_formatVolts(profile.vPp)} and lies inside the '
                  'allowed range.',
        measured: measured,
        expected: {
          if (minVpp != null) 'minVppVolts': _finite(minVpp),
          if (maxVpp != null) 'maxVppVolts': _finite(maxVpp),
        },
      );
    }

    if (expectedVmax != null || expectedVmin != null) {
      final reference = expectedVmax ?? expectedVmin;
      final tolerance =
          toleranceVolts ??
          (tolerancePercent == null || reference == null
              ? null
              : reference.abs() * tolerancePercent / 100);
      if (tolerance == null) {
        return _finding(
          test: WaveformFaultTest.amplitude,
          status: WaveformFaultStatus.inconclusive,
          summary: 'Vmax/Vmin are specified, but no tolerance was supplied.',
          measured: measured,
          expected: {
            if (expectedVmax != null) 'vmaxVolts': _finite(expectedVmax),
            if (expectedVmin != null) 'vminVolts': _finite(expectedVmin),
          },
          missingInputs: const ['toleranceVolts for expectedVmaxVolts/Vmin'],
        );
      }
      final maxDeviation = expectedVmax == null
          ? 0.0
          : (profile.vMax - expectedVmax).abs();
      final minDeviation = expectedVmin == null
          ? 0.0
          : (profile.vMin - expectedVmin).abs();
      final violated = maxDeviation > tolerance || minDeviation > tolerance;
      return _finding(
        test: WaveformFaultTest.amplitude,
        status: violated ? WaveformFaultStatus.fail : WaveformFaultStatus.pass,
        severity: violated
            ? _severityForRatio(
                math.max(maxDeviation, minDeviation) / tolerance,
              )
            : WaveformFaultSeverity.none,
        summary: violated
            ? 'Vmax ${_formatVolts(profile.vMax)} and Vmin '
                  '${_formatVolts(profile.vMin)} exceed the allowed '
                  'limits.'
            : 'Vmax ${_formatVolts(profile.vMax)} and Vmin '
                  '${_formatVolts(profile.vMin)} are within the allowed '
                  'limits.',
        measured: measured,
        expected: {
          if (expectedVmax != null) 'vmaxVolts': _finite(expectedVmax),
          if (expectedVmin != null) 'vminVolts': _finite(expectedVmin),
          'toleranceVolts': _finite(tolerance),
        },
      );
    }

    return _finding(
      test: WaveformFaultTest.amplitude,
      status: WaveformFaultStatus.informational,
      summary:
          'Vpp is ${_formatVolts(profile.vPp)} (Vmax '
          '${_formatVolts(profile.vMax)}, Vmin ${_formatVolts(profile.vMin)}); '
          'no reference value was supplied.',
      measured: measured,
      missingInputs: const [
        'expectedVppVolts (or minVppVolts/maxVppVolts) and '
            'toleranceVolts or tolerancePercent',
      ],
    );
  }

  WaveformFaultFinding _signalLoss(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final minRms = request.number('minRmsVolts');
    final minVpp = request.number('minVppVolts');
    final maxDropoutFraction = request.number('maxDropoutFraction');
    final dropoutFraction = request.number('dropoutFraction') ?? 0.2;
    final windowSeconds = request.number('windowSeconds');
    final windows = _windowStats(profile, _windowCount(profile, windowSeconds));
    final medianVpp = windows.isEmpty
        ? 0.0
        : _median([for (final window in windows) window.vPp]);
    final dropouts = <_WindowStats>[];
    if (medianVpp > 0 && dropoutFraction > 0 && dropoutFraction < 1) {
      final threshold = medianVpp * dropoutFraction;
      for (final window in windows) {
        if (window.vPp < threshold) dropouts.add(window);
      }
    }
    final fraction = windows.isEmpty ? 0.0 : dropouts.length / windows.length;
    final flat = profile.vPp <= math.max(2 * (profile.lsb ?? 0), 1e-12);
    final measured = <String, dynamic>{
      'rmsVolts': _finite(profile.vRms),
      'vppVolts': _finite(profile.vPp),
      'energyVoltsSquared': _finite(
        profile.vRms * profile.vRms * profile.trace.durationSeconds,
      ),
      'signalActivityPercent': _finite(_activityPercent(profile)),
      'windowCount': windows.length,
      'dropoutWindowCount': dropouts.length,
      'dropoutFraction': _finite(fraction),
      'medianWindowVppVolts': _finite(medianVpp),
    };
    final expected = <String, dynamic>{
      if (minRms != null) 'minRmsVolts': _finite(minRms),
      if (minVpp != null) 'minVppVolts': _finite(minVpp),
      if (maxDropoutFraction != null)
        'maxDropoutFraction': _finite(maxDropoutFraction),
    };
    final events = _groupWindowEvents(dropouts);
    final missing = <String>[];
    if (minRms == null && minVpp == null && maxDropoutFraction == null) {
      missing.add(
        'minRmsVolts or minVppVolts and maxDropoutFraction for a pass/fail '
        'verdict',
      );
    }

    if (minRms != null && profile.vRms < minRms) {
      return _finding(
        test: WaveformFaultTest.signalLoss,
        status: WaveformFaultStatus.fail,
        severity: WaveformFaultSeverity.high,
        summary:
            'RMS is ${_formatVolts(profile.vRms)}, below the specified '
            'minimum ${_formatVolts(minRms)}.',
        measured: measured,
        expected: expected,
        events: events,
      );
    }
    if (minVpp != null && profile.vPp < minVpp) {
      return _finding(
        test: WaveformFaultTest.signalLoss,
        status: WaveformFaultStatus.fail,
        severity: WaveformFaultSeverity.high,
        summary:
            'Vpp is ${_formatVolts(profile.vPp)}, below the specified '
            'minimum ${_formatVolts(minVpp)}.',
        measured: measured,
        expected: expected,
        events: events,
      );
    }
    if (maxDropoutFraction != null && fraction > maxDropoutFraction) {
      return _finding(
        test: WaveformFaultTest.signalLoss,
        status: WaveformFaultStatus.fail,
        severity: _severityForRatio(fraction / maxDropoutFraction),
        summary:
            '${dropouts.length} of ${windows.length} windows drop below '
            '${_formatPercent(dropoutFraction * 100)} of the median Vpp; the '
            'allowed fraction is '
            '${_formatPercent(maxDropoutFraction * 100)}.',
        measured: measured,
        expected: expected,
        events: events,
      );
    }
    if (flat) {
      return _finding(
        test: WaveformFaultTest.signalLoss,
        status: WaveformFaultStatus.warning,
        severity: WaveformFaultSeverity.high,
        summary:
            'The record is a flat line (Vpp ${_formatVolts(profile.vPp)}); no '
            'signal activity was detected.',
        measured: measured,
        expected: expected.isEmpty ? null : expected,
        missingInputs: missing,
        events: events,
      );
    }
    if (dropouts.isNotEmpty) {
      return _finding(
        test: WaveformFaultTest.signalLoss,
        status: WaveformFaultStatus.warning,
        severity: _severityForRatio(fraction / 0.05),
        summary:
            '${dropouts.length} of ${windows.length} windows show a signal '
            'dropout (Vpp below '
            '${_formatPercent(dropoutFraction * 100)} of the median).',
        measured: measured,
        expected: expected.isEmpty ? null : expected,
        missingInputs: missing,
        events: events,
      );
    }
    return _finding(
      test: WaveformFaultTest.signalLoss,
      status: expected.isEmpty
          ? WaveformFaultStatus.informational
          : WaveformFaultStatus.pass,
      summary: expected.isEmpty
          ? 'No signal dropout was detected; RMS is '
                '${_formatVolts(profile.vRms)}. No reference level was '
                'supplied.'
          : 'No signal dropout was detected and the specified minimum was '
                'met.',
      measured: measured,
      expected: expected.isEmpty ? null : expected,
      missingInputs: missing,
    );
  }

  WaveformFaultFinding _transients(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final spikes = _detectSpikes(profile, request);
    final threshold =
        request.number('spikeThresholdVolts') ??
        math.max(
          math.max(6 * profile.noiseRms, 0.02 * profile.vPp),
          2 * (profile.lsb ?? 0),
        );
    final maxDuration =
        request.number('maxSpikeDurationSeconds') ??
        (profile.periodSeconds != null
            ? math.max(3 * (profile.dt ?? 0), 0.02 * profile.periodSeconds!)
            : math.max(
                3 * (profile.dt ?? 0),
                0.0005 * profile.trace.durationSeconds,
              ));
    final maxCount = request.integer('maxSpikeCount');
    final measured = <String, dynamic>{
      'spikeCount': spikes.length,
      'spikeThresholdVolts': _finite(threshold),
      'maxSpikeDurationSeconds': _finite(maxDuration),
      'largestSpikeVolts': _finite(
        spikes.isEmpty
            ? null
            : spikes
                  .map((spike) => spike.amplitudeVolts.abs())
                  .reduce(math.max),
      ),
      'maxSlewRateVoltsPerSecond': _finite(_maxSlewRate(profile)),
    };
    final expected = <String, dynamic>{
      if (request.number('spikeThresholdVolts') != null)
        'spikeThresholdVolts': _finite(request.number('spikeThresholdVolts')),
      if (request.number('maxSpikeDurationSeconds') != null)
        'maxSpikeDurationSeconds': _finite(
          request.number('maxSpikeDurationSeconds'),
        ),
      'maxSpikeCount': ?maxCount,
    };
    final events = [
      for (final spike in spikes.take(10))
        {
          'timeSeconds': _finite(spike.startSeconds),
          'peakTimeSeconds': _finite(spike.peakSeconds),
          'amplitudeVolts': _finite(spike.amplitudeVolts),
          'widthSeconds': _finite(spike.widthSeconds),
        },
    ];
    final missing = expected.isEmpty
        ? const [
            'spikeThresholdVolts and maxSpikeDurationSeconds for a pass/fail '
                'verdict',
          ]
        : const <String>[];

    if (spikes.isEmpty) {
      return _finding(
        test: WaveformFaultTest.transients,
        status: expected.isEmpty
            ? WaveformFaultStatus.informational
            : WaveformFaultStatus.pass,
        summary: expected.isEmpty
            ? 'No transients above the internal threshold '
                  '${_formatVolts(threshold)} were detected.'
            : 'No transients above the specified threshold were detected.',
        measured: measured,
        expected: expected.isEmpty ? null : expected,
        missingInputs: missing,
      );
    }
    final exceededCount = maxCount != null && spikes.length > maxCount;
    final suppliedThreshold = request.number('spikeThresholdVolts') != null;
    final status = exceededCount || suppliedThreshold
        ? WaveformFaultStatus.fail
        : WaveformFaultStatus.warning;
    final severity = exceededCount
        ? _severityForRatio(spikes.length / maxCount)
        : suppliedThreshold
        ? WaveformFaultSeverity.high
        : WaveformFaultSeverity.medium;
    return _finding(
      test: WaveformFaultTest.transients,
      status: status,
      severity: severity,
      summary:
          '${spikes.length} transient(s) exceed '
          '${suppliedThreshold ? 'the specified' : 'the internal'} threshold '
          '${_formatVolts(threshold)}; the largest is '
          '${_formatVolts(measured['largestSpikeVolts'] as double?)}.',
      measured: measured,
      expected: expected.isEmpty ? null : expected,
      events: events,
      missingInputs: missing,
    );
  }

  WaveformFaultFinding _clipping(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final lsb = profile.lsb ?? (profile.vPp / 255);
    final tolerance = math.max(1.5 * lsb, 0.005 * profile.vPp);
    final upperThreshold = profile.vMax - tolerance;
    final lowerThreshold = profile.vMin + tolerance;
    final upperRuns = _flatRuns(
      profile.volts,
      profile.times,
      upperThreshold,
      above: true,
    );
    final lowerRuns = _flatRuns(
      profile.volts,
      profile.times,
      lowerThreshold,
      above: false,
    );
    final upperSamples = upperRuns.fold<int>(
      0,
      (sum, run) => sum + run.sampleCount,
    );
    final lowerSamples = lowerRuns.fold<int>(
      0,
      (sum, run) => sum + run.sampleCount,
    );
    final clippedSamples = upperSamples + lowerSamples;
    final clippingRatio = profile.length == 0
        ? 0.0
        : clippedSamples / profile.length;
    final maxPercent = request.number('maxClippingPercent');
    final allowedMax = request.number('allowedMaxVolts');
    final allowedMin = request.number('allowedMinVolts');
    final voltageTolerance = request.number('toleranceVolts') ?? 0;
    final measured = <String, dynamic>{
      'vmaxVolts': _finite(profile.vMax),
      'vminVolts': _finite(profile.vMin),
      'upperClippingRatio': _finite(
        profile.length == 0 ? null : upperSamples / profile.length,
      ),
      'lowerClippingRatio': _finite(
        profile.length == 0 ? null : lowerSamples / profile.length,
      ),
      'clippingRatio': _finite(clippingRatio),
      'upperClippedRegionCount': upperRuns.length,
      'lowerClippedRegionCount': lowerRuns.length,
      'longestClippedRegionSeconds': _finite(
        [
          for (final run in [...upperRuns, ...lowerRuns]) run.widthSeconds,
        ].fold<double>(0, (a, b) => math.max(a, b)),
      ),
      'rectangular': profile.isRectangular,
    };
    final events = [
      for (final run in [
        ...upperRuns,
        ...lowerRuns,
      ].where((run) => run.sampleCount >= 3).take(10))
        {
          'startSeconds': _finite(run.startSeconds),
          'endSeconds': _finite(run.endSeconds),
          'durationSeconds': _finite(run.widthSeconds),
          'levelVolts': _finite(run.levelVolts),
          'polarity': run.high ? 'upper' : 'lower',
        },
    ];
    final expected = <String, dynamic>{
      if (maxPercent != null) 'maxClippingPercent': _finite(maxPercent),
      if (allowedMax != null) 'allowedMaxVolts': _finite(allowedMax),
      if (allowedMin != null) 'allowedMinVolts': _finite(allowedMin),
      if (request.number('toleranceVolts') != null)
        'toleranceVolts': _finite(voltageTolerance),
    };
    if (profile.isRectangular && allowedMax == null && allowedMin == null) {
      return _finding(
        test: WaveformFaultTest.clipping,
        status: WaveformFaultStatus.informational,
        summary:
            'The signal is rectangular; flat high and low levels are expected '
            'and cannot be distinguished from clipping without allowed '
            'voltage limits.',
        measured: measured,
        expected: expected.isEmpty ? null : expected,
        missingInputs: const [
          'allowedMaxVolts and allowedMinVolts for a pass/fail verdict',
        ],
      );
    }
    final limitViolated =
        (allowedMax != null && profile.vMax > allowedMax + voltageTolerance) ||
        (allowedMin != null && profile.vMin < allowedMin - voltageTolerance);
    if (limitViolated) {
      return _finding(
        test: WaveformFaultTest.clipping,
        status: WaveformFaultStatus.fail,
        severity: WaveformFaultSeverity.high,
        summary:
            'Vmax ${_formatVolts(profile.vMax)} / Vmin '
            '${_formatVolts(profile.vMin)} exceed the allowed voltage range.',
        measured: measured,
        expected: expected,
        events: events,
      );
    }
    if (maxPercent != null && clippingRatio * 100 > maxPercent) {
      return _finding(
        test: WaveformFaultTest.clipping,
        status: WaveformFaultStatus.fail,
        severity: _severityForRatio((clippingRatio * 100) / maxPercent),
        summary:
            '${_formatPercent(clippingRatio * 100)} of the samples are clipped, '
            'above the allowed ${_formatPercent(maxPercent)}.',
        measured: measured,
        expected: expected,
        events: events,
      );
    }
    if (maxPercent == null && clippingRatio >= 0.01) {
      return _finding(
        test: WaveformFaultTest.clipping,
        status: WaveformFaultStatus.warning,
        severity: clippingRatio >= 0.1
            ? WaveformFaultSeverity.high
            : WaveformFaultSeverity.medium,
        summary:
            '${_formatPercent(clippingRatio * 100)} of the samples show flat '
            'tops or bottoms, which indicates clipping. No clipping limit was '
            'supplied.',
        measured: measured,
        expected: expected.isEmpty ? null : expected,
        events: events,
        missingInputs: const [
          'maxClippingPercent for a pass/fail clipping verdict',
        ],
      );
    }
    if (expected.isEmpty) {
      if (clippingRatio >= 0.01) {
        return _finding(
          test: WaveformFaultTest.clipping,
          status: WaveformFaultStatus.warning,
          severity: clippingRatio >= 0.1
              ? WaveformFaultSeverity.high
              : WaveformFaultSeverity.medium,
          summary:
              '${_formatPercent(clippingRatio * 100)} of the samples show flat '
              'tops or bottoms, which indicates clipping. No allowed voltage '
              'range was supplied.',
          measured: measured,
          events: events,
          missingInputs: const [
            'allowedMaxVolts/allowedMinVolts or maxClippingPercent for a '
                'pass/fail verdict',
          ],
        );
      }
      return _finding(
        test: WaveformFaultTest.clipping,
        status: WaveformFaultStatus.informational,
        summary:
            'No significant flat tops or bottoms were detected '
            '(${_formatPercent(clippingRatio * 100)} clipped samples).',
        measured: measured,
        missingInputs: const [
          'allowedMaxVolts/allowedMinVolts or maxClippingPercent for a '
              'pass/fail verdict',
        ],
      );
    }
    return _finding(
      test: WaveformFaultTest.clipping,
      status: WaveformFaultStatus.pass,
      summary:
          'The signal stays within the allowed voltage range and the clipping '
          'ratio is ${_formatPercent(clippingRatio * 100)}.',
      measured: measured,
      expected: expected,
      events: events,
    );
  }

  WaveformFaultFinding _frequencyError(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final frequencies = <double>[
      for (final period in profile.periods)
        if (period > 0) 1 / period,
    ];
    final measured = <String, dynamic>{
      'periodCount': profile.periods.length,
      'meanFrequencyHz': _finite(
        frequencies.isEmpty ? profile.fundamentalHz : _mean(frequencies),
      ),
      'minFrequencyHz': _finite(
        frequencies.isEmpty ? null : frequencies.reduce(math.min),
      ),
      'maxFrequencyHz': _finite(
        frequencies.isEmpty ? null : frequencies.reduce(math.max),
      ),
      'driftPercent': _finite(_frequencyDriftPercent(frequencies)),
      'driftHzPerSecond': _finite(_frequencyDriftSlope(profile)),
      'currentFrequencyHz': _finite(profile.fundamentalHz),
    };
    final expectedFrequency = request.number('expectedFrequencyHz');
    final toleranceHz = request.number('toleranceHz');
    final tolerancePercent = request.number('tolerancePercent');
    final maxDriftHz = request.number('maxDriftHz');
    final maxDriftPercent = request.number('maxDriftPercent');
    final meanFrequency = measured['meanFrequencyHz'] as double?;
    if (meanFrequency == null) {
      return _finding(
        test: WaveformFaultTest.frequencyError,
        status: WaveformFaultStatus.inconclusive,
        summary:
            'No periodic frequency was detected; frequency error and drift '
            'cannot be measured.',
        measured: measured,
        missingInputs: const ['a periodic signal with at least two periods'],
      );
    }
    final expected = <String, dynamic>{
      if (expectedFrequency != null) 'frequencyHz': _finite(expectedFrequency),
      if (maxDriftHz != null) 'maxDriftHz': _finite(maxDriftHz),
      if (maxDriftPercent != null) 'maxDriftPercent': _finite(maxDriftPercent),
    };
    final missing = <String>[];
    if (expectedFrequency == null) {
      missing.add(
        'expectedFrequencyHz and toleranceHz or tolerancePercent for a '
        'pass/fail verdict',
      );
    }
    if (expectedFrequency != null) {
      final tolerance = _tolerance(
        toleranceHz,
        tolerancePercent,
        expectedFrequency,
      );
      if (tolerance == null) {
        return _finding(
          test: WaveformFaultTest.frequencyError,
          status: WaveformFaultStatus.inconclusive,
          summary:
              'The expected frequency is '
              '${_formatHz(expectedFrequency)}, but no tolerance was supplied.',
          measured: measured,
          expected: expected,
          missingInputs: const [
            'toleranceHz or tolerancePercent for expectedFrequencyHz',
          ],
        );
      }
      expected['toleranceHz'] = _finite(tolerance);
      if ((meanFrequency - expectedFrequency).abs() > tolerance) {
        final deviation = meanFrequency - expectedFrequency;
        return _finding(
          test: WaveformFaultTest.frequencyError,
          status: WaveformFaultStatus.fail,
          severity: _severityForRatio(deviation.abs() / tolerance),
          summary:
              'The mean frequency is ${_formatHz(meanFrequency)}, '
              '${_formatSignedHz(deviation)} from the specified '
              '${_formatHz(expectedFrequency)} '
              '(${_formatSignedPercent(_percent(deviation, expectedFrequency))}).',
          measured: measured,
          expected: expected,
          deviation: {
            'frequencyHz': _finite(deviation),
            'percent': _finite(_percent(deviation, expectedFrequency)),
          },
        );
      }
    }
    final driftPercent = _frequencyDriftPercent(frequencies);
    final driftRange = frequencies.isEmpty
        ? 0.0
        : frequencies.reduce(math.max) - frequencies.reduce(math.min);
    final driftViolated =
        (maxDriftHz != null && driftRange > maxDriftHz) ||
        (maxDriftPercent != null &&
            driftPercent != null &&
            driftPercent.abs() > maxDriftPercent);
    if (driftViolated) {
      return _finding(
        test: WaveformFaultTest.frequencyError,
        status: WaveformFaultStatus.fail,
        severity: maxDriftPercent != null && driftPercent != null
            ? _severityForRatio(driftPercent.abs() / maxDriftPercent)
            : WaveformFaultSeverity.high,
        summary:
            'The frequency drifts by ${_formatHz(driftRange)} '
            '(${_formatSignedPercent(driftPercent)} over the record), above '
            'the specified drift limit.',
        measured: measured,
        expected: expected,
      );
    }
    if (expected.isEmpty) {
      if (driftPercent != null && driftPercent.abs() > 5) {
        return _finding(
          test: WaveformFaultTest.frequencyError,
          status: WaveformFaultStatus.warning,
          severity: driftPercent.abs() > 20
              ? WaveformFaultSeverity.high
              : WaveformFaultSeverity.medium,
          summary:
              'The frequency changes by ${_formatSignedPercent(driftPercent)} '
              'across the record; no reference frequency or drift limit was '
              'supplied.',
          measured: measured,
          events: _frequencyEvents(profile),
          missingInputs: missing,
        );
      }
      return _finding(
        test: WaveformFaultTest.frequencyError,
        status: WaveformFaultStatus.informational,
        summary:
            'The mean frequency is '
            '${_formatHz(meanFrequency)}; no reference frequency or drift '
            'limit was supplied.',
        measured: measured,
        events: _frequencyEvents(profile),
        missingInputs: missing,
      );
    }
    return _finding(
      test: WaveformFaultTest.frequencyError,
      status: WaveformFaultStatus.pass,
      summary:
          'The frequency is within the specification and the drift is '
          '${_formatSignedPercent(driftPercent)}.',
      measured: measured,
      expected: expected,
      events: _frequencyEvents(profile),
    );
  }

  WaveformFaultFinding _noise(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final signalRms = profile.vStd;
    final noiseRms = profile.noiseRms;
    final snrDb = signalRms > 0 && noiseRms > 0
        ? 20 * math.log(signalRms / noiseRms) / math.ln10
        : null;
    final noiseFloor = _spectrumNoiseFloor(profile.spectrum);
    final fundamental = _fundamentalAmplitude(
      profile.spectrum,
      profile.fundamentalHz,
    );
    final noiseFloorDbc =
        noiseFloor != null && fundamental != null && fundamental > 0
        ? 20 * math.log(noiseFloor / fundamental) / math.ln10
        : null;
    final measured = <String, dynamic>{
      'rmsNoiseVolts': _finite(noiseRms),
      'signalRmsVolts': _finite(signalRms),
      'snrDb': _finite(snrDb),
      'noiseFloorVolts': _finite(noiseFloor),
      'noiseFloorDbc': _finite(noiseFloorDbc),
      'bandwidthHz': _finite(
        profile.context.sampleRateHz == null
            ? null
            : profile.context.sampleRateHz! / 2,
      ),
      'quantizationStepVolts': _finite(profile.lsb),
    };
    final maxNoise = request.number('maxNoiseRmsVolts');
    final minSnr = request.number('minSnrDb');
    final maxFloor = request.number('maxNoiseFloorVolts');
    final expected = <String, dynamic>{
      if (maxNoise != null) 'maxNoiseRmsVolts': _finite(maxNoise),
      if (minSnr != null) 'minSnrDb': _finite(minSnr),
      if (maxFloor != null) 'maxNoiseFloorVolts': _finite(maxFloor),
    };
    final missing = expected.isEmpty
        ? const [
            'maxNoiseRmsVolts, minSnrDb or maxNoiseFloorVolts for a pass/fail '
                'verdict',
          ]
        : const <String>[];
    if (maxNoise != null && noiseRms > maxNoise) {
      return _finding(
        test: WaveformFaultTest.noise,
        status: WaveformFaultStatus.fail,
        severity: _severityForRatio(noiseRms / maxNoise),
        summary:
            'The RMS noise is ${_formatVolts(noiseRms)}, above the allowed '
            '${_formatVolts(maxNoise)}.',
        measured: measured,
        expected: expected,
      );
    }
    if (minSnr != null && snrDb != null && snrDb < minSnr) {
      return _finding(
        test: WaveformFaultTest.noise,
        status: WaveformFaultStatus.fail,
        severity: _severityForRatio(minSnr / math.max(snrDb, 1e-12)),
        summary:
            'The SNR is ${_formatDb(snrDb)}, below the specified minimum '
            '${_formatDb(minSnr)}.',
        measured: measured,
        expected: expected,
      );
    }
    if (maxFloor != null && noiseFloor != null && noiseFloor > maxFloor) {
      return _finding(
        test: WaveformFaultTest.noise,
        status: WaveformFaultStatus.fail,
        severity: _severityForRatio(noiseFloor / maxFloor),
        summary:
            'The noise floor is ${_formatVolts(noiseFloor)}, above the allowed '
            '${_formatVolts(maxFloor)}.',
        measured: measured,
        expected: expected,
      );
    }
    if (expected.isEmpty) {
      final noiseRatio = signalRms > 0 ? noiseRms / signalRms : 0.0;
      if (noiseRatio > 0.1 || noiseRms > 0.05 * profile.vPp) {
        return _finding(
          test: WaveformFaultTest.noise,
          status: WaveformFaultStatus.warning,
          severity: noiseRatio > 0.3
              ? WaveformFaultSeverity.high
              : WaveformFaultSeverity.medium,
          summary:
              'The RMS noise is ${_formatVolts(noiseRms)} '
              '(${_formatPercent(noiseRatio * 100)} of the signal RMS); no '
              'reference noise level was supplied.',
          measured: measured,
          missingInputs: missing,
        );
      }
      return _finding(
        test: WaveformFaultTest.noise,
        status: WaveformFaultStatus.informational,
        summary:
            'The RMS noise is ${_formatVolts(noiseRms)}; no reference noise '
            'level was supplied.',
        measured: measured,
        missingInputs: missing,
      );
    }
    return _finding(
      test: WaveformFaultTest.noise,
      status: WaveformFaultStatus.pass,
      summary:
          'The RMS noise is ${_formatVolts(noiseRms)} and within the '
          'specification.',
      measured: measured,
      expected: expected,
    );
  }

  WaveformFaultFinding _ringing(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final ringing = _detectRinging(profile, request);
    final measured = <String, dynamic>{
      'ringingEventCount': ringing.length,
      'largestRingingAmplitudeVolts': _finite(
        ringing.isEmpty
            ? null
            : ringing.map((event) => event.amplitudeVolts).reduce(math.max),
      ),
      'dominantRingingFrequencyHz': _finite(
        ringing.isEmpty
            ? null
            : _median([for (final event in ringing) event.frequencyHz ?? 0]) ==
                  0
            ? null
            : _median([for (final event in ringing) event.frequencyHz ?? 0]),
      ),
      'thresholdVolts': _finite(_ringingThreshold(request, profile)),
    };
    final expected = <String, dynamic>{
      if (request.number('ringingThresholdVolts') != null)
        'ringingThresholdVolts': _finite(
          request.number('ringingThresholdVolts'),
        ),
      if (request.number('maxRingingDurationSeconds') != null)
        'maxRingingDurationSeconds': _finite(
          request.number('maxRingingDurationSeconds'),
        ),
      if (request.number('minRingingFrequencyHz') != null)
        'minRingingFrequencyHz': _finite(
          request.number('minRingingFrequencyHz'),
        ),
      if (request.number('maxRingingFrequencyHz') != null)
        'maxRingingFrequencyHz': _finite(
          request.number('maxRingingFrequencyHz'),
        ),
    };
    final events = [
      for (final event in ringing.take(10))
        {
          'startSeconds': _finite(event.startSeconds),
          'amplitudeVolts': _finite(event.amplitudeVolts),
          'frequencyHz': _finite(event.frequencyHz),
          'decayRatePerSecond': _finite(event.decayRatePerSecond),
          'durationSeconds': _finite(event.durationSeconds),
        },
    ];
    if (ringing.isEmpty) {
      return _finding(
        test: WaveformFaultTest.ringing,
        status: expected.isEmpty
            ? WaveformFaultStatus.informational
            : WaveformFaultStatus.pass,
        summary: expected.isEmpty
            ? 'No ringing above the internal threshold was detected after '
                  'the edges.'
            : 'No ringing above the specified threshold was detected after '
                  'the edges.',
        measured: measured,
        expected: expected.isEmpty ? null : expected,
        missingInputs: expected.isEmpty
            ? const [
                'ringingThresholdVolts and maxRingingDurationSeconds for a '
                    'pass/fail verdict',
              ]
            : const <String>[],
      );
    }
    final threshold = _ringingThreshold(request, profile);
    final suppliedThreshold = request.number('ringingThresholdVolts') != null;
    final maxDuration = request.number('maxRingingDurationSeconds');
    final durationViolated =
        maxDuration != null &&
        ringing.any((event) => event.durationSeconds > maxDuration);
    final minFrequency = request.number('minRingingFrequencyHz');
    final maxFrequency = request.number('maxRingingFrequencyHz');
    final frequencyViolated = ringing.any(
      (event) =>
          (minFrequency != null && (event.frequencyHz ?? 0) < minFrequency) ||
          (maxFrequency != null && (event.frequencyHz ?? 0) > maxFrequency),
    );
    final violated = suppliedThreshold || durationViolated || frequencyViolated;
    return _finding(
      test: WaveformFaultTest.ringing,
      status: violated ? WaveformFaultStatus.fail : WaveformFaultStatus.warning,
      severity: violated
          ? WaveformFaultSeverity.high
          : WaveformFaultSeverity.medium,
      summary:
          '${ringing.length} ringing event(s) above '
          '${_formatVolts(threshold)} were detected after steep edges; the '
          'largest amplitude is '
          '${_formatVolts(measured['largestRingingAmplitudeVolts'] as double?)}.',
      measured: measured,
      expected: expected.isEmpty ? null : expected,
      events: events,
      missingInputs: expected.isEmpty
          ? const [
              'ringingThresholdVolts and maxRingingDurationSeconds for a '
                  'pass/fail verdict',
            ]
          : const <String>[],
    );
  }

  WaveformFaultFinding _dutyCycle(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final runs = _pulseRuns(profile);
    final highRuns = runs.where((run) => run.high).toList();
    final duties = <double>[];
    for (var i = 0; i + 1 < highRuns.length; i++) {
      final period = highRuns[i + 1].startSeconds - highRuns[i].startSeconds;
      if (period > 0) duties.add(highRuns[i].widthSeconds / period * 100);
    }
    if (duties.length < 2 || profile.durationSeconds <= 0) {
      return _finding(
        test: WaveformFaultTest.dutyCycle,
        status: WaveformFaultStatus.inconclusive,
        summary:
            'Fewer than two complete high pulses were detected; the duty '
            'cycle cannot be measured.',
        measured: {'pulseCount': highRuns.length},
        missingInputs: const ['a longer record with at least two periods'],
      );
    }
    final meanDuty = _mean(duties);
    final minDuty = duties.reduce(math.min);
    final maxDuty = duties.reduce(math.max);
    final variation = _std(duties) / meanDuty * 100;
    final measured = <String, dynamic>{
      'dutyPercent': _finite(meanDuty),
      'minDutyPercent': _finite(minDuty),
      'maxDutyPercent': _finite(maxDuty),
      'dutyVariationPercent': _finite(variation),
      'pulseCount': highRuns.length,
    };
    final expectedDuty = request.number('expectedDutyPercent');
    final tolerance = request.number('tolerancePercent');
    final expected = <String, dynamic>{
      if (expectedDuty != null) 'dutyPercent': _finite(expectedDuty),
      if (tolerance != null) 'tolerancePercent': _finite(tolerance),
    };
    final events = <Map<String, dynamic>>[];
    for (var i = 0; i < duties.length; i++) {
      if (expectedDuty != null &&
          tolerance != null &&
          (duties[i] - expectedDuty).abs() <= tolerance) {
        continue;
      }
      events.add({
        'startSeconds': _finite(highRuns[i].startSeconds),
        'dutyPercent': _finite(duties[i]),
      });
      if (events.length >= 10) break;
    }
    if (expectedDuty == null || tolerance == null) {
      if (variation > 5) {
        return _finding(
          test: WaveformFaultTest.dutyCycle,
          status: WaveformFaultStatus.warning,
          severity: variation > 20
              ? WaveformFaultSeverity.high
              : WaveformFaultSeverity.medium,
          summary:
              'The duty cycle varies between ${_formatPercent(minDuty)} and '
              '${_formatPercent(maxDuty)}; no expected duty or tolerance was '
              'supplied.',
          measured: measured,
          missingInputs: const [
            'expectedDutyPercent and tolerancePercent for a pass/fail verdict',
          ],
          events: events,
        );
      }
      return _finding(
        test: WaveformFaultTest.dutyCycle,
        status: WaveformFaultStatus.informational,
        summary:
            'The duty cycle is ${_formatPercent(meanDuty)}; no expected duty '
            'or tolerance was supplied.',
        measured: measured,
        missingInputs: const [
          'expectedDutyPercent and tolerancePercent for a pass/fail verdict',
        ],
        events: events,
      );
    }
    final deviation = meanDuty - expectedDuty;
    final passed = deviation.abs() <= tolerance;
    return _finding(
      test: WaveformFaultTest.dutyCycle,
      status: passed ? WaveformFaultStatus.pass : WaveformFaultStatus.fail,
      severity: passed
          ? WaveformFaultSeverity.none
          : _severityForRatio(deviation.abs() / tolerance),
      summary: passed
          ? 'The duty cycle is ${_formatPercent(meanDuty)} and within the '
                'specified ${_formatPercent(expectedDuty)} ± '
                '${_formatPercent(tolerance)}.'
          : 'The duty cycle is ${_formatPercent(meanDuty)}, '
                '${_formatSignedPercent(deviation)} from the specified '
                '${_formatPercent(expectedDuty)}.',
      measured: measured,
      expected: expected,
      deviation: {'percent': _finite(deviation)},
      events: events,
    );
  }

  WaveformFaultFinding _glitches(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final runs = _pulseRuns(profile);
    final highRuns = runs.where((run) => run.high).toList();
    final lowRuns = runs.where((run) => !run.high).toList();
    final minPulseWidth = request.number('minPulseWidthSeconds');
    final expectedPulseCount = request.integer('expectedPulseCount');
    final glitches = <_RunEvent>[];
    if (minPulseWidth != null) {
      for (final run in runs) {
        if (run.widthSeconds < minPulseWidth) glitches.add(run);
      }
    } else {
      for (final group in [highRuns, lowRuns]) {
        if (group.length < 5) continue;
        final medianWidth = _median([
          for (final run in group) run.widthSeconds,
        ]);
        if (medianWidth <= 0) continue;
        final threshold = 0.25 * medianWidth;
        for (final run in group) {
          if (run.widthSeconds < threshold) glitches.add(run);
        }
      }
    }
    final measured = <String, dynamic>{
      'pulseCount': highRuns.length,
      'glitchCount': glitches.length,
      'shortestPulseSeconds': _finite(
        runs.isEmpty
            ? null
            : runs.map((run) => run.widthSeconds).reduce(math.min),
      ),
      'medianHighWidthSeconds': _finite(
        highRuns.isEmpty
            ? null
            : _median([for (final run in highRuns) run.widthSeconds]),
      ),
      'medianLowWidthSeconds': _finite(
        lowRuns.isEmpty
            ? null
            : _median([for (final run in lowRuns) run.widthSeconds]),
      ),
    };
    final expected = <String, dynamic>{
      if (minPulseWidth != null) 'minPulseWidthSeconds': _finite(minPulseWidth),
      'expectedPulseCount': ?expectedPulseCount,
    };
    final events = [
      for (final run in glitches.take(10))
        {
          'startSeconds': _finite(run.startSeconds),
          'durationSeconds': _finite(run.widthSeconds),
          'polarity': run.high ? 'high' : 'low',
          'levelVolts': _finite(run.levelVolts),
        },
    ];
    final maxGlitchCount = request.integer('maxGlitchCount');
    final pulseCountViolated =
        expectedPulseCount != null &&
        (highRuns.length - expectedPulseCount).abs() >
            math.max(1, (expectedPulseCount * 0.1).round());
    if (pulseCountViolated) {
      return _finding(
        test: WaveformFaultTest.glitches,
        status: WaveformFaultStatus.fail,
        severity: _severityForRatio(
          (highRuns.length - expectedPulseCount).abs() /
              math.max(1, expectedPulseCount),
        ),
        summary:
            'The record contains ${highRuns.length} high pulse(s) instead of '
            'the expected $expectedPulseCount.',
        measured: measured,
        expected: expected,
        events: events,
      );
    }
    if (glitches.isEmpty) {
      return _finding(
        test: WaveformFaultTest.glitches,
        status: expected.isEmpty
            ? WaveformFaultStatus.informational
            : WaveformFaultStatus.pass,
        summary: expected.isEmpty
            ? 'No pulses shorter than 25 % of the median pulse width were '
                  'detected.'
            : 'No glitches were detected and the specified pulse rules were '
                  'met.',
        measured: measured,
        expected: expected.isEmpty ? null : expected,
        missingInputs: expected.isEmpty
            ? const [
                'minPulseWidthSeconds or expectedPulseCount for a pass/fail '
                    'verdict',
              ]
            : const <String>[],
      );
    }
    final countViolated =
        maxGlitchCount != null && glitches.length > maxGlitchCount;
    final status = minPulseWidth != null || countViolated
        ? WaveformFaultStatus.fail
        : WaveformFaultStatus.warning;
    return _finding(
      test: WaveformFaultTest.glitches,
      status: status,
      severity: countViolated
          ? _severityForRatio(glitches.length / maxGlitchCount)
          : WaveformFaultSeverity.medium,
      summary:
          '${glitches.length} pulse(s) are shorter than the expected pulse '
          'width; the shortest is '
          '${_formatSeconds(measured['shortestPulseSeconds'] as double?)}.',
      measured: measured,
      expected: expected.isEmpty ? null : expected,
      events: events,
      missingInputs: expected.isEmpty
          ? const [
              'minPulseWidthSeconds or expectedPulseCount for a pass/fail '
                  'verdict',
            ]
          : const <String>[],
    );
  }

  WaveformFaultFinding _jitter(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final periods = profile.periods;
    if (periods.length < 3) {
      return _finding(
        test: WaveformFaultTest.jitter,
        status: WaveformFaultStatus.inconclusive,
        summary:
            'Fewer than three periods were detected; jitter cannot be '
            'measured.',
        measured: {'periodCount': periods.length},
        missingInputs: const ['a record with at least three periods'],
      );
    }
    final meanPeriod = _mean(periods);
    final stdPeriod = _std(periods);
    final peakToPeak = periods.reduce(math.max) - periods.reduce(math.min);
    final cycleToCycle = <double>[
      for (var i = 1; i < periods.length; i++)
        (periods[i] - periods[i - 1]).abs(),
    ];
    final cycleToCycleStd = _std(cycleToCycle);
    final cycleToCycleMax = cycleToCycle.reduce(math.max);
    final measured = <String, dynamic>{
      'periodCount': periods.length,
      'meanPeriodSeconds': _finite(meanPeriod),
      'stdPeriodSeconds': _finite(stdPeriod),
      'peakToPeakJitterSeconds': _finite(peakToPeak),
      'jitterPercent': _finite(stdPeriod / meanPeriod * 100),
      'cycleToCycleStdSeconds': _finite(cycleToCycleStd),
      'cycleToCycleMaxSeconds': _finite(cycleToCycleMax),
    };
    final maxJitterSeconds =
        request.number('maxJitterSeconds') ??
        (request.number('maxJitterPicoseconds') == null
            ? null
            : request.number('maxJitterPicoseconds')! * 1e-12);
    final maxCycleToCycle = request.number('maxCycleToCycleSeconds');
    final maxJitterPercent = request.number('maxJitterPercent');
    final expected = <String, dynamic>{
      if (maxJitterSeconds != null)
        'maxJitterSeconds': _finite(maxJitterSeconds),
      if (request.number('maxJitterPicoseconds') != null)
        'maxJitterPicoseconds': _finite(request.number('maxJitterPicoseconds')),
      if (maxJitterPercent != null)
        'maxJitterPercent': _finite(maxJitterPercent),
      if (maxCycleToCycle != null)
        'maxCycleToCycleSeconds': _finite(maxCycleToCycle),
    };
    final events = _worstPeriodEvents(profile);
    final missing = expected.isEmpty
        ? const [
            'maxJitterSeconds/maxJitterPicoseconds or maxJitterPercent for a '
                'pass/fail verdict',
          ]
        : const <String>[];
    final violated =
        (maxJitterSeconds != null && stdPeriod > maxJitterSeconds) ||
        (maxJitterPercent != null &&
            stdPeriod / meanPeriod * 100 > maxJitterPercent) ||
        (maxCycleToCycle != null && cycleToCycleMax > maxCycleToCycle);
    if (violated) {
      return _finding(
        test: WaveformFaultTest.jitter,
        status: WaveformFaultStatus.fail,
        severity: maxJitterPercent != null
            ? _severityForRatio(
                (stdPeriod / meanPeriod * 100) / maxJitterPercent,
              )
            : WaveformFaultSeverity.high,
        summary:
            'The period jitter is ${_formatSeconds(stdPeriod)} RMS '
            '(${_formatPercent(stdPeriod / meanPeriod * 100)}), above the '
            'specified limit.',
        measured: measured,
        expected: expected,
        events: events,
      );
    }
    if (expected.isEmpty) {
      final jitterPercent = stdPeriod / meanPeriod * 100;
      if (jitterPercent > 2 || peakToPeak / meanPeriod * 100 > 10) {
        return _finding(
          test: WaveformFaultTest.jitter,
          status: WaveformFaultStatus.warning,
          severity: jitterPercent > 10
              ? WaveformFaultSeverity.high
              : WaveformFaultSeverity.medium,
          summary:
              'The period jitter is ${_formatPercent(jitterPercent)} RMS and '
              '${_formatPercent(peakToPeak / meanPeriod * 100)} peak-to-peak; '
              'no jitter limit was supplied.',
          measured: measured,
          events: events,
          missingInputs: missing,
        );
      }
      return _finding(
        test: WaveformFaultTest.jitter,
        status: WaveformFaultStatus.informational,
        summary:
            'The period jitter is ${_formatPercent(jitterPercent)} RMS; no '
            'jitter limit was supplied.',
        measured: measured,
        events: events,
        missingInputs: missing,
      );
    }
    return _finding(
      test: WaveformFaultTest.jitter,
      status: WaveformFaultStatus.pass,
      summary:
          'The period jitter is ${_formatSeconds(stdPeriod)} RMS and within '
          'the specification.',
      measured: measured,
      expected: expected,
      events: events,
    );
  }

  WaveformFaultFinding _dcOffset(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final windows = _windowStats(profile, _windowCount(profile, null));
    final firstMean = windows.isEmpty ? profile.vMean : windows.first.vMean;
    final lastMean = windows.isEmpty ? profile.vMean : windows.last.vMean;
    final drift = lastMean - firstMean;
    final baseline = (profile.lowLevel + profile.highLevel) / 2;
    final measured = <String, dynamic>{
      'meanVolts': _finite(profile.vMean),
      'medianVolts': _finite(_median(profile.sortedVolts)),
      'baselineVolts': _finite(baseline),
      'firstWindowMeanVolts': _finite(firstMean),
      'lastWindowMeanVolts': _finite(lastMean),
      'driftVolts': _finite(drift),
      'driftPercentOfVpp': _finite(
        profile.vPp == 0 ? null : drift / profile.vPp * 100,
      ),
    };
    final expectedMean = request.number('expectedMeanVolts');
    final expectedBaseline = request.number('expectedBaselineVolts');
    final tolerance = request.number('toleranceVolts');
    final maxDrift = request.number('maxDriftVolts');
    if ((expectedMean != null || expectedBaseline != null) &&
        tolerance == null) {
      return _finding(
        test: WaveformFaultTest.dcOffset,
        status: WaveformFaultStatus.inconclusive,
        summary: 'A DC reference was supplied, but no tolerance was supplied.',
        measured: measured,
        missingInputs: const ['toleranceVolts for the DC reference'],
      );
    }
    final expected = <String, dynamic>{
      if (expectedMean != null) 'meanVolts': _finite(expectedMean),
      if (expectedBaseline != null) 'baselineVolts': _finite(expectedBaseline),
      if (tolerance != null) 'toleranceVolts': _finite(tolerance),
      if (maxDrift != null) 'maxDriftVolts': _finite(maxDrift),
    };
    final missing = expected.isEmpty
        ? const [
            'expectedMeanVolts or expectedBaselineVolts and toleranceVolts for '
                'a pass/fail verdict',
          ]
        : const <String>[];
    final meanViolated =
        expectedMean != null &&
        tolerance != null &&
        (profile.vMean - expectedMean).abs() > tolerance;
    final baselineViolated =
        expectedBaseline != null &&
        tolerance != null &&
        (baseline - expectedBaseline).abs() > tolerance;
    final driftViolated = maxDrift != null && drift.abs() > maxDrift;
    if (meanViolated || baselineViolated || driftViolated) {
      final deviation = meanViolated
          ? profile.vMean - expectedMean
          : baselineViolated
          ? baseline - expectedBaseline
          : drift;
      return _finding(
        test: WaveformFaultTest.dcOffset,
        status: WaveformFaultStatus.fail,
        severity: tolerance != null && (meanViolated || baselineViolated)
            ? _severityForRatio(deviation.abs() / tolerance)
            : WaveformFaultSeverity.high,
        summary:
            'The DC level is ${_formatVolts(profile.vMean)} (baseline '
            '${_formatVolts(baseline)}), '
            '${_formatSignedVolts(deviation)} from the specification.',
        measured: measured,
        expected: expected,
        deviation: {'volts': _finite(deviation)},
      );
    }
    if (expected.isEmpty) {
      if (profile.vPp > 0 && drift.abs() > 0.05 * profile.vPp) {
        return _finding(
          test: WaveformFaultTest.dcOffset,
          status: WaveformFaultStatus.warning,
          severity: WaveformFaultSeverity.medium,
          summary:
              'The DC level drifts by ${_formatSignedVolts(drift)} across the '
              'record; no expected DC level was supplied.',
          measured: measured,
          missingInputs: missing,
        );
      }
      return _finding(
        test: WaveformFaultTest.dcOffset,
        status: WaveformFaultStatus.informational,
        summary:
            'The mean level is ${_formatVolts(profile.vMean)} and the baseline '
            'is ${_formatVolts(baseline)}; no expected DC level was supplied.',
        measured: measured,
        missingInputs: missing,
      );
    }
    return _finding(
      test: WaveformFaultTest.dcOffset,
      status: WaveformFaultStatus.pass,
      summary:
          'The DC level is ${_formatVolts(profile.vMean)} and within the '
          'specification.',
      measured: measured,
      expected: expected,
    );
  }

  WaveformFaultFinding _distortion(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final spectrum = profile.spectrum;
    if (spectrum == null || spectrum.amplitudes.length < 4) {
      return _finding(
        test: WaveformFaultTest.distortion,
        status: WaveformFaultStatus.inconclusive,
        summary:
            'The sample rate is unknown; no FFT distortion analysis is '
            'possible.',
        measured: const {},
        missingInputs: const ['sampleRateHz'],
      );
    }
    final peakIndex = _dominantPeakIndex(spectrum);
    final fundamental = spectrum.interpolatedPeakFrequency(peakIndex);
    final harmonicAmplitudes = <double>[];
    if (fundamental != null && fundamental > 0) {
      for (var harmonic = 2; harmonic <= 5; harmonic++) {
        final amplitude = spectrum.amplitudeNear(
          fundamental * harmonic,
          binTolerance: 2,
        );
        if (amplitude != null) harmonicAmplitudes.add(amplitude);
      }
    }
    final h1 = spectrum.amplitudes[peakIndex];
    final thd = h1 > 0 && harmonicAmplitudes.isNotEmpty
        ? math.sqrt(
                harmonicAmplitudes.fold<double>(
                  0,
                  (sum, amplitude) => sum + amplitude * amplitude,
                ),
              ) /
              h1 *
              100
        : null;
    final positive = profile.vMax - profile.vMean;
    final negative = profile.vMean - profile.vMin;
    final symmetryError = positive > 0 && negative > 0
        ? (positive - negative).abs() / ((positive + negative) / 2) * 100
        : null;
    final meanAbsolute = _meanAbsoluteDeviation(profile);
    final formFactor = meanAbsolute > 0 ? profile.vStd / meanAbsolute : null;
    final measured = <String, dynamic>{
      'fundamentalFrequencyHz': _finite(fundamental),
      'fundamentalAmplitudeVolts': _finite(h1),
      'thdPercent': _finite(thd),
      'symmetryErrorPercent': _finite(symmetryError),
      'formFactor': _finite(formFactor),
      'harmonicAmplitudesVolts': [
        for (var i = 0; i < harmonicAmplitudes.length; i++)
          {
            'harmonic': i + 2,
            'frequencyHz': _finite(
              fundamental == null ? null : fundamental * (i + 2),
            ),
            'amplitudeVolts': _finite(harmonicAmplitudes[i]),
            'percentOfFundamental': _finite(
              h1 > 0 ? harmonicAmplitudes[i] / h1 * 100 : null,
            ),
          },
      ],
    };
    final maxThd = request.number('maxThdPercent');
    final maxHarmonic = request.number('maxHarmonicPercent');
    final maxSymmetry = request.number('maxSymmetryErrorPercent');
    final expected = <String, dynamic>{
      if (maxThd != null) 'maxThdPercent': _finite(maxThd),
      if (maxHarmonic != null) 'maxHarmonicPercent': _finite(maxHarmonic),
      if (maxSymmetry != null) 'maxSymmetryErrorPercent': _finite(maxSymmetry),
    };
    final harmonicViolated =
        maxHarmonic != null &&
        h1 > 0 &&
        harmonicAmplitudes.any(
          (amplitude) => amplitude / h1 * 100 > maxHarmonic,
        );
    final violated =
        (maxThd != null && thd != null && thd > maxThd) ||
        harmonicViolated ||
        (maxSymmetry != null &&
            symmetryError != null &&
            symmetryError > maxSymmetry);
    if (violated) {
      return _finding(
        test: WaveformFaultTest.distortion,
        status: WaveformFaultStatus.fail,
        severity: maxThd != null && thd != null
            ? _severityForRatio(thd / maxThd)
            : WaveformFaultSeverity.high,
        summary:
            'The distortion exceeds the specification (THD '
            '${_formatPercent(thd)}, symmetry error '
            '${_formatPercent(symmetryError)}).',
        measured: measured,
        expected: expected,
      );
    }
    if (expected.isEmpty) {
      if (profile.isRectangular) {
        return _finding(
          test: WaveformFaultTest.distortion,
          status: WaveformFaultStatus.informational,
          summary:
              'The signal is rectangular; the measured THD of '
              '${_formatPercent(thd)} is expected for this signal type. No '
              'distortion limit was supplied.',
          measured: measured,
          missingInputs: const [
            'maxThdPercent, maxHarmonicPercent or maxSymmetryErrorPercent for '
                'a pass/fail verdict',
          ],
        );
      }
      if ((thd != null && thd > 5) ||
          (symmetryError != null && symmetryError > 10)) {
        return _finding(
          test: WaveformFaultTest.distortion,
          status: WaveformFaultStatus.warning,
          severity: (thd ?? 0) > 15
              ? WaveformFaultSeverity.high
              : WaveformFaultSeverity.medium,
          summary:
              'The signal shows distortion (THD ${_formatPercent(thd)}, '
              'symmetry error ${_formatPercent(symmetryError)}); no distortion '
              'limit was supplied.',
          measured: measured,
          missingInputs: const [
            'maxThdPercent, maxHarmonicPercent or maxSymmetryErrorPercent for '
                'a pass/fail verdict',
          ],
        );
      }
      return _finding(
        test: WaveformFaultTest.distortion,
        status: WaveformFaultStatus.informational,
        summary:
            'THD is ${_formatPercent(thd)} and the symmetry error is '
            '${_formatPercent(symmetryError)}; no distortion limit was '
            'supplied.',
        measured: measured,
        missingInputs: const [
          'maxThdPercent, maxHarmonicPercent or maxSymmetryErrorPercent for a '
              'pass/fail verdict',
        ],
      );
    }
    return _finding(
      test: WaveformFaultTest.distortion,
      status: WaveformFaultStatus.pass,
      summary:
          'THD is ${_formatPercent(thd)} and the symmetry error is '
          '${_formatPercent(symmetryError)}, within the specification.',
      measured: measured,
      expected: expected,
    );
  }

  WaveformFaultFinding _spuriousFrequencies(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final spectrum = profile.spectrum;
    if (spectrum == null || spectrum.amplitudes.length < 8) {
      return _finding(
        test: WaveformFaultTest.spuriousFrequencies,
        status: WaveformFaultStatus.inconclusive,
        summary: 'The sample rate is unknown; no FFT analysis is possible.',
        measured: const {},
        missingInputs: const ['sampleRateHz'],
      );
    }
    final expectedFundamental = request.number('expectedFundamentalHz');
    final fundamental =
        expectedFundamental ??
        profile.fundamentalHz ??
        spectrum.dominantFrequency;
    if (fundamental == null || fundamental <= 0) {
      return _finding(
        test: WaveformFaultTest.spuriousFrequencies,
        status: WaveformFaultStatus.inconclusive,
        summary:
            'No fundamental frequency was found; the expected frequency '
            'components cannot be excluded.',
        measured: {'sampleRateHz': _finite(profile.context.sampleRateHz)},
        missingInputs: const ['expectedFundamentalHz'],
      );
    }
    final harmonicCount = request.integer('harmonicCount') ?? 10;
    final h1 = spectrum.amplitudeNear(fundamental, binTolerance: 2) ?? 0;
    final noiseFloor = _spectrumNoiseFloor(spectrum) ?? 0;
    final minimumAmplitude =
        request.number('minSpuriousAmplitudeVolts') ??
        math.max(4 * noiseFloor, 0.01 * h1);
    final excludedBins = <int>{};
    for (var harmonic = 1; harmonic <= harmonicCount; harmonic++) {
      final frequency = fundamental * harmonic;
      final center = (frequency / spectrum.resolutionHz).round();
      for (var offset = -3; offset <= 3; offset++) {
        excludedBins.add(center + offset);
      }
    }
    final peaks = <_SpectrumPeak>[];
    for (var index = 2; index + 1 < spectrum.amplitudes.length; index++) {
      if (excludedBins.contains(index)) continue;
      final amplitude = spectrum.amplitudes[index];
      if (amplitude < minimumAmplitude) continue;
      if (amplitude < spectrum.amplitudes[index - 1] ||
          amplitude <= spectrum.amplitudes[index + 1]) {
        continue;
      }
      peaks.add(
        _SpectrumPeak(
          frequencyHz:
              spectrum.interpolatedPeakFrequency(index) ??
              spectrum.frequencies[index],
          amplitudeVolts: amplitude,
          dbc: h1 > 0 ? 20 * math.log(amplitude / h1) / math.ln10 : null,
        ),
      );
    }
    peaks.sort((a, b) => b.amplitudeVolts.compareTo(a.amplitudeVolts));
    final top = peaks.take(10).toList();
    final measured = <String, dynamic>{
      'fundamentalFrequencyHz': _finite(fundamental),
      'fundamentalAmplitudeVolts': _finite(h1),
      'frequencyResolutionHz': _finite(spectrum.resolutionHz),
      'spuriousComponentCount': peaks.length,
      'spuriousComponents': [
        for (final peak in top)
          {
            'frequencyHz': _finite(peak.frequencyHz),
            'amplitudeVolts': _finite(peak.amplitudeVolts),
            'dbc': _finite(peak.dbc),
          },
      ],
    };
    final minDbc = request.number('minSpuriousLevelDbc');
    final maxAmplitude = request.number('minSpuriousAmplitudeVolts');
    final expected = <String, dynamic>{
      if (minDbc != null) 'minSpuriousLevelDbc': _finite(minDbc),
      if (maxAmplitude != null)
        'minSpuriousAmplitudeVolts': _finite(maxAmplitude),
    };
    final events = [
      for (final peak in top)
        {
          'frequencyHz': _finite(peak.frequencyHz),
          'amplitudeVolts': _finite(peak.amplitudeVolts),
          'dbc': _finite(peak.dbc),
        },
    ];
    final violated =
        (minDbc != null &&
            top.any((peak) => peak.dbc != null && peak.dbc! > minDbc)) ||
        (maxAmplitude != null &&
            top.any((peak) => peak.amplitudeVolts > maxAmplitude));
    if (violated) {
      return _finding(
        test: WaveformFaultTest.spuriousFrequencies,
        status: WaveformFaultStatus.fail,
        severity: WaveformFaultSeverity.high,
        summary:
            '${peaks.length} unexpected spectral component(s) exceed the '
            'specification; the strongest is at '
            '${_formatHz(top.first.frequencyHz)} '
            '(${_formatDbc(top.first.dbc)}).',
        measured: measured,
        expected: expected,
        events: events,
      );
    }
    if (expected.isEmpty) {
      final strongestDbc = top.isEmpty ? null : top.first.dbc;
      if (strongestDbc != null && strongestDbc > -40) {
        return _finding(
          test: WaveformFaultTest.spuriousFrequencies,
          status: WaveformFaultStatus.warning,
          severity: strongestDbc > -20
              ? WaveformFaultSeverity.high
              : WaveformFaultSeverity.medium,
          summary:
              '${peaks.length} unexpected spectral component(s) were found; the '
              'strongest is at ${_formatHz(top.first.frequencyHz)} '
              '(${_formatDbc(strongestDbc)}). No reference spectrum or limit '
              'was supplied.',
          measured: measured,
          events: events,
          missingInputs: const [
            'minSpuriousLevelDbc or minSpuriousAmplitudeVolts for a pass/fail '
                'verdict',
          ],
        );
      }
      return _finding(
        test: WaveformFaultTest.spuriousFrequencies,
        status: WaveformFaultStatus.informational,
        summary:
            'No unexpected spectral component above '
            '${_formatVolts(minimumAmplitude)} was found; no reference '
            'spectrum or limit was supplied.',
        measured: measured,
        events: events,
        missingInputs: const [
          'minSpuriousLevelDbc or minSpuriousAmplitudeVolts for a pass/fail '
              'verdict',
        ],
      );
    }
    return _finding(
      test: WaveformFaultTest.spuriousFrequencies,
      status: WaveformFaultStatus.pass,
      summary: 'No unexpected spectral component violates the specification.',
      measured: measured,
      expected: expected,
      events: events,
    );
  }

  WaveformFaultFinding _edgeTimes(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final durations = _measureEdgeDurations(profile);
    if (durations.rise.isEmpty && durations.fall.isEmpty) {
      return _finding(
        test: WaveformFaultTest.edgeTimes,
        status: WaveformFaultStatus.inconclusive,
        summary:
            'No complete 10–90 % edge transition was found; rise and fall '
            'times cannot be measured.',
        measured: {
          'risingEdgeCount': profile.risingEdges.length,
          'fallingEdgeCount': profile.fallingEdges.length,
        },
        missingInputs: const [
          'a record with complete rising and falling edges',
        ],
      );
    }
    final rise = [for (final duration in durations.rise) duration.seconds];
    final fall = [for (final duration in durations.fall) duration.seconds];
    final meanRiseTime = rise.isEmpty ? null : _mean(rise);
    final meanFallTime = fall.isEmpty ? null : _mean(fall);
    final asymmetry =
        meanRiseTime != null &&
            meanFallTime != null &&
            math.max(meanRiseTime, meanFallTime) > 0
        ? (meanRiseTime - meanFallTime).abs() /
              math.max(meanRiseTime, meanFallTime) *
              100
        : null;
    final measured = <String, dynamic>{
      'meanRiseTimeSeconds': _finite(meanRiseTime),
      'meanFallTimeSeconds': _finite(meanFallTime),
      'minRiseTimeSeconds': _finite(
        rise.isEmpty ? null : rise.reduce(math.min),
      ),
      'maxRiseTimeSeconds': _finite(
        rise.isEmpty ? null : rise.reduce(math.max),
      ),
      'minFallTimeSeconds': _finite(
        fall.isEmpty ? null : fall.reduce(math.min),
      ),
      'maxFallTimeSeconds': _finite(
        fall.isEmpty ? null : fall.reduce(math.max),
      ),
      'asymmetryPercent': _finite(asymmetry),
      'measuredRiseEdges': rise.length,
      'measuredFallEdges': fall.length,
    };
    final maxRise = request.number('maxRiseTimeSeconds');
    final maxFall = request.number('maxFallTimeSeconds');
    final maxAsymmetry = request.number('maxAsymmetryPercent');
    final expected = <String, dynamic>{
      if (maxRise != null) 'maxRiseTimeSeconds': _finite(maxRise),
      if (maxFall != null) 'maxFallTimeSeconds': _finite(maxFall),
      if (maxAsymmetry != null) 'maxAsymmetryPercent': _finite(maxAsymmetry),
    };
    final events = _slowestEdges(durations);
    if ((maxRise != null && rise.isEmpty) ||
        (maxFall != null && fall.isEmpty)) {
      return _finding(
        test: WaveformFaultTest.edgeTimes,
        status: WaveformFaultStatus.inconclusive,
        summary: 'The requested edge type was not found in the record.',
        measured: measured,
        expected: expected,
        missingInputs: const [
          'a record containing the requested rising or falling edge',
        ],
      );
    }
    final riseViolated =
        maxRise != null &&
        rise.isNotEmpty &&
        rise.any((duration) => duration > maxRise);
    final fallViolated =
        maxFall != null &&
        fall.isNotEmpty &&
        fall.any((duration) => duration > maxFall);
    final asymmetryViolated =
        maxAsymmetry != null && asymmetry != null && asymmetry > maxAsymmetry;
    if (riseViolated || fallViolated || asymmetryViolated) {
      final ratio = riseViolated
          ? (rise.reduce(math.max) / maxRise)
          : fallViolated
          ? (fall.reduce(math.max) / maxFall)
          : (asymmetry! / maxAsymmetry!);
      return _finding(
        test: WaveformFaultTest.edgeTimes,
        status: WaveformFaultStatus.fail,
        severity: _severityForRatio(ratio),
        summary:
            'Rise time is ${_formatSeconds(meanRiseTime)} and fall time is '
            '${_formatSeconds(meanFallTime)}; the edges violate the '
            'specification.',
        measured: measured,
        expected: expected,
        events: events,
      );
    }
    if (expected.isEmpty) {
      final period = profile.periodSeconds;
      final slow =
          (profile.isRectangular &&
              ((period != null &&
                      ((meanRiseTime ?? 0) > 0.1 * period ||
                          (meanFallTime ?? 0) > 0.1 * period)) ||
                  (period == null &&
                      profile.durationSeconds > 0 &&
                      ((meanRiseTime ?? 0) > 0.05 * profile.durationSeconds ||
                          (meanFallTime ?? 0) >
                              0.05 * profile.durationSeconds)))) ||
          (asymmetry != null && asymmetry > 50);
      if (slow) {
        return _finding(
          test: WaveformFaultTest.edgeTimes,
          status: WaveformFaultStatus.warning,
          severity: WaveformFaultSeverity.medium,
          summary:
              'The edges are slow or asymmetric (rise '
              '${_formatSeconds(meanRiseTime)}, fall '
              '${_formatSeconds(meanFallTime)}, asymmetry '
              '${_formatPercent(asymmetry)}); no edge-time limit was supplied.',
          measured: measured,
          events: events,
          missingInputs: const [
            'maxRiseTimeSeconds, maxFallTimeSeconds and maxAsymmetryPercent for '
                'a pass/fail verdict',
          ],
        );
      }
      return _finding(
        test: WaveformFaultTest.edgeTimes,
        status: WaveformFaultStatus.informational,
        summary:
            'Rise time is ${_formatSeconds(meanRiseTime)} and fall time is '
            '${_formatSeconds(meanFallTime)}; no edge-time limit was supplied.',
        measured: measured,
        events: events,
        missingInputs: const [
          'maxRiseTimeSeconds, maxFallTimeSeconds and maxAsymmetryPercent for a '
              'pass/fail verdict',
        ],
      );
    }
    return _finding(
      test: WaveformFaultTest.edgeTimes,
      status: WaveformFaultStatus.pass,
      summary:
          'Rise time is ${_formatSeconds(meanRiseTime)} and fall time is '
          '${_formatSeconds(meanFallTime)}, within the specification.',
      measured: measured,
      expected: expected,
      events: events,
    );
  }

  WaveformFaultFinding _amplitudeStability(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final windows = _windowStats(
      profile,
      _windowCount(profile, request.number('windowSeconds')),
    );
    if (windows.length < 4) {
      return _finding(
        test: WaveformFaultTest.amplitudeStability,
        status: WaveformFaultStatus.inconclusive,
        summary:
            'Too few windows were available to evaluate amplitude '
            'stability.',
        measured: {'windowCount': windows.length},
        missingInputs: const ['a longer record'],
      );
    }
    final vpps = [for (final window in windows) window.vPp];
    final meanVpp = _mean(vpps);
    final minVpp = vpps.reduce(math.min);
    final maxVpp = vpps.reduce(math.max);
    final stdVpp = _std(vpps);
    final variationPercent = meanVpp == 0 ? null : stdVpp / meanVpp * 100;
    final rangePercent = meanVpp == 0
        ? null
        : (maxVpp - minVpp) / meanVpp * 100;
    double? modulationFrequency;
    final sampleRate = profile.context.sampleRateHz;
    if (sampleRate != null && windows.length >= 8) {
      final windowRate = windows.length / profile.trace.durationSeconds;
      if (windowRate > 0) {
        final spectrum = computeSpectrum(
          Float64List.fromList(vpps),
          windowRate,
        );
        modulationFrequency = spectrum.dominantFrequency;
      }
    }
    final measured = <String, dynamic>{
      'windowCount': windows.length,
      'meanWindowVppVolts': _finite(meanVpp),
      'minWindowVppVolts': _finite(minVpp),
      'maxWindowVppVolts': _finite(maxVpp),
      'stdWindowVppVolts': _finite(stdVpp),
      'amplitudeVariationPercent': _finite(variationPercent),
      'amplitudeRangePercent': _finite(rangePercent),
      'modulationFrequencyHz': _finite(modulationFrequency),
    };
    final maxVariation = request.number('maxAmplitudeVariationPercent');
    final expected = <String, dynamic>{
      if (maxVariation != null)
        'maxAmplitudeVariationPercent': _finite(maxVariation),
    };
    final events = [
      for (final window in [windows.first, windows.last])
        {
          'startSeconds': _finite(window.startSeconds),
          'endSeconds': _finite(window.endSeconds),
          'vppVolts': _finite(window.vPp),
        },
    ];
    final violated =
        maxVariation != null &&
        rangePercent != null &&
        rangePercent > maxVariation;
    if (violated) {
      return _finding(
        test: WaveformFaultTest.amplitudeStability,
        status: WaveformFaultStatus.fail,
        severity: _severityForRatio(rangePercent / maxVariation),
        summary:
            'The amplitude varies by ${_formatPercent(rangePercent)} '
            '(${_formatVolts(minVpp)} to ${_formatVolts(maxVpp)}), above the '
            'allowed ${_formatPercent(maxVariation)}.',
        measured: measured,
        expected: expected,
        events: events,
      );
    }
    if (expected.isEmpty) {
      if ((rangePercent ?? 0) > 20 || (variationPercent ?? 0) > 10) {
        return _finding(
          test: WaveformFaultTest.amplitudeStability,
          status: WaveformFaultStatus.warning,
          severity: (rangePercent ?? 0) > 50
              ? WaveformFaultSeverity.high
              : WaveformFaultSeverity.medium,
          summary:
              'The amplitude varies by ${_formatPercent(rangePercent)}; no '
              'allowed amplitude variation was supplied.',
          measured: measured,
          events: events,
          missingInputs: const [
            'maxAmplitudeVariationPercent for a pass/fail verdict',
          ],
        );
      }
      return _finding(
        test: WaveformFaultTest.amplitudeStability,
        status: WaveformFaultStatus.informational,
        summary:
            'The amplitude varies by ${_formatPercent(rangePercent)}; no '
            'allowed amplitude variation was supplied.',
        measured: measured,
        events: events,
        missingInputs: const [
          'maxAmplitudeVariationPercent for a pass/fail verdict',
        ],
      );
    }
    return _finding(
      test: WaveformFaultTest.amplitudeStability,
      status: WaveformFaultStatus.pass,
      summary:
          'The amplitude varies by ${_formatPercent(rangePercent)}, within the '
          'specification.',
      measured: measured,
      expected: expected,
      events: events,
    );
  }

  WaveformFaultFinding _settling(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    if (profile.periods.length >= 3 &&
        request.number('edgeTimeSeconds') == null) {
      return _finding(
        test: WaveformFaultTest.settling,
        status: WaveformFaultStatus.notApplicable,
        summary:
            'The signal is a steady periodic waveform; no single settling '
            'event was identified.',
        measured: {'periodCount': profile.periods.length},
      );
    }
    final requestedEdgeTime = request.number('edgeTimeSeconds');
    _Edge? edge;
    if (requestedEdgeTime != null) {
      edge = _nearestEdge(profile.edges, requestedEdgeTime);
    } else {
      var largestChange = 0.0;
      for (final candidate in profile.edges) {
        final pre = _meanRange(
          profile.volts,
          math.max(0, candidate.index - 10),
          math.max(0, candidate.index - 1),
        );
        final post = _meanRange(
          profile.volts,
          candidate.index + 1,
          math.min(profile.length - 1, candidate.index + 10),
        );
        final change = (post - pre).abs();
        if (change > largestChange) {
          largestChange = change;
          edge = candidate;
        }
      }
    }
    if (edge == null) {
      return _finding(
        test: WaveformFaultTest.settling,
        status: WaveformFaultStatus.inconclusive,
        summary: 'No step or edge was found for the settling analysis.',
        measured: const {},
        missingInputs: const ['edgeTimeSeconds'],
      );
    }
    final nextEdge = _nextEdge(profile.edges, edge);
    final searchEndIndex = nextEdge?.index ?? profile.length - 1;
    if (searchEndIndex - edge.index < 8) {
      return _finding(
        test: WaveformFaultTest.settling,
        status: WaveformFaultStatus.inconclusive,
        summary:
            'The settling window after the edge is too short to measure a '
            'settling time.',
        measured: {'edgeTimeSeconds': _finite(edge.time)},
        missingInputs: const ['a longer record or edgeTimeSeconds'],
      );
    }
    final preLevel = _meanRange(
      profile.volts,
      math.max(0, edge.index - 10),
      math.max(0, edge.index - 1),
    );
    final postStart = math
        .max(
          edge.index,
          searchEndIndex - math.max(5, (searchEndIndex - edge.index) ~/ 10),
        )
        .toInt();
    final postLevel = _meanRange(profile.volts, postStart, searchEndIndex);
    final step = postLevel - preLevel;
    final minimumStep = math.max(4 * profile.noiseRms, 0.02 * profile.vPp);
    if (step.abs() < minimumStep) {
      return _finding(
        test: WaveformFaultTest.settling,
        status: WaveformFaultStatus.inconclusive,
        summary:
            'The detected transition of ${_formatVolts(step)} is too small '
            'for a reliable settling measurement.',
        measured: {
          'stepVolts': _finite(step),
          'preLevelVolts': _finite(preLevel),
          'postLevelVolts': _finite(postLevel),
        },
      );
    }
    final bandPercent = request.number('settlingBandPercent') ?? 2;
    final band = bandPercent / 100 * step.abs();
    var lastOutside = edge.index;
    for (var index = edge.index + 1; index <= searchEndIndex; index++) {
      if ((profile.volts[index] - postLevel).abs() > band) {
        lastOutside = index;
      }
    }
    final settlingIndex = math.min(profile.length - 1, lastOutside + 1);
    final settlingTime = profile.times[settlingIndex] - edge.time;
    var overshoot = 0.0;
    if (step > 0) {
      var peak = postLevel;
      for (var index = edge.index; index <= settlingIndex; index++) {
        if (profile.volts[index] > peak) peak = profile.volts[index];
      }
      overshoot = (peak - postLevel) / step.abs() * 100;
    } else {
      var trough = postLevel;
      for (var index = edge.index; index <= settlingIndex; index++) {
        if (profile.volts[index] < trough) trough = profile.volts[index];
      }
      overshoot = (postLevel - trough) / step.abs() * 100;
    }
    final measured = <String, dynamic>{
      'edgeTimeSeconds': _finite(edge.time),
      'settlingTimeSeconds': _finite(settlingTime),
      'overshootPercent': _finite(overshoot),
      'settlingBandPercent': _finite(bandPercent),
      'bandVolts': _finite(band),
      'stepVolts': _finite(step),
      'preLevelVolts': _finite(preLevel),
      'postLevelVolts': _finite(postLevel),
    };
    final maxSettlingTime = request.number('maxSettlingTimeSeconds');
    final maxOvershoot = request.number('maxOvershootPercent');
    final expected = <String, dynamic>{
      if (maxSettlingTime != null)
        'maxSettlingTimeSeconds': _finite(maxSettlingTime),
      if (maxOvershoot != null) 'maxOvershootPercent': _finite(maxOvershoot),
      if (request.number('settlingBandPercent') != null)
        'settlingBandPercent': _finite(bandPercent),
    };
    final violated =
        (maxSettlingTime != null && settlingTime > maxSettlingTime) ||
        (maxOvershoot != null && overshoot > maxOvershoot);
    if (violated) {
      return _finding(
        test: WaveformFaultTest.settling,
        status: WaveformFaultStatus.fail,
        severity: maxSettlingTime != null && settlingTime > maxSettlingTime
            ? _severityForRatio(settlingTime / maxSettlingTime)
            : WaveformFaultSeverity.high,
        summary:
            'The signal settles in ${_formatSeconds(settlingTime)} with '
            '${_formatPercent(overshoot)} overshoot, outside the specification.',
        measured: measured,
        expected: expected,
      );
    }
    if (expected.isEmpty) {
      if (overshoot > 20 ||
          settlingTime > 0.25 * profile.trace.durationSeconds) {
        return _finding(
          test: WaveformFaultTest.settling,
          status: WaveformFaultStatus.warning,
          severity: WaveformFaultSeverity.medium,
          summary:
              'The signal settles in ${_formatSeconds(settlingTime)} with '
              '${_formatPercent(overshoot)} overshoot; no settling limit was '
              'supplied.',
          measured: measured,
          missingInputs: const [
            'maxSettlingTimeSeconds and maxOvershootPercent for a pass/fail '
                'verdict',
          ],
        );
      }
      return _finding(
        test: WaveformFaultTest.settling,
        status: WaveformFaultStatus.informational,
        summary:
            'The signal settles in ${_formatSeconds(settlingTime)} with '
            '${_formatPercent(overshoot)} overshoot; no settling limit was '
            'supplied.',
        measured: measured,
        missingInputs: const [
          'maxSettlingTimeSeconds and maxOvershootPercent for a pass/fail '
              'verdict',
        ],
      );
    }
    return _finding(
      test: WaveformFaultTest.settling,
      status: WaveformFaultStatus.pass,
      summary:
          'The signal settles in ${_formatSeconds(settlingTime)} with '
          '${_formatPercent(overshoot)} overshoot, within the specification.',
      measured: measured,
      expected: expected,
    );
  }

  WaveformFaultFinding _phaseDelay(
    WaveformFaultRequest request,
    WaveformFaultContext context,
    _SignalProfile profile,
  ) {
    final secondTrace = context.secondTrace;
    if (secondTrace == null || secondTrace.isEmpty) {
      return _finding(
        test: WaveformFaultTest.phaseDelay,
        status: WaveformFaultStatus.inconclusive,
        summary:
            'A second acquired channel is required for the phase/delay '
            'analysis.',
        measured: const {},
        missingInputs: const ['channelB'],
      );
    }
    final secondProfile = _SignalProfile.from(
      WaveformFaultContext(
        trace: secondTrace,
        channel: context.secondChannel ?? 'ch2',
        sampleRateHz: context.sampleRateHz,
        timebaseSecondsPerDiv: context.timebaseSecondsPerDiv,
        adcBits: context.adcBits,
        probeAttenuation: context.probeAttenuation,
        probeAttenuationAssumed: context.probeAttenuationAssumed,
        triggerLevelVolts: context.triggerLevelVolts,
        triggerPosition: context.triggerPosition,
        triggerDelaySeconds: context.triggerDelaySeconds,
      ),
    );
    final matches = _matchRisingEdges(profile, secondProfile);
    if (matches.isEmpty) {
      return _finding(
        test: WaveformFaultTest.phaseDelay,
        status: WaveformFaultStatus.inconclusive,
        summary:
            'No matching edges were found between ${context.channel} and '
            '${context.secondChannel ?? 'the second channel'}.',
        measured: {
          'channelBEdgeCount': secondProfile.risingEdges.length,
          'channelAEdgeCount': profile.risingEdges.length,
        },
        missingInputs: const ['two channels with a common periodic signal'],
      );
    }
    final delays = [for (final match in matches) match.delaySeconds];
    final delay = _median(delays);
    final dt = profile.dt;
    final lagSamples = dt == null || dt <= 0 ? 0 : (delay / dt).round();
    final correlation = _correlationAtLag(
      profile.volts,
      secondProfile.volts,
      lagSamples,
    );
    final fundamental = profile.fundamentalHz ?? secondProfile.fundamentalHz;
    final phaseDegrees = fundamental == null
        ? null
        : _wrapDegrees(360 * fundamental * delay);
    final measured = <String, dynamic>{
      'delaySeconds': _finite(delay),
      'delayMicroseconds': _finite(delay * 1e6),
      'phaseDegrees': _finite(phaseDegrees),
      'correlation': _finite(correlation),
      'matchedEdgeCount': matches.length,
      'channelBEdgeCount': secondProfile.risingEdges.length,
    };
    final expectedDelaySeconds =
        request.number('expectedDelaySeconds') ??
        (request.number('expectedDelayMicroseconds') == null
            ? null
            : request.number('expectedDelayMicroseconds')! * 1e-6);
    final toleranceDelay =
        request.number('toleranceDelaySeconds') ??
        (request.number('toleranceDelayMicroseconds') == null
            ? null
            : request.number('toleranceDelayMicroseconds')! * 1e-6);
    final expectedPhase = request.number('expectedPhaseDegrees');
    final tolerancePhase = request.number('tolerancePhaseDegrees');
    final expected = <String, dynamic>{
      if (expectedDelaySeconds != null)
        'delaySeconds': _finite(expectedDelaySeconds),
      if (toleranceDelay != null)
        'toleranceDelaySeconds': _finite(toleranceDelay),
      if (expectedPhase != null) 'phaseDegrees': _finite(expectedPhase),
      if (tolerancePhase != null)
        'tolerancePhaseDegrees': _finite(tolerancePhase),
    };
    final missing = expected.isEmpty
        ? const [
            'expectedDelaySeconds or expectedPhaseDegrees and a tolerance for '
                'a pass/fail verdict',
          ]
        : const <String>[];
    final delayViolated =
        expectedDelaySeconds != null &&
        toleranceDelay != null &&
        (delay - expectedDelaySeconds).abs() > toleranceDelay;
    if ((expectedDelaySeconds != null && toleranceDelay == null) ||
        (expectedPhase != null && tolerancePhase == null)) {
      return _finding(
        test: WaveformFaultTest.phaseDelay,
        status: WaveformFaultStatus.inconclusive,
        summary: 'A delay or phase reference was supplied without a tolerance.',
        measured: measured,
        expected: expected,
        missingInputs: const [
          'toleranceDelaySeconds or tolerancePhaseDegrees for the supplied '
              'reference',
        ],
      );
    }
    final phaseDifference = expectedPhase == null || phaseDegrees == null
        ? null
        : _wrapDegrees(phaseDegrees - expectedPhase);
    final phaseViolated =
        phaseDifference != null &&
        tolerancePhase != null &&
        phaseDifference.abs() > tolerancePhase;
    final events = [
      for (final match in matches.take(10))
        {
          'timeSeconds': _finite(match.referenceTimeSeconds),
          'delaySeconds': _finite(match.delaySeconds),
        },
    ];
    if (delayViolated || phaseViolated) {
      return _finding(
        test: WaveformFaultTest.phaseDelay,
        status: WaveformFaultStatus.fail,
        severity: delayViolated
            ? _severityForRatio(
                (delay - expectedDelaySeconds).abs() / toleranceDelay,
              )
            : WaveformFaultSeverity.high,
        summary:
            'The delay is ${_formatSeconds(delay)} '
            '(${_formatDegrees(phaseDegrees)}), outside the specification.',
        measured: measured,
        expected: expected,
        deviation: {
          'delaySeconds': _finite(
            expectedDelaySeconds == null ? null : delay - expectedDelaySeconds,
          ),
          'phaseDegrees': _finite(phaseDifference),
        },
        events: events,
      );
    }
    if (expected.isEmpty) {
      return _finding(
        test: WaveformFaultTest.phaseDelay,
        status: WaveformFaultStatus.informational,
        summary:
            'The delay is ${_formatSeconds(delay)} '
            '(${_formatDegrees(phaseDegrees)}); no expected delay or phase '
            'was supplied.',
        measured: measured,
        events: events,
        missingInputs: missing,
        limitations: fundamental == null
            ? const [
                'The fundamental frequency is unknown, so no phase angle was '
                    'computed.',
              ]
            : const <String>[],
      );
    }
    return _finding(
      test: WaveformFaultTest.phaseDelay,
      status: WaveformFaultStatus.pass,
      summary:
          'The delay is ${_formatSeconds(delay)} '
          '(${_formatDegrees(phaseDegrees)}), within the specification.',
      measured: measured,
      expected: expected,
      events: events,
    );
  }

  WaveformFaultFinding _crosstalk(
    WaveformFaultRequest request,
    WaveformFaultContext context,
    _SignalProfile profile,
  ) {
    final secondTrace = context.secondTrace;
    if (secondTrace == null || secondTrace.isEmpty) {
      return _finding(
        test: WaveformFaultTest.crosstalk,
        status: WaveformFaultStatus.inconclusive,
        summary:
            'A second acquired channel is required for the crosstalk '
            'analysis.',
        measured: const {},
        missingInputs: const ['channelB'],
      );
    }
    final secondProfile = _SignalProfile.from(
      WaveformFaultContext(
        trace: secondTrace,
        channel: context.secondChannel ?? 'ch2',
        sampleRateHz: context.sampleRateHz,
        timebaseSecondsPerDiv: context.timebaseSecondsPerDiv,
        adcBits: context.adcBits,
        probeAttenuation: context.probeAttenuation,
        probeAttenuationAssumed: context.probeAttenuationAssumed,
        triggerLevelVolts: context.triggerLevelVolts,
        triggerPosition: context.triggerPosition,
        triggerDelaySeconds: context.triggerDelaySeconds,
      ),
    );
    final dt = profile.dt ?? 1;
    final edgeCount = profile.edges.length;
    if (edgeCount == 0) {
      return _finding(
        test: WaveformFaultTest.crosstalk,
        status: WaveformFaultStatus.inconclusive,
        summary:
            'No switching edges were found on ${context.channel}; crosstalk '
            'cannot be correlated with an aggressor event.',
        measured: {'channelBEdgeCount': secondProfile.edges.length},
      );
    }
    final halfWindowSamples = math.max(
      2,
      ((profile.periodSeconds != null
                  ? 0.02 * profile.periodSeconds!
                  : 0.01 * profile.trace.durationSeconds) /
              dt)
          .round(),
    );
    final activeMask = Int32List(profile.length + 1);
    for (final edge in profile.edges) {
      final start = math.max(0, edge.index - halfWindowSamples);
      final end = math.min(profile.length, edge.index + halfWindowSamples + 1);
      activeMask[start] += 1;
      activeMask[end] -= 1;
    }
    var activeCount = 0;
    var quietCount = 0;
    var activeSum = 0.0;
    var quietSum = 0.0;
    var activePeak = 0.0;
    var quietPeak = 0.0;
    var activeLevel = 0;
    for (var index = 0; index < profile.length; index++) {
      activeLevel += activeMask[index];
      final value = secondProfile.volts[index];
      if (activeLevel > 0) {
        activeCount++;
        activeSum += value * value;
        final absolute = value.abs();
        if (absolute > activePeak) activePeak = absolute;
      } else {
        quietCount++;
        quietSum += value * value;
        final absolute = value.abs();
        if (absolute > quietPeak) quietPeak = absolute;
      }
    }
    final activeRms = activeCount == 0
        ? 0.0
        : math.sqrt(activeSum / activeCount);
    final quietRms = quietCount == 0 ? 0.0 : math.sqrt(quietSum / quietCount);
    final aggressorAmplitude = profile.vPp;
    final couplingAmplitude = math.max(0.0, activePeak - quietPeak);
    final couplingRatio = aggressorAmplitude <= 0
        ? null
        : couplingAmplitude / aggressorAmplitude;
    final couplingDb = couplingRatio == null || couplingRatio <= 0
        ? null
        : 20 * math.log(couplingRatio) / math.ln10;
    final correlation = _correlationAtLag(
      profile.volts,
      secondProfile.volts,
      0,
    );
    final aggressorFundamental = profile.fundamentalHz;
    final victimAtAggressor = aggressorFundamental == null
        ? null
        : secondProfile.spectrum?.amplitudeNear(
            aggressorFundamental,
            binTolerance: 2,
          );
    final measured = <String, dynamic>{
      'activeWindowRmsVolts': _finite(activeRms),
      'quietWindowRmsVolts': _finite(quietRms),
      'activePeakVolts': _finite(activePeak),
      'quietPeakVolts': _finite(quietPeak),
      'couplingAmplitudeVolts': _finite(couplingAmplitude),
      'couplingRatio': _finite(couplingRatio),
      'couplingPercent': _finite(
        couplingRatio == null ? null : couplingRatio * 100,
      ),
      'couplingDb': _finite(couplingDb),
      'aggressorFundamentalHz': _finite(aggressorFundamental),
      'victimAmplitudeAtAggressorVolts': _finite(victimAtAggressor),
      'zeroLagCorrelation': _finite(correlation),
      'aggressorEdgeCount': profile.edges.length,
    };
    final maxCrosstalkDb = request.number('maxCrosstalkDb');
    final maxCrosstalkPercent = request.number('maxCrosstalkPercent');
    final expected = <String, dynamic>{
      if (maxCrosstalkDb != null) 'maxCrosstalkDb': _finite(maxCrosstalkDb),
      if (maxCrosstalkPercent != null)
        'maxCrosstalkPercent': _finite(maxCrosstalkPercent),
    };
    final ratioPercent = couplingRatio == null ? null : couplingRatio * 100;
    final violated =
        (maxCrosstalkDb != null &&
            couplingDb != null &&
            couplingDb > maxCrosstalkDb) ||
        (maxCrosstalkPercent != null &&
            ratioPercent != null &&
            ratioPercent > maxCrosstalkPercent);
    final events = _crosstalkEvents(profile, secondProfile);
    if (violated) {
      return _finding(
        test: WaveformFaultTest.crosstalk,
        status: WaveformFaultStatus.fail,
        severity: maxCrosstalkPercent != null && ratioPercent != null
            ? _severityForRatio(ratioPercent / maxCrosstalkPercent)
            : WaveformFaultSeverity.high,
        summary:
            '${context.secondChannel ?? 'The second channel'} shows '
            '${_formatDb(couplingDb)} coupling at the switching edges of '
            '${context.channel}.',
        measured: measured,
        expected: expected,
        events: events,
      );
    }
    if (expected.isEmpty) {
      if (couplingDb != null && couplingDb > -40) {
        return _finding(
          test: WaveformFaultTest.crosstalk,
          status: WaveformFaultStatus.warning,
          severity: couplingDb > -20
              ? WaveformFaultSeverity.high
              : WaveformFaultSeverity.medium,
          summary:
              '${context.secondChannel ?? 'The second channel'} shows '
              '${_formatDb(couplingDb)} coupling at the switching edges of '
              '${context.channel}; no coupling limit was supplied.',
          measured: measured,
          events: events,
          missingInputs: const [
            'maxCrosstalkDb or maxCrosstalkPercent for a pass/fail verdict',
          ],
          limitations: (correlation ?? 0).abs() > 0.9
              ? const [
                  'The channels are strongly correlated; crosstalk cannot be '
                      'separated from a legitimate common signal.',
                ]
              : const <String>[],
        );
      }
      return _finding(
        test: WaveformFaultTest.crosstalk,
        status: WaveformFaultStatus.informational,
        summary: couplingDb == null
            ? 'No edge-synchronous excess activity was detected on '
                  '${context.secondChannel ?? 'the second channel'}.'
            : '${context.secondChannel ?? 'The second channel'} shows '
                  '${_formatDb(couplingDb)} coupling at the switching edges of '
                  '${context.channel}; no coupling limit was supplied.',
        measured: measured,
        events: events,
        missingInputs: const [
          'maxCrosstalkDb or maxCrosstalkPercent for a pass/fail verdict',
        ],
      );
    }
    return _finding(
      test: WaveformFaultTest.crosstalk,
      status: WaveformFaultStatus.pass,
      summary: couplingDb == null
          ? 'No edge-synchronous excess activity was detected on '
                '${context.secondChannel ?? 'the second channel'}.'
          : '${context.secondChannel ?? 'The second channel'} shows '
                '${_formatDb(couplingDb)} coupling, within the specification.',
      measured: measured,
      expected: expected,
      events: events,
    );
  }

  WaveformFaultFinding _intermittent(
    WaveformFaultRequest request,
    _SignalProfile profile,
  ) {
    final events = _intermittentEvents(profile);
    final periodCount = profile.periods.length;
    final countsByType = <String, int>{};
    for (final event in events) {
      countsByType[event.type] = (countsByType[event.type] ?? 0) + 1;
    }
    final eventsPerSecond = profile.trace.durationSeconds > 0
        ? events.length / profile.trace.durationSeconds
        : null;
    final eventsPerMillionPeriods = periodCount > 0
        ? events.length / periodCount * 1e6
        : null;
    final measured = <String, dynamic>{
      'eventCount': events.length,
      'countsByType': countsByType,
      'eventsPerSecond': _finite(eventsPerSecond),
      'eventsPerMillionPeriods': _finite(eventsPerMillionPeriods),
      'observedPeriods': periodCount,
      'observedSeconds': _finite(profile.trace.durationSeconds),
    };
    final maxEventCount = request.integer('maxEventCount');
    final maxPerMillion = request.number('maxEventsPerMillionPeriods');
    final expected = <String, dynamic>{
      'maxEventCount': ?maxEventCount,
      if (maxPerMillion != null)
        'maxEventsPerMillionPeriods': _finite(maxPerMillion),
    };
    final reportEvents = [
      for (final event in events.take(20))
        {
          'type': event.type,
          'startSeconds': _finite(event.startSeconds),
          'durationSeconds': _finite(event.durationSeconds),
          if (event.value != null) 'value': _finite(event.value),
          if (event.unit != null) 'unit': event.unit,
        },
    ];
    final violated =
        (maxEventCount != null && events.length > maxEventCount) ||
        (maxPerMillion != null &&
            eventsPerMillionPeriods != null &&
            eventsPerMillionPeriods > maxPerMillion);
    if (violated) {
      return _finding(
        test: WaveformFaultTest.intermittent,
        status: WaveformFaultStatus.fail,
        severity: WaveformFaultSeverity.high,
        summary:
            '${events.length} intermittent event(s) were found in '
            '${_formatSeconds(profile.trace.durationSeconds)}, above the '
            'specified event rate.',
        measured: measured,
        expected: expected,
        events: reportEvents,
      );
    }
    if (expected.isEmpty) {
      if (events.isNotEmpty) {
        return _finding(
          test: WaveformFaultTest.intermittent,
          status: WaveformFaultStatus.warning,
          severity: WaveformFaultSeverity.medium,
          summary:
              '${events.length} intermittent event(s) were found in '
              '${_formatSeconds(profile.trace.durationSeconds)}; no allowed '
              'event rate was supplied.',
          measured: measured,
          events: reportEvents,
          missingInputs: const [
            'maxEventCount or maxEventsPerMillionPeriods for a pass/fail '
                'verdict',
          ],
          limitations: periodCount < 10
              ? const [
                  'The record covers fewer than ten periods; rare intermittent '
                      'faults may be missed.',
                ]
              : const <String>[],
        );
      }
      return _finding(
        test: WaveformFaultTest.intermittent,
        status: WaveformFaultStatus.informational,
        summary:
            'No intermittent event was found in '
            '${_formatSeconds(profile.trace.durationSeconds)}; no allowed '
            'event rate was supplied.',
        measured: measured,
        missingInputs: const [
          'maxEventCount or maxEventsPerMillionPeriods for a pass/fail verdict',
          'a longer recording for rare events',
        ],
        limitations: periodCount < 10
            ? const [
                'The record covers fewer than ten periods; rare intermittent '
                    'faults may be missed.',
              ]
            : const <String>[],
      );
    }
    return _finding(
      test: WaveformFaultTest.intermittent,
      status: WaveformFaultStatus.pass,
      summary:
          'No intermittent event exceeds the specification in '
          '${_formatSeconds(profile.trace.durationSeconds)}.',
      measured: measured,
      expected: expected,
      events: reportEvents,
    );
  }

  WaveformFaultFinding _measurementArtifacts(
    WaveformFaultContext context,
    _SignalProfile profile,
  ) {
    final limitations = <String>{};
    final critical = <String>[];
    final measured = <String, dynamic>{
      'sampleRateHz': _finite(context.sampleRateHz),
      'adcBits': context.adcBits,
      'quantizationStepVolts': _finite(profile.lsb),
      'probeAttenuation': _finite(context.probeAttenuation),
      'probeAttenuationAssumed': context.probeAttenuationAssumed,
      'triggerPosition': context.triggerPosition,
      'leadingSamplesExcluded': context.leadingSamplesExcluded,
      'sampleCount': context.trace.length,
      'durationSeconds': _finite(context.trace.durationSeconds),
    };
    final sampleRate = context.sampleRateHz;
    if (sampleRate == null || sampleRate <= 0) {
      critical.add(
        'The sample rate is unknown; time and frequency values are '
        'not calibrated.',
      );
    } else {
      measured['nyquistHz'] = sampleRate / 2;
      final dominant = profile.spectrum?.dominantFrequency;
      if (dominant != null && dominant > 0.4 * sampleRate) {
        critical.add(
          'The dominant frequency (${_formatHz(dominant)}) is close to the '
          'Nyquist frequency (${_formatHz(sampleRate / 2)}); aliasing may '
          'explain the observed component.',
        );
      }
      final fundamental = profile.fundamentalHz;
      if (fundamental != null && fundamental > 0) {
        final samplesPerPeriod = sampleRate / fundamental;
        measured['samplesPerPeriod'] = samplesPerPeriod;
        if (samplesPerPeriod < 10) {
          limitations.add(
            'Only ${samplesPerPeriod.toStringAsFixed(1)} samples per period '
            'are available; rise/fall time and jitter results are limited.',
          );
        }
        final recordPeriods = context.trace.durationSeconds * fundamental;
        measured['recordPeriods'] = recordPeriods;
        if (recordPeriods < 2) {
          limitations.add(
            'The record covers only ${recordPeriods.toStringAsFixed(2)} '
            'periods; frequency and jitter results are unreliable.',
          );
        }
      }
    }
    final lsb = profile.lsb;
    if (lsb != null && lsb > 0) {
      measured['signalCodes'] = profile.vPp / lsb;
      if (profile.vPp / lsb < 20) {
        limitations.add(
          'The signal spans fewer than 20 ADC codes; quantization dominates '
          'the measurement.',
        );
      }
      if (profile.noiseRms < 1.5 * lsb) {
        limitations.add(
          'The measured noise is close to the quantization step '
          '(${_formatVolts(lsb)}); the noise result is resolution-limited.',
        );
      }
      final vdiv = context.verticalScaleVoltsPerDiv;
      if (vdiv != null && vdiv > 0 && context.adcBits >= 4) {
        final offset = context.verticalOffsetVolts ?? 0;
        final maximumCode =
            (math.pow(2, context.adcBits - 1).toDouble() - 1) * lsb - offset;
        final minimumCode =
            -math.pow(2, context.adcBits - 1).toDouble() * lsb - offset;
        var saturated = 0;
        for (final value in profile.volts) {
          if (value >= maximumCode - 0.5 * lsb ||
              value <= minimumCode + 0.5 * lsb) {
            saturated++;
          }
        }
        measured['adcSaturatedSamples'] = saturated;
        measured['adcFullScaleHighVolts'] = maximumCode;
        measured['adcFullScaleLowVolts'] = minimumCode;
        if (saturated > 0.001 * profile.length) {
          critical.add(
            '$saturated samples reach the ADC full scale; the acquisition is '
            'clipped and amplitude results are affected.',
          );
        }
      }
    }
    if (context.probeAttenuationAssumed) {
      limitations.add(
        'The probe attenuation was assumed to be 1:1; absolute voltage values '
        'may be scaled differently by the probe.',
      );
    }
    if (context.triggerPosition <= 0) {
      limitations.add(
        'The trigger position is unknown; pre-trigger and settling analysis '
        'are limited.',
      );
    }
    if (context.leadingSamplesExcluded > 0) {
      limitations.add(
        '${context.leadingSamplesExcluded} leading samples were excluded as a '
        'known acquisition artifact.',
      );
    }
    final dt = profile.dt;
    if (dt != null && dt > 0 && profile.times.length > 2) {
      var nonUniform = false;
      final limit = math.min(profile.times.length - 1, 1000);
      for (var index = 0; index < limit; index++) {
        final step = profile.times[index + 1] - profile.times[index];
        if ((step - dt).abs() > 0.1 * dt) {
          nonUniform = true;
          break;
        }
      }
      if (nonUniform) {
        limitations.add(
          'The sample spacing is not uniform; time-based results may be '
          'inaccurate.',
        );
      }
    }
    if (profile.vPp <= math.max(2 * (lsb ?? 0), 1e-12)) {
      critical.add(
        'The signal is a flat line; amplitude, distortion and frequency '
        'results are not meaningful.',
      );
    }
    limitations.addAll(critical);
    final status = critical.isEmpty
        ? WaveformFaultStatus.informational
        : WaveformFaultStatus.warning;
    return _finding(
      test: WaveformFaultTest.measurementArtifacts,
      status: status,
      severity: critical.isEmpty
          ? WaveformFaultSeverity.none
          : WaveformFaultSeverity.medium,
      summary: critical.isEmpty
          ? 'No measurement artifact was detected.'
          : '${critical.length} measurement artifact(s) may affect the '
                'diagnosis.',
      measured: measured,
      missingInputs: context.probeAttenuationAssumed
          ? const ['probeAttenuation for absolute voltage scaling']
          : const <String>[],
      limitations: limitations.toList(),
    );
  }
}

/// Signal profile shared by the individual tests.
class _SignalProfile {
  const _SignalProfile({
    required this.context,
    required this.volts,
    required this.times,
    required this.sortedVolts,
    required this.dt,
    required this.vMin,
    required this.vMax,
    required this.vPp,
    required this.vMean,
    required this.vRms,
    required this.vStd,
    required this.lowLevel,
    required this.highLevel,
    required this.midLevel,
    required this.amplitude,
    required this.lsb,
    required this.noiseRms,
    required this.edges,
    required this.periods,
    required this.periodSeconds,
    required this.fundamentalHz,
    required this.spectrum,
    required this.isRectangular,
    required this.limitations,
  });

  factory _SignalProfile.from(WaveformFaultContext context) {
    final trace = context.trace;
    final volts = trace.volts;
    final times = trace.times;
    final length = volts.length;
    final limitations = <String>[];
    if (length < 2) {
      return _SignalProfile(
        context: context,
        volts: volts,
        times: times,
        sortedVolts: const [],
        dt: null,
        vMin: 0,
        vMax: 0,
        vPp: 0,
        vMean: 0,
        vRms: 0,
        vStd: 0,
        lowLevel: 0,
        highLevel: 0,
        midLevel: 0,
        amplitude: 0,
        lsb: null,
        noiseRms: 0,
        edges: const [],
        periods: const [],
        periodSeconds: null,
        fundamentalHz: null,
        spectrum: null,
        isRectangular: false,
        limitations: const [
          'The record contains fewer than two valid samples.',
        ],
      );
    }
    var vMin = volts.first;
    var vMax = volts.first;
    var sum = 0.0;
    var sumSquares = 0.0;
    for (final value in volts) {
      if (value < vMin) vMin = value;
      if (value > vMax) vMax = value;
      sum += value;
      sumSquares += value * value;
    }
    final mean = sum / length;
    final variance = math.max(0.0, sumSquares / length - mean * mean);
    final rms = math.sqrt(sumSquares / length);
    final std = math.sqrt(variance);
    final sorted = List<double>.from(volts)..sort();
    final lowLevel = _percentileSorted(sorted, 0.005);
    final highLevel = _percentileSorted(sorted, 0.995);
    final amplitude = highLevel - lowLevel;
    final vPp = vMax - vMin;
    final dt = trace.sampleIntervalSeconds;
    final vdiv = context.verticalScaleVoltsPerDiv;
    final lsb = vdiv == null || vdiv <= 0 ? null : vdiv / 25;
    if (length < 32) {
      limitations.add(
        'The record contains only $length samples; fault analysis is limited.',
      );
    }
    if (vPp <= 0) {
      limitations.add(
        'The signal is a flat line; no shape information is available.',
      );
    }
    if (dt == null || dt <= 0) {
      limitations.add(
        'The sample interval is unavailable; time-based results are not '
        'calibrated.',
      );
    }
    final edges = _detectEdges(volts, times, lowLevel, highLevel);
    final periods = <double>[];
    _Edge? previousRising;
    for (final edge in edges) {
      if (!edge.rising) continue;
      if (previousRising != null) {
        final period = edge.time - previousRising.time;
        if (period > 0 && period.isFinite) periods.add(period);
      }
      previousRising = edge;
    }
    final periodSeconds = periods.isEmpty ? null : _median(periods);
    FftSpectrum? spectrum;
    final sampleRate = context.sampleRateHz;
    if (sampleRate != null && sampleRate > 0 && length >= 16) {
      final centered = Float64List(length);
      for (var index = 0; index < length; index++) {
        centered[index] = volts[index] - mean;
      }
      spectrum = computeSpectrum(centered, sampleRate);
    }
    final dominant = spectrum?.dominantFrequency;
    final fundamentalHz = periodSeconds != null && periodSeconds > 0
        ? 1 / periodSeconds
        : dominant;
    if (fundamentalHz != null &&
        sampleRate != null &&
        sampleRate > 0 &&
        sampleRate / fundamentalHz < 10) {
      limitations.add(
        'Fewer than ten samples per period are available; edge and jitter '
        'results are limited.',
      );
    }
    if (fundamentalHz != null &&
        fundamentalHz > 0 &&
        trace.durationSeconds * fundamentalHz < 2) {
      limitations.add(
        'The record covers less than two periods; frequency and jitter results '
        'are unreliable.',
      );
    }
    final noiseRms = _estimateNoise(volts, periodSeconds, dt, lsb);
    final twoLevel = _twoLevelFraction(sorted, lowLevel, highLevel);
    final isRectangular = twoLevel >= 0.85 && amplitude >= 0.5 * vPp;
    if (context.leadingSamplesExcluded > 0) {
      limitations.add(
        '${context.leadingSamplesExcluded} leading samples were excluded as a '
        'known acquisition artifact.',
      );
    }
    return _SignalProfile(
      context: context,
      volts: volts,
      times: times,
      sortedVolts: sorted,
      dt: dt,
      vMin: vMin,
      vMax: vMax,
      vPp: vPp,
      vMean: mean,
      vRms: rms,
      vStd: std,
      lowLevel: lowLevel,
      highLevel: highLevel,
      midLevel: (lowLevel + highLevel) / 2,
      amplitude: amplitude,
      lsb: lsb,
      noiseRms: noiseRms,
      edges: edges,
      periods: periods,
      periodSeconds: periodSeconds,
      fundamentalHz: fundamentalHz,
      spectrum: spectrum,
      isRectangular: isRectangular,
      limitations: limitations,
    );
  }

  final WaveformFaultContext context;
  final Float64List volts;
  final Float64List times;
  final List<double> sortedVolts;
  final double? dt;
  final double vMin;
  final double vMax;
  final double vPp;
  final double vMean;
  final double vRms;
  final double vStd;
  final double lowLevel;
  final double highLevel;
  final double midLevel;
  final double amplitude;
  final double? lsb;
  final double noiseRms;
  final List<_Edge> edges;
  final List<double> periods;
  final double? periodSeconds;
  final double? fundamentalHz;
  final FftSpectrum? spectrum;
  final bool isRectangular;
  final List<String> limitations;

  int get length => volts.length;
  WaveformTrace get trace => context.trace;
  double get durationSeconds => context.trace.durationSeconds;
  List<_Edge> get risingEdges => [
    for (final edge in edges)
      if (edge.rising) edge,
  ];
  List<_Edge> get fallingEdges => [
    for (final edge in edges)
      if (!edge.rising) edge,
  ];
}

class _Edge {
  const _Edge({required this.index, required this.time, required this.rising});

  final int index;
  final double time;
  final bool rising;
}

class _WindowStats {
  const _WindowStats({
    required this.startSeconds,
    required this.endSeconds,
    required this.vPp,
    required this.vRms,
    required this.vMean,
  });

  final double startSeconds;
  final double endSeconds;
  final double vPp;
  final double vRms;
  final double vMean;
}

class _SpikeEvent {
  const _SpikeEvent({
    required this.startSeconds,
    required this.peakSeconds,
    required this.amplitudeVolts,
    required this.widthSeconds,
  });

  final double startSeconds;
  final double peakSeconds;
  final double amplitudeVolts;
  final double widthSeconds;
}

class _RunEvent {
  const _RunEvent({
    required this.high,
    required this.startIndex,
    required this.endIndex,
    required this.startSeconds,
    required this.endSeconds,
    required this.levelVolts,
  });

  final bool high;
  final int startIndex;
  final int endIndex;
  final double startSeconds;
  final double endSeconds;
  final double levelVolts;

  int get sampleCount => endIndex - startIndex + 1;
  double get widthSeconds => endSeconds - startSeconds;
}

class _RingingEvent {
  const _RingingEvent({
    required this.startSeconds,
    required this.amplitudeVolts,
    required this.frequencyHz,
    required this.decayRatePerSecond,
    required this.durationSeconds,
  });

  final double startSeconds;
  final double amplitudeVolts;
  final double? frequencyHz;
  final double? decayRatePerSecond;
  final double durationSeconds;
}

class _SpectrumPeak {
  const _SpectrumPeak({
    required this.frequencyHz,
    required this.amplitudeVolts,
    required this.dbc,
  });

  final double frequencyHz;
  final double amplitudeVolts;
  final double? dbc;
}

class _EdgeDuration {
  const _EdgeDuration({
    required this.timeSeconds,
    required this.seconds,
    required this.rising,
  });

  final double timeSeconds;
  final double seconds;
  final bool rising;
}

class _EdgeDurations {
  const _EdgeDurations({required this.rise, required this.fall});

  final List<_EdgeDuration> rise;
  final List<_EdgeDuration> fall;
}

class _DelayMatch {
  const _DelayMatch({
    required this.referenceTimeSeconds,
    required this.delaySeconds,
  });

  final double referenceTimeSeconds;
  final double delaySeconds;
}

class _IntermittentEvent {
  const _IntermittentEvent({
    required this.type,
    required this.startSeconds,
    required this.durationSeconds,
    this.value,
    this.unit,
  });

  final String type;
  final double startSeconds;
  final double durationSeconds;
  final double? value;
  final String? unit;
}

// ---------------------------------------------------------------------------
// Measurement helpers.
// ---------------------------------------------------------------------------

List<_Edge> _detectEdges(
  Float64List volts,
  Float64List times,
  double low,
  double high,
) {
  if (volts.length < 3 || high <= low) return const [];
  final amplitude = high - low;
  final highThreshold = low + 0.6 * amplitude;
  final lowThreshold = low + 0.4 * amplitude;
  var state = volts.first >= (low + high) / 2 ? 1 : -1;
  final edges = <_Edge>[];
  for (var index = 1; index < volts.length; index++) {
    final value = volts[index];
    if (state <= 0 && value >= highThreshold) {
      final previous = volts[index - 1];
      final fraction = value == previous
          ? 0.0
          : ((highThreshold - previous) / (value - previous)).clamp(0.0, 1.0);
      edges.add(
        _Edge(
          index: index,
          time: times[index - 1] + (times[index] - times[index - 1]) * fraction,
          rising: true,
        ),
      );
      state = 1;
    } else if (state >= 0 && value <= lowThreshold) {
      final previous = volts[index - 1];
      final fraction = value == previous
          ? 0.0
          : ((lowThreshold - previous) / (value - previous)).clamp(0.0, 1.0);
      edges.add(
        _Edge(
          index: index,
          time: times[index - 1] + (times[index] - times[index - 1]) * fraction,
          rising: false,
        ),
      );
      state = -1;
    }
  }
  return edges;
}

List<_WindowStats> _windowStats(_SignalProfile profile, int count) {
  final length = profile.length;
  if (length < 2 || count < 1) return const [];
  final windows = <_WindowStats>[];
  final size = length / count;
  for (var window = 0; window < count; window++) {
    final start = (window * size).floor();
    final end = math.min(length, ((window + 1) * size).ceil());
    if (end - start < 2) continue;
    var minimum = profile.volts[start];
    var maximum = profile.volts[start];
    var sum = 0.0;
    var sumSquares = 0.0;
    for (var index = start; index < end; index++) {
      final value = profile.volts[index];
      if (value < minimum) minimum = value;
      if (value > maximum) maximum = value;
      sum += value;
      sumSquares += value * value;
    }
    final n = end - start;
    windows.add(
      _WindowStats(
        startSeconds: profile.times[start],
        endSeconds: profile.times[end - 1],
        vPp: maximum - minimum,
        vRms: math.sqrt(sumSquares / n),
        vMean: sum / n,
      ),
    );
  }
  return windows;
}

int _windowCount(_SignalProfile profile, double? windowSeconds) {
  if (windowSeconds != null && windowSeconds > 0) {
    final count = (profile.durationSeconds / windowSeconds).round();
    return count.clamp(4, 1000);
  }
  final period = profile.periodSeconds;
  if (period != null && period > 0) {
    return (profile.durationSeconds / period).floor().clamp(4, 200);
  }
  return math.min(50, math.max(1, profile.length ~/ 2));
}

double _estimateNoise(
  Float64List volts,
  double? periodSeconds,
  double? dt,
  double? lsb,
) {
  if (volts.length < 5) return 0;
  var windowSize = 5;
  if (periodSeconds != null && dt != null && dt > 0) {
    final samplesPerPeriod = periodSeconds / dt;
    windowSize = (samplesPerPeriod / 20).round().clamp(3, 51);
  }
  if (windowSize.isEven) windowSize++;
  final half = windowSize ~/ 2;
  final residuals = List<double>.filled(volts.length, 0);
  final buffer = List<double>.filled(windowSize, 0);
  for (var index = 0; index < volts.length; index++) {
    final start = math.max(0, index - half);
    final end = math.min(volts.length - 1, index + half);
    var count = 0;
    for (var scan = start; scan <= end; scan++) {
      buffer[count++] = volts[scan];
    }
    final values = buffer.sublist(0, count)..sort();
    residuals[index] = volts[index] - values[count ~/ 2];
  }
  residuals.sort();
  final absolute = [for (final value in residuals) value.abs()]..sort();
  final sigma = 1.4826 * _percentileSorted(absolute, 0.5);
  final quantization = lsb == null ? 0.0 : lsb / math.sqrt(12);
  return math.max(sigma, quantization);
}

double _twoLevelFraction(List<double> sorted, double low, double high) {
  final amplitude = high - low;
  if (amplitude <= 0 || sorted.isEmpty) return 0;
  final band = 0.08 * amplitude;
  var count = 0;
  for (final value in sorted) {
    if ((value - low).abs() <= band || (value - high).abs() <= band) {
      count++;
    }
  }
  return count / sorted.length;
}

double? _activityPercent(_SignalProfile profile) {
  if (profile.vPp <= 0) return 0;
  final threshold = 0.05 * profile.vPp;
  var active = 0;
  for (final value in profile.volts) {
    if ((value - profile.vMean).abs() > threshold) active++;
  }
  return active / profile.length * 100;
}

List<Map<String, dynamic>> _groupWindowEvents(List<_WindowStats> windows) {
  final grouped = <Map<String, dynamic>>[];
  _WindowStats? first;
  _WindowStats? previous;
  for (final window in windows) {
    if (first == null) {
      first = window;
      previous = window;
      continue;
    }
    if (window.startSeconds - previous!.endSeconds <=
        (previous.endSeconds - previous.startSeconds) * 1.5) {
      previous = window;
      continue;
    }
    grouped.add({
      'startSeconds': _finite(first.startSeconds),
      'endSeconds': _finite(previous.endSeconds),
      'durationSeconds': _finite(previous.endSeconds - first.startSeconds),
      'minVppVolts': _finite(first.vPp),
    });
    first = window;
    previous = window;
  }
  if (first != null && previous != null) {
    grouped.add({
      'startSeconds': _finite(first.startSeconds),
      'endSeconds': _finite(previous.endSeconds),
      'durationSeconds': _finite(previous.endSeconds - first.startSeconds),
      'minVppVolts': _finite(first.vPp),
    });
  }
  return grouped.take(10).toList();
}

List<_SpikeEvent> _detectSpikes(
  _SignalProfile profile,
  WaveformFaultRequest request,
) {
  final length = profile.length;
  if (length < 5) return const [];
  var windowSize = 31;
  if (profile.periodSeconds != null && profile.dt != null && profile.dt! > 0) {
    final samplesPerPeriod = profile.periodSeconds! / profile.dt!;
    windowSize = (samplesPerPeriod / 20).round().clamp(9, 31).toInt();
  }
  windowSize = math.min(windowSize, length);
  if (windowSize.isEven) windowSize--;
  final half = windowSize ~/ 2;
  final residual = Float64List(length);
  for (var index = 0; index < length; index++) {
    final start = math.max(0, index - half);
    final end = math.min(length - 1, index + half);
    final values = <double>[
      for (var scan = start; scan <= end; scan++) profile.volts[scan],
    ]..sort();
    residual[index] = profile.volts[index] - values[values.length ~/ 2];
  }
  final threshold =
      request.number('spikeThresholdVolts') ??
      math.max(
        math.max(6 * profile.noiseRms, 0.02 * profile.vPp),
        2 * (profile.lsb ?? 0),
      );
  if (threshold <= 0) return const [];
  final maxDuration =
      request.number('maxSpikeDurationSeconds') ??
      (profile.periodSeconds != null
          ? math.max(3 * (profile.dt ?? 0), 0.02 * profile.periodSeconds!)
          : math.max(3 * (profile.dt ?? 0), 0.0005 * profile.durationSeconds));
  final events = <_SpikeEvent>[];
  var index = 0;
  while (index < length) {
    if (residual[index].abs() <= threshold) {
      index++;
      continue;
    }
    final start = index;
    final sign = residual[index].sign;
    var peak = residual[index].abs();
    var peakIndex = index;
    while (index < length &&
        residual[index].abs() > threshold &&
        residual[index].sign == sign) {
      if (residual[index].abs() > peak) {
        peak = residual[index].abs();
        peakIndex = index;
      }
      index++;
    }
    final end = index - 1;
    final width = (end - start + 1) * (profile.dt ?? 1.0);
    if (width > maxDuration) continue;
    final preEnd = math.max(0, start - 3);
    final pre = _meanRange(profile.volts, math.max(0, preEnd - 3), preEnd);
    final postStart = math.min(length - 1, end + 3);
    final post = _meanRange(
      profile.volts,
      postStart,
      math.min(length - 1, postStart + 3),
    );
    final peakVolts = profile.volts[peakIndex];
    // A real edge changes the level permanently; a spike returns to the
    // previous baseline.
    if ((post - pre).abs() > 0.5 * (peakVolts - pre).abs()) continue;
    events.add(
      _SpikeEvent(
        startSeconds: profile.times[start],
        peakSeconds: profile.times[peakIndex],
        amplitudeVolts: peakVolts - pre,
        widthSeconds: width,
      ),
    );
  }
  return events;
}

List<_RunEvent> _flatRuns(
  Float64List volts,
  Float64List times,
  double threshold, {
  required bool above,
}) {
  final runs = <_RunEvent>[];
  var index = 0;
  while (index < volts.length) {
    final inside = above
        ? volts[index] >= threshold
        : volts[index] <= threshold;
    if (!inside) {
      index++;
      continue;
    }
    final start = index;
    while (index < volts.length &&
        (above ? volts[index] >= threshold : volts[index] <= threshold)) {
      index++;
    }
    final end = index - 1;
    if (end - start + 1 < 2) continue;
    var sum = 0.0;
    for (var scan = start; scan <= end; scan++) {
      sum += volts[scan];
    }
    runs.add(
      _RunEvent(
        high: above,
        startIndex: start,
        endIndex: end,
        startSeconds: times[start],
        endSeconds: times[end],
        levelVolts: sum / (end - start + 1),
      ),
    );
  }
  return runs;
}

List<_RunEvent> _pulseRuns(_SignalProfile profile) {
  final edges = profile.edges;
  if (edges.length < 2) return const [];
  final runs = <_RunEvent>[];
  var state = edges.first.rising;
  var startIndex = edges.first.index;
  var startSeconds = edges.first.time;
  for (var index = 1; index < edges.length; index++) {
    final edge = edges[index];
    runs.add(
      _RunEvent(
        high: state,
        startIndex: startIndex,
        endIndex: edge.index,
        startSeconds: startSeconds,
        endSeconds: edge.time,
        levelVolts: _meanRange(
          profile.volts,
          startIndex,
          math.max(startIndex, edge.index - 1),
        ),
      ),
    );
    state = edge.rising;
    startIndex = edge.index;
    startSeconds = edge.time;
  }
  return runs;
}

double? _maxSlewRate(_SignalProfile profile) {
  final dt = profile.dt;
  if (dt == null || dt <= 0 || profile.length < 2) return null;
  var maximum = 0.0;
  for (var index = 1; index < profile.length; index++) {
    final slew = (profile.volts[index] - profile.volts[index - 1]).abs() / dt;
    if (slew > maximum) maximum = slew;
  }
  return maximum;
}

double? _frequencyDriftPercent(List<double> frequencies) {
  if (frequencies.length < 4) return null;
  final third = math.max(1, frequencies.length ~/ 3);
  final first = _mean(frequencies.sublist(0, third));
  final last = _mean(frequencies.sublist(frequencies.length - third));
  if (first == 0) return null;
  return (last - first) / first * 100;
}

double? _frequencyDriftSlope(_SignalProfile profile) {
  final frequencies = <double>[
    for (final period in profile.periods)
      if (period > 0) 1 / period,
  ];
  if (frequencies.length < 4) return null;
  final rising = profile.risingEdges;
  if (rising.length <= frequencies.length) return null;
  final times = <double>[
    for (var index = 1; index <= frequencies.length; index++)
      rising[index].time,
  ];
  final fit = fitLinear(
    Float64List.fromList(times),
    Float64List.fromList(frequencies),
  );
  return fit.slope;
}

List<Map<String, dynamic>> _frequencyEvents(_SignalProfile profile) {
  final frequencies = <double>[
    for (final period in profile.periods)
      if (period > 0) 1 / period,
  ];
  if (frequencies.isEmpty) return const [];
  final stride = math.max(1, frequencies.length ~/ 10);
  final events = <Map<String, dynamic>>[];
  final rising = profile.risingEdges;
  for (var index = 0; index < frequencies.length; index += stride) {
    final edgeIndex = math.min(index + 1, rising.length - 1);
    events.add({
      'timeSeconds': _finite(rising[edgeIndex].time),
      'frequencyHz': _finite(frequencies[index]),
    });
  }
  return events;
}

double? _spectrumNoiseFloor(FftSpectrum? spectrum) {
  if (spectrum == null || spectrum.amplitudes.length < 8) return null;
  final start = spectrum.amplitudes.length ~/ 2;
  final values = <double>[
    for (var index = start; index < spectrum.amplitudes.length; index++)
      spectrum.amplitudes[index],
  ];
  return values.isEmpty ? null : _median(values);
}

double? _fundamentalAmplitude(FftSpectrum? spectrum, double? fundamentalHz) {
  if (spectrum == null || fundamentalHz == null || fundamentalHz <= 0) {
    return null;
  }
  return spectrum.amplitudeNear(fundamentalHz, binTolerance: 2);
}

int _dominantPeakIndex(FftSpectrum spectrum) {
  var best = 1;
  for (var index = 2; index < spectrum.amplitudes.length; index++) {
    if (spectrum.amplitudes[index] > spectrum.amplitudes[best]) best = index;
  }
  return best;
}

double _meanAbsoluteDeviation(_SignalProfile profile) {
  if (profile.length == 0) return 0;
  var sum = 0.0;
  for (final value in profile.volts) {
    sum += (value - profile.vMean).abs();
  }
  return sum / profile.length;
}

_EdgeDurations _measureEdgeDurations(_SignalProfile profile) {
  if (profile.amplitude <= 0) return const _EdgeDurations(rise: [], fall: []);
  final low10 = profile.lowLevel + 0.1 * profile.amplitude;
  final high90 = profile.lowLevel + 0.9 * profile.amplitude;
  final maxSpan = profile.periodSeconds != null && profile.dt != null
      ? math.max(4, (profile.periodSeconds! / profile.dt! * 0.5).round())
      : math.max(4, profile.length ~/ 10);
  final rise = <_EdgeDuration>[];
  final fall = <_EdgeDuration>[];
  for (final edge in profile.risingEdges) {
    final t10 = _crossingBefore(
      profile,
      edge.index,
      low10,
      maxSpan,
      rising: true,
    );
    final t90 = _crossingAfter(
      profile,
      edge.index,
      high90,
      maxSpan,
      rising: true,
    );
    if (t10 != null && t90 != null && t90 >= t10) {
      rise.add(
        _EdgeDuration(timeSeconds: edge.time, seconds: t90 - t10, rising: true),
      );
    }
  }
  for (final edge in profile.fallingEdges) {
    final t90 = _crossingBefore(
      profile,
      edge.index,
      high90,
      maxSpan,
      rising: false,
    );
    final t10 = _crossingAfter(
      profile,
      edge.index,
      low10,
      maxSpan,
      rising: false,
    );
    if (t10 != null && t90 != null && t10 >= t90) {
      fall.add(
        _EdgeDuration(
          timeSeconds: edge.time,
          seconds: t10 - t90,
          rising: false,
        ),
      );
    }
  }
  return _EdgeDurations(rise: rise, fall: fall);
}

double? _crossingBefore(
  _SignalProfile profile,
  int edgeIndex,
  double threshold,
  int maxSpan, {
  required bool rising,
}) {
  final start = math.max(0, edgeIndex - maxSpan);
  double? last;
  for (var index = start; index < edgeIndex; index++) {
    final first = profile.volts[index];
    final second = profile.volts[index + 1];
    final crossed = rising
        ? first < threshold && second >= threshold
        : first > threshold && second <= threshold;
    if (crossed) {
      final fraction = second == first
          ? 0.0
          : ((threshold - first) / (second - first)).clamp(0.0, 1.0);
      last =
          profile.times[index] +
          (profile.times[index + 1] - profile.times[index]) * fraction;
    }
  }
  if (last != null) return last;
  final value = profile.volts[start];
  return (rising ? value >= threshold : value <= threshold)
      ? profile.times[start]
      : null;
}

double? _crossingAfter(
  _SignalProfile profile,
  int edgeIndex,
  double threshold,
  int maxSpan, {
  required bool rising,
}) {
  final start = math.max(0, edgeIndex - 1);
  final end = math.min(profile.length - 1, edgeIndex + maxSpan);
  for (var index = start; index < end; index++) {
    final first = profile.volts[index];
    final second = profile.volts[index + 1];
    final crossed = rising
        ? first < threshold && second >= threshold
        : first > threshold && second <= threshold;
    if (crossed) {
      final fraction = second == first
          ? 0.0
          : ((threshold - first) / (second - first)).clamp(0.0, 1.0);
      return profile.times[index] +
          (profile.times[index + 1] - profile.times[index]) * fraction;
    }
  }
  final value = profile.volts[start];
  return (rising ? value >= threshold : value <= threshold)
      ? profile.times[start]
      : null;
}

List<Map<String, dynamic>> _slowestEdges(_EdgeDurations durations) {
  final all = [...durations.rise, ...durations.fall]
    ..sort((a, b) => b.seconds.compareTo(a.seconds));
  return [
    for (final duration in all.take(10))
      {
        'timeSeconds': _finite(duration.timeSeconds),
        'direction': duration.rising ? 'rising' : 'falling',
        'durationSeconds': _finite(duration.seconds),
      },
  ];
}

_Edge? _nearestEdge(List<_Edge> edges, double time) {
  _Edge? best;
  var bestDistance = double.infinity;
  for (final edge in edges) {
    final distance = (edge.time - time).abs();
    if (distance < bestDistance) {
      best = edge;
      bestDistance = distance;
    }
  }
  return best;
}

_Edge? _nextEdge(List<_Edge> edges, _Edge edge) {
  for (final candidate in edges) {
    if (candidate.time > edge.time) return candidate;
  }
  return null;
}

List<_DelayMatch> _matchRisingEdges(
  _SignalProfile reference,
  _SignalProfile other,
) {
  final referenceEdges = reference.risingEdges;
  final otherEdges = other.risingEdges;
  if (referenceEdges.isEmpty || otherEdges.isEmpty) return const [];
  final dt = reference.dt ?? other.dt ?? 1;
  final searchWindow = math.max(
    10 * dt,
    reference.periodSeconds != null
        ? 0.5 * reference.periodSeconds!
        : 0.02 * reference.durationSeconds,
  );
  final matches = <_DelayMatch>[];
  var scan = 0;
  for (final edge in referenceEdges) {
    while (scan < otherEdges.length &&
        otherEdges[scan].time < edge.time - searchWindow) {
      scan++;
    }
    _Edge? best;
    var bestDistance = double.infinity;
    var candidate = scan;
    while (candidate < otherEdges.length &&
        otherEdges[candidate].time <= edge.time + searchWindow) {
      final distance = (otherEdges[candidate].time - edge.time).abs();
      if (distance < bestDistance) {
        best = otherEdges[candidate];
        bestDistance = distance;
      }
      candidate++;
    }
    if (best != null) {
      matches.add(
        _DelayMatch(
          referenceTimeSeconds: edge.time,
          delaySeconds: best.time - edge.time,
        ),
      );
    }
  }
  return matches;
}

double? _correlationAtLag(
  Float64List first,
  Float64List second,
  int lagSamples,
) {
  final length = math.min(first.length, second.length);
  if (length < 4) return null;
  final lag = lagSamples.clamp(-length + 4, length - 4).toInt();
  final startFirst = math.max(0, -lag);
  final startSecond = math.max(0, lag);
  final count = length - lag.abs();
  if (count < 4) return null;
  var sumA = 0.0;
  var sumB = 0.0;
  var sumAB = 0.0;
  var sumA2 = 0.0;
  var sumB2 = 0.0;
  for (var index = 0; index < count; index++) {
    final a = first[startFirst + index];
    final b = second[startSecond + index];
    sumA += a;
    sumB += b;
    sumAB += a * b;
    sumA2 += a * a;
    sumB2 += b * b;
  }
  final denominator =
      math.sqrt(count * sumA2 - sumA * sumA) *
      math.sqrt(count * sumB2 - sumB * sumB);
  if (denominator <= 1e-15) return null;
  return (count * sumAB - sumA * sumB) / denominator;
}

List<Map<String, dynamic>> _crosstalkEvents(
  _SignalProfile aggressor,
  _SignalProfile victim,
) {
  final dt = aggressor.dt ?? 1;
  final halfWindow = math.max(
    2,
    ((aggressor.periodSeconds != null
                ? 0.02 * aggressor.periodSeconds!
                : 0.01 * aggressor.durationSeconds) /
            dt)
        .round(),
  );
  final events = <Map<String, dynamic>>[];
  for (final edge in aggressor.edges) {
    final start = math.max(0, edge.index - halfWindow);
    final end = math.min(victim.length, edge.index + halfWindow + 1);
    if (end - start < 2) continue;
    var minimum = victim.volts[start];
    var maximum = victim.volts[start];
    for (var index = start + 1; index < end; index++) {
      final value = victim.volts[index];
      if (value < minimum) minimum = value;
      if (value > maximum) maximum = value;
    }
    events.add({
      'timeSeconds': _finite(edge.time),
      'victimPeakToPeakVolts': _finite(maximum - minimum),
    });
    if (events.length >= 10) break;
  }
  return events;
}

List<_IntermittentEvent> _intermittentEvents(_SignalProfile profile) {
  final events = <_IntermittentEvent>[];
  final windows = _windowStats(profile, _windowCount(profile, null));
  if (windows.isNotEmpty) {
    final medianVpp = _median([for (final window in windows) window.vPp]);
    if (medianVpp > 0) {
      for (final window in windows) {
        if (window.vPp < 0.2 * medianVpp) {
          events.add(
            _IntermittentEvent(
              type: 'dropout',
              startSeconds: window.startSeconds,
              durationSeconds: window.endSeconds - window.startSeconds,
              value: window.vPp,
              unit: 'Vpp',
            ),
          );
        }
      }
    }
  }
  for (final spike in _detectSpikes(
    profile,
    const WaveformFaultRequest(test: WaveformFaultTest.transients),
  )) {
    events.add(
      _IntermittentEvent(
        type: 'spike',
        startSeconds: spike.startSeconds,
        durationSeconds: spike.widthSeconds,
        value: spike.amplitudeVolts,
        unit: 'V',
      ),
    );
  }
  final runs = _pulseRuns(profile);
  for (final group in [
    runs.where((run) => run.high).toList(),
    runs.where((run) => !run.high).toList(),
  ]) {
    if (group.length < 5) continue;
    final medianWidth = _median([for (final run in group) run.widthSeconds]);
    if (medianWidth <= 0) continue;
    for (final run in group) {
      if (run.widthSeconds < 0.25 * medianWidth) {
        events.add(
          _IntermittentEvent(
            type: 'glitch',
            startSeconds: run.startSeconds,
            durationSeconds: run.widthSeconds,
            value: run.levelVolts,
            unit: 'V',
          ),
        );
      }
    }
  }
  if (profile.periods.length >= 5) {
    final medianPeriod = _median(profile.periods);
    for (var index = 0; index < profile.periods.length; index++) {
      final period = profile.periods[index];
      if (period > 1.5 * medianPeriod || period < 0.5 * medianPeriod) {
        final rising = profile.risingEdges;
        final edgeIndex = math.min(index + 1, rising.length - 1);
        events.add(
          _IntermittentEvent(
            type: 'period_outlier',
            startSeconds: rising[edgeIndex].time,
            durationSeconds: period,
            value: period,
            unit: 's',
          ),
        );
      }
    }
  }
  events.sort((a, b) => a.startSeconds.compareTo(b.startSeconds));
  return events;
}

List<Map<String, dynamic>> _worstPeriodEvents(_SignalProfile profile) {
  if (profile.periods.length < 3) return const [];
  final mean = _mean(profile.periods);
  final rising = profile.risingEdges;
  final indexed = <({int index, double deviation})>[
    for (var index = 0; index < profile.periods.length; index++)
      (index: index, deviation: (profile.periods[index] - mean).abs()),
  ]..sort((a, b) => b.deviation.compareTo(a.deviation));
  return [
    for (final entry in indexed.take(10))
      {
        'timeSeconds': _finite(
          rising.isEmpty
              ? null
              : rising[math.min(entry.index + 1, rising.length - 1)].time,
        ),
        'periodSeconds': _finite(profile.periods[entry.index]),
        'deviationSeconds': _finite(entry.deviation),
      },
  ];
}

List<_RingingEvent> _detectRinging(
  _SignalProfile profile,
  WaveformFaultRequest request,
) {
  final durations = _measureEdgeDurations(profile);
  final threshold = _ringingThreshold(request, profile);
  final dt = profile.dt;
  if (dt == null || dt <= 0) return const [];
  final events = <_RingingEvent>[];
  final steepEdges = [
    for (final item in [...durations.rise, ...durations.fall])
      if (item.seconds <=
          math.max(
            10 * dt,
            profile.periodSeconds == null
                ? 0.05 * profile.durationSeconds
                : 0.1 * profile.periodSeconds!,
          ))
        item,
  ];
  for (final item in steepEdges.take(50)) {
    final edgeTime = item.timeSeconds;
    final startIndex = _indexAtOrAfter(profile.times, edgeTime);
    final windowSeconds = profile.periodSeconds == null
        ? 0.1 * profile.durationSeconds
        : 0.5 * profile.periodSeconds!;
    final nextEdge = _nextEdge(
      profile.edges,
      _Edge(index: startIndex, time: edgeTime, rising: item.rising),
    );
    final edgeLimit = nextEdge == null
        ? profile.length
        : math.max(startIndex + 8, nextEdge.index - 2);
    final endIndex = math
        .min(
          profile.length,
          math.min(
            startIndex + math.max(8, (windowSeconds / dt).round()),
            edgeLimit,
          ),
        )
        .toInt();
    if (endIndex - startIndex < 8) continue;
    final windowLength = endIndex - startIndex;
    final window = Float64List(windowLength);
    final windowTimes = Float64List(windowLength);
    for (var index = 0; index < windowLength; index++) {
      window[index] = profile.volts[startIndex + index];
      windowTimes[index] = profile.times[startIndex + index];
    }
    final fit = fitLinear(windowTimes, window);
    final residual = Float64List(windowLength);
    for (var index = 0; index < windowLength; index++) {
      residual[index] =
          window[index] - (fit.slope * windowTimes[index] + fit.intercept);
    }
    final transitionSamples = (item.seconds / dt).ceil() + 2;
    final skip = transitionSamples
        .clamp(3, math.min(20, windowLength - 2))
        .toInt();
    var peak = 0.0;
    var zeroCrossings = 0;
    var previous = residual[skip];
    for (var index = skip; index < windowLength; index++) {
      final value = residual[index];
      if (value.abs() > peak) peak = value.abs();
      if (index > skip && previous.sign != value.sign && value != 0) {
        zeroCrossings++;
      }
      previous = value;
    }
    if (peak <= threshold || zeroCrossings < 2) continue;
    final sampleRate = profile.context.sampleRateHz;
    double? frequency;
    if (sampleRate != null && sampleRate > 0) {
      final spectrum = computeSpectrum(
        Float64List.fromList(residual.sublist(skip)),
        sampleRate,
      );
      frequency = spectrum.dominantFrequency;
    } else {
      final span = windowTimes[windowLength - 1] - windowTimes[skip];
      if (span > 0) frequency = zeroCrossings / (2 * span);
    }
    if (frequency != null &&
        profile.fundamentalHz != null &&
        frequency <= 1.5 * profile.fundamentalHz!) {
      continue;
    }
    final envelope = fitEnvelopeDecay(
      Float64List.fromList(residual.sublist(skip)),
      Float64List.fromList(windowTimes.sublist(skip)),
      minimumProminence: threshold * 0.5,
    );
    final decayRate = envelope?.decayRatePerSecond;
    final duration = decayRate != null && decayRate > 0
        ? math.min(windowSeconds, math.log(peak / threshold) / decayRate)
        : windowSeconds;
    events.add(
      _RingingEvent(
        startSeconds: edgeTime,
        amplitudeVolts: peak,
        frequencyHz: frequency,
        decayRatePerSecond: decayRate,
        durationSeconds: duration,
      ),
    );
  }
  return events;
}

double _ringingThreshold(
  WaveformFaultRequest request,
  _SignalProfile profile,
) =>
    request.number('ringingThresholdVolts') ??
    math.max(4 * profile.noiseRms, 0.01 * profile.vPp);

int _indexAtOrAfter(Float64List times, double time) {
  var low = 0;
  var high = times.length - 1;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (times[middle] < time) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

double _meanRange(Float64List values, int start, int end) {
  if (values.isEmpty) return 0;
  final first = start.clamp(0, values.length - 1);
  final last = end.clamp(first, values.length - 1);
  var sum = 0.0;
  for (var index = first; index <= last; index++) {
    sum += values[index];
  }
  return sum / (last - first + 1);
}

double _mean(List<double> values) {
  if (values.isEmpty) return 0;
  var sum = 0.0;
  for (final value in values) {
    sum += value;
  }
  return sum / values.length;
}

double _std(List<double> values) {
  if (values.length < 2) return 0;
  final mean = _mean(values);
  var sum = 0.0;
  for (final value in values) {
    final difference = value - mean;
    sum += difference * difference;
  }
  return math.sqrt(sum / values.length);
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.from(values)..sort();
  return _percentileSorted(sorted, 0.5);
}

double _percentileSorted(List<double> sorted, double fraction) {
  if (sorted.isEmpty) return 0;
  final position = (sorted.length - 1) * fraction.clamp(0.0, 1.0);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final weight = position - lower;
  return sorted[lower] * (1 - weight) + sorted[upper] * weight;
}

double? _tolerance(double? absolute, double? percent, double reference) {
  if (absolute != null) return absolute.abs();
  if (percent != null) return reference.abs() * percent / 100;
  return null;
}

double? _percent(double value, double reference) {
  if (reference == 0) return null;
  return value / reference * 100;
}

WaveformFaultSeverity _severityForRatio(double ratio) {
  if (!ratio.isFinite) return WaveformFaultSeverity.high;
  if (ratio >= 2) return WaveformFaultSeverity.high;
  if (ratio >= 1) return WaveformFaultSeverity.medium;
  return WaveformFaultSeverity.low;
}

String _overallStatus(List<WaveformFaultFinding> findings) {
  if (findings.any((finding) => finding.status == WaveformFaultStatus.fail)) {
    return 'fail';
  }
  if (findings.any(
    (finding) => finding.status == WaveformFaultStatus.warning,
  )) {
    return 'warning';
  }
  if (findings.any(
    (finding) => finding.status == WaveformFaultStatus.inconclusive,
  )) {
    return 'incomplete';
  }
  if (findings.isNotEmpty &&
      findings.every((finding) => finding.status == WaveformFaultStatus.pass)) {
    return 'pass';
  }
  return 'informational';
}

Map<String, dynamic> _contextMap(
  WaveformFaultContext context,
  _SignalProfile profile,
) => {
  'channel': context.channel,
  if (context.secondChannel != null) 'secondChannel': context.secondChannel,
  'sampleCount': context.trace.length,
  'durationSeconds': _finite(context.trace.durationSeconds),
  if (context.sampleRateHz != null)
    'sampleRateHz': _finite(context.sampleRateHz),
  if (context.verticalScaleVoltsPerDiv != null)
    'verticalScaleVoltsPerDiv': _finite(context.verticalScaleVoltsPerDiv),
  if (context.verticalOffsetVolts != null)
    'verticalOffsetVolts': _finite(context.verticalOffsetVolts),
  if (context.timebaseSecondsPerDiv != null)
    'timebaseSecondsPerDiv': _finite(context.timebaseSecondsPerDiv),
  'adcBits': context.adcBits,
  'probeAttenuation': _finite(context.probeAttenuation),
  'probeAttenuationAssumed': context.probeAttenuationAssumed,
  if (context.triggerLevelVolts != null)
    'triggerLevelVolts': _finite(context.triggerLevelVolts),
  'triggerPosition': context.triggerPosition,
  if (context.triggerDelaySeconds != null)
    'triggerDelaySeconds': _finite(context.triggerDelaySeconds),
  'leadingSamplesExcluded': context.leadingSamplesExcluded,
  'lowLevelVolts': _finite(profile.lowLevel),
  'highLevelVolts': _finite(profile.highLevel),
  'noiseRmsVolts': _finite(profile.noiseRms),
  if (profile.lsb != null) 'quantizationStepVolts': _finite(profile.lsb),
  'periodCount': profile.periods.length,
  if (profile.periodSeconds != null)
    'periodSeconds': _finite(profile.periodSeconds),
  'rectangular': profile.isRectangular,
};

WaveformFaultFinding _finding({
  required WaveformFaultTest test,
  required WaveformFaultStatus status,
  required String summary,
  WaveformFaultSeverity severity = WaveformFaultSeverity.none,
  Map<String, dynamic> measured = const {},
  Map<String, dynamic>? expected,
  Map<String, dynamic>? deviation,
  List<Map<String, dynamic>> events = const [],
  List<String> missingInputs = const [],
  List<String> limitations = const [],
}) => WaveformFaultFinding(
  test: test,
  status: status,
  severity: severity,
  summary: summary,
  measured: measured,
  expected: expected,
  deviation: deviation,
  events: events,
  missingInputs: missingInputs,
  limitations: limitations,
);

double? _finite(double? value) =>
    value != null && value.isFinite ? value : null;

String _formatVolts(double? value) {
  if (value == null || !value.isFinite) return 'n/a';
  final magnitude = value.abs();
  if (magnitude >= 1) return '${value.toStringAsFixed(3)} V';
  if (magnitude >= 1e-3) return '${(value * 1e3).toStringAsFixed(2)} mV';
  return '${(value * 1e6).toStringAsFixed(1)} µV';
}

String _formatSignedVolts(double value) {
  if (!value.isFinite) return 'n/a';
  final sign = value >= 0 ? '+' : '';
  return '$sign${_formatVolts(value)}';
}

String _formatSeconds(double? value) {
  if (value == null || !value.isFinite) return 'n/a';
  final magnitude = value.abs();
  if (magnitude >= 1) return '${value.toStringAsFixed(3)} s';
  if (magnitude >= 1e-3) return '${(value * 1e3).toStringAsFixed(2)} ms';
  if (magnitude >= 1e-6) return '${(value * 1e6).toStringAsFixed(2)} µs';
  return '${(value * 1e9).toStringAsFixed(1)} ns';
}

String _formatHz(double? value) {
  if (value == null || !value.isFinite) return 'n/a';
  final magnitude = value.abs();
  if (magnitude >= 1e9) return '${(value / 1e9).toStringAsFixed(3)} GHz';
  if (magnitude >= 1e6) return '${(value / 1e6).toStringAsFixed(3)} MHz';
  if (magnitude >= 1e3) return '${(value / 1e3).toStringAsFixed(3)} kHz';
  return '${value.toStringAsFixed(3)} Hz';
}

String _formatSignedHz(double value) {
  if (!value.isFinite) return 'n/a';
  final sign = value >= 0 ? '+' : '';
  return '$sign${_formatHz(value)}';
}

String _formatPercent(double? value) {
  if (value == null || !value.isFinite) return 'n/a';
  return '${value.toStringAsFixed(2)} %';
}

String _formatSignedPercent(double? value) {
  if (value == null || !value.isFinite) return 'n/a';
  final sign = value >= 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(2)} %';
}

String _formatDb(double? value) {
  if (value == null || !value.isFinite) return 'n/a';
  return '${value.toStringAsFixed(1)} dB';
}

String _formatDbc(double? value) {
  if (value == null || !value.isFinite) return 'n/a';
  return '${value.toStringAsFixed(1)} dBc';
}

String _formatDegrees(double? value) {
  if (value == null || !value.isFinite) return 'n/a';
  return '${value.toStringAsFixed(1)}°';
}

double _wrapDegrees(double value) {
  var wrapped = value % 360;
  if (wrapped > 180) wrapped -= 360;
  if (wrapped < -180) wrapped += 360;
  return wrapped;
}
