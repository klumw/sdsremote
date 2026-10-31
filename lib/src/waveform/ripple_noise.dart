/// Ripple & noise measurement preset.
///
/// Builds the SCPI sequence for an AC-coupled, bandwidth-limited ripple
/// measurement and the commands that restore the previous channel settings.
/// Pure Dart, no I/O.
library;

/// SCPI sequence for one ripple/noise measurement.
class RippleNoisePlan {
  /// Commands that apply the ripple preset.
  final List<String> applyCommands;

  /// Queries that return the RMS and peak-to-peak values.
  final List<String> measureCommands;

  /// Commands that restore the settings captured before the preset.
  final List<String> restoreCommands;

  const RippleNoisePlan({
    required this.applyCommands,
    required this.measureCommands,
    required this.restoreCommands,
  });
}

/// Builds the ripple/noise sequence for [channel].
///
/// The channel is AC-coupled (`CPL A1M`), optionally bandwidth-limited
/// (`BWL <ch>,ON`), and set to [vdiv] V/div with [offset] V. The restore
/// commands use the values observed before the preset; when they are unknown,
/// DC coupling and the bandwidth limit off are assumed.
RippleNoisePlan buildRippleNoisePlan({
  required int channel,
  required double vdiv,
  required double offset,
  bool bandwidthLimit = true,
  String previousCoupling = 'D1M',
  bool previousBandwidthLimit = false,
  double? previousVdiv,
  double? previousOffset,
}) {
  final ch = 'C$channel';
  final apply = <String>[
    '$ch:CPL A1M',
    if (bandwidthLimit) 'BWL $ch,ON',
    '$ch:VDIV ${_fmt(vdiv)}V',
    '$ch:OFST ${_fmt(offset)}V',
  ];
  final restore = <String>[
    '$ch:CPL $previousCoupling',
    'BWL $ch,${previousBandwidthLimit ? 'ON' : 'OFF'}',
    if (previousVdiv != null) '$ch:VDIV ${_fmt(previousVdiv)}V',
    if (previousOffset != null) '$ch:OFST ${_fmt(previousOffset)}V',
  ];
  return RippleNoisePlan(
    applyCommands: apply,
    measureCommands: ['$ch:PAVA? RMS', '$ch:PAVA? PKPK'],
    restoreCommands: restore,
  );
}

/// Human-readable result line for the dialog.
String formatRippleNoiseResult({required double? rms, required double? vpp}) {
  final rmsText = rms == null ? 'n/a' : '${rms.toStringAsFixed(4)} V';
  final vppText = vpp == null ? 'n/a' : '${vpp.toStringAsFixed(4)} V';
  return 'RMS noise: $rmsText\nVpp: $vppText\n\n'
      'Measured with AC coupling and the 20 MHz bandwidth limit. '
      'Probe ground lead and probe attenuation set the practical noise '
      'floor; values below a few hundred µV are dominated by the setup.';
}

/// Coupling token from a `C<n>:CPL?` response, or null when none is found.
///
/// Accepts both the short form (`D1M`) and a response with a header
/// (`C1:CPL D1M`).
String? parseCouplingResponse(String response) {
  const couplings = {'A1M', 'D1M', 'A50', 'D50', 'GND'};
  final tokens = response.trim().split(RegExp(r'[\s,]+'));
  for (final token in tokens.reversed) {
    final upper = token.toUpperCase();
    if (couplings.contains(upper)) return upper;
  }
  return null;
}

/// Bandwidth-limit state of [channel] from a `BWL?` response, or null when the
/// response does not contain that channel.
///
/// The instrument answers with all channels, for example
/// `BWL C1,OFF,C2,ON,C3,OFF,C4,OFF`.
bool? parseBandwidthLimitResponse(String response, int channel) {
  final match = RegExp(
    'C\\s*$channel\\s*,\\s*(ON|OFF)',
    caseSensitive: false,
  ).firstMatch(response);
  return switch (match?.group(1)?.toUpperCase()) {
    'ON' => true,
    'OFF' => false,
    _ => null,
  };
}

/// Numeric voltage from a `VDIV?` or `PAVA?` response, or null when it cannot
/// be parsed.
///
/// The value is taken from the last comma- or space-separated token, so both
/// `C1:VDIV 5.00E-01V` and `C1:PAVA RMS,5.00E-03V` are accepted. A `mV` suffix
/// is converted to volts.
double? parseVoltageResponse(String response) {
  final text = response.trim();
  final comma = text.lastIndexOf(',');
  final space = text.lastIndexOf(' ');
  final splitAt = comma > space ? comma : space;
  final token = splitAt >= 0 ? text.substring(splitAt + 1).trim() : text;
  final match = RegExp(
    r'^([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)\s*(mV|V)?$',
    caseSensitive: false,
  ).firstMatch(token);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  if (value == null) return null;
  return match.group(2)?.toLowerCase() == 'mv' ? value / 1000 : value;
}

String _fmt(double value) {
  var text = value.toStringAsFixed(6);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}
