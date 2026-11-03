/// Signal-generator waveform capabilities.
///
/// The command packages list the waveform names; the driver tables in
/// `models.dart` and `fy6900_protocol.dart` define the actual channel mapping
/// used by the transport. This adapter reuses those existing tables instead of
/// duplicating the cross-model mapping in the device-profile layer.
library;

import '../signal_generator/fy6900_protocol.dart';
import '../signal_generator/models.dart';
import 'device_command_registry.dart';
import 'device_profile_models.dart';

/// Builds a capability resolver for the signal-generator profiles.
///
/// Returns null for profiles that are not signal generators.
DeviceWaveformCapabilityResolver? createSiggenWaveformResolver({
  required String profileId,
  required DeviceWaveforms waveforms,
}) {
  if (profileId == DeviceProfileIds.fy6900) {
    return ({required String requested, int? channel}) =>
        _resolveFy6900(requested, channel, waveforms, profileId);
  }
  if (profileId == DeviceProfileIds.jds6600) {
    return ({required String requested, int? channel}) =>
        _resolveJds6600(requested, channel, waveforms, profileId);
  }
  return null;
}

DeviceWaveformResolution _resolveJds6600(
  String requested,
  int? channel,
  DeviceWaveforms waveforms,
  String profileId,
) {
  final waveform = Jds6600Waveform.fromScpi(requested);
  if (waveform == null) {
    throw _unsupported(requested, channel, waveforms, profileId);
  }
  if (waveform == Jds6600Waveform.arbitrary) {
    throw DeviceCommandException(
      DeviceErrorCode.unsupportedWaveform,
      'Arbitrary waveform selection is not supported by profile '
      '"$profileId".',
      profile: profileId,
      parameter: 'shape',
      requestedValue: requested,
      supportedValues: waveforms.supported,
      details: const {'device_error_code': -113},
    );
  }
  if (!waveform.isJds6600Shape) {
    throw DeviceCommandException(
      DeviceErrorCode.unsupportedWaveform,
      'The waveform "$requested" is FY6900-only and is rejected by the '
      'JDS6600 profile with SCPI error -222.',
      profile: profileId,
      parameter: 'shape',
      requestedValue: requested,
      supportedValues: waveforms.supported,
      details: const {'device_error_code': -222},
    );
  }

  final resolved = waveform.scpiMnemonic;
  _ensurePackageListing(resolved, waveforms, profileId, requested);
  final normalizedRequest = requested.trim().toUpperCase();
  return DeviceWaveformResolution(
    requested: requested,
    resolved: resolved,
    channel: channel,
    mapped: resolved != normalizedRequest,
    note: resolved != normalizedRequest
        ? 'Accepted waveform name "$requested" normalized to the device '
              'mnemonic "$resolved".'
        : null,
    sourceProfile: profileId,
  );
}

DeviceWaveformResolution _resolveFy6900(
  String requested,
  int? channel,
  DeviceWaveforms waveforms,
  String profileId,
) {
  final waveform = Jds6600Waveform.fromScpi(requested);
  if (waveform == null) {
    throw _unsupported(requested, channel, waveforms, profileId);
  }
  if (waveform == Jds6600Waveform.arbitrary) {
    throw DeviceCommandException(
      DeviceErrorCode.unsupportedWaveform,
      'Arbitrary waveform selection is not supported by profile '
      '"$profileId".',
      profile: profileId,
      parameter: 'shape',
      requestedValue: requested,
      supportedValues: waveforms.supported,
      details: const {'device_error_code': -113},
    );
  }

  final effectiveChannel = channel ?? 1;
  if (effectiveChannel == 2 && waveform == Jds6600Waveform.pulse) {
    const resolved = 'RECT';
    _ensurePackageListing(resolved, waveforms, profileId, requested);
    return DeviceWaveformResolution(
      requested: requested,
      resolved: resolved,
      channel: effectiveChannel,
      mapped: true,
      note:
          'CH2 has no adjustable pulse on the FY6900; PULS is mapped to '
          'RECT as documented.',
      sourceProfile: profileId,
    );
  }

  final directlySupported = Jds6600Waveform.selectableFor(
    SiggenFamily.fy6900,
    channel: effectiveChannel,
  ).contains(waveform);
  if (directlySupported) {
    final resolved = waveform.scpiMnemonic;
    _ensurePackageListing(resolved, waveforms, profileId, requested);
    final normalizedRequest = requested.trim().toUpperCase();
    return DeviceWaveformResolution(
      requested: requested,
      resolved: resolved,
      channel: channel,
      mapped: resolved != normalizedRequest,
      note: resolved != normalizedRequest
          ? 'Accepted waveform name "$requested" normalized to the device '
                'mnemonic "$resolved".'
          : null,
      sourceProfile: profileId,
    );
  }

  // The FY6900 driver already defines the closest preset for JDS6600-only
  // names. Reuse that table instead of duplicating it.
  try {
    final index = Fy6900Protocol.waveformIndex(effectiveChannel, waveform);
    final mapped = Fy6900Protocol.decodeWaveform(effectiveChannel, index);
    final resolved = mapped.scpiMnemonic;
    _ensurePackageListing(resolved, waveforms, profileId, requested);
    return DeviceWaveformResolution(
      requested: requested,
      resolved: resolved,
      channel: effectiveChannel,
      mapped: true,
      note:
          'JDS6600 waveform "$requested" is not native to the FY6900 and '
          'maps to the closest FY6900 preset "$resolved".',
      sourceProfile: profileId,
    );
  } on Jds6600Exception {
    throw _unsupported(requested, channel, waveforms, profileId);
  }
}

void _ensurePackageListing(
  String resolved,
  DeviceWaveforms waveforms,
  String profileId,
  String requested,
) {
  if (waveforms.acceptedNames.contains(resolved.toUpperCase())) return;
  throw DeviceCommandException(
    DeviceErrorCode.profileInconsistent,
    'The driver resolved waveform "$requested" to "$resolved", but the '
    'command package for profile "$profileId" does not list that name.',
    profile: profileId,
    parameter: 'shape',
    requestedValue: requested,
    supportedValues: waveforms.acceptedNames.toList(growable: false),
  );
}

DeviceCommandException _unsupported(
  String requested,
  int? channel,
  DeviceWaveforms waveforms,
  String profileId,
) {
  return DeviceCommandException(
    DeviceErrorCode.unsupportedWaveform,
    'The waveform "$requested" is not supported by profile "$profileId"'
    '${channel == null ? '' : ' on channel $channel'}.',
    profile: profileId,
    parameter: 'shape',
    requestedValue: requested,
    supportedValues: waveforms.acceptedNames.toList(growable: false),
    details: {
      'supported_waveforms': waveforms.supported,
      'accepted_aliases': waveforms.acceptedAliases,
      if (waveforms.unsupportedNote != null)
        'unsupported_note': waveforms.unsupportedNote,
    },
  );
}
