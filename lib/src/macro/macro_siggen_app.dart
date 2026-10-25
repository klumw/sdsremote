/// Application binding for the macro signal-generator commands.
///
/// `connect(SIG, usb)` reads the generator type selected in the settings and
/// connects to the matching device. The connection uses the same
/// [SignalGeneratorService] (and therefore the same drivers and SCPI
/// interpreter) as the signal generator window and the Bode plot.
library;

import '../app/app_preferences.dart';
import '../signal_generator/fy6900_driver.dart';
import '../signal_generator/fy6900_serial_transport.dart';
import '../signal_generator/jds6600_driver.dart';
import '../signal_generator/jds6600_serial_transport.dart';
import '../signal_generator/models.dart';
import '../signal_generator/serial_port_scanner.dart';
import '../signal_generator/siggen_driver.dart';
import '../signal_generator/signal_generator_service.dart';
import 'macro_siggen.dart';

/// Settings keys also used by the settings panel and the detector.
const String _devicePreferenceKey = 'siggen_device';
const String _portPreferenceKey = 'siggen_port';

typedef MacroPreferenceReader = Future<String?> Function(String key);
typedef MacroPortLister = Future<List<String>> Function();

/// Opens the signal generator configured in Settings → Signal Generator.
///
/// When the application already owns a [service] for the configured family,
/// that service is reused. This keeps macro playback and the generator window
/// from opening the same serial port twice.
class AppMacroSiggenConnector {
  AppMacroSiggenConnector({
    this.service,
    MacroPreferenceReader? readPreference,
    MacroPortLister? listPorts,
  }) : _readPreference = readPreference ?? AppPreferences.getString,
       _listPorts = listPorts ?? _listSerialPortNames;

  /// Service owned by the application, or null to open a dedicated one.
  final SignalGeneratorService? service;

  final MacroPreferenceReader _readPreference;
  final MacroPortLister _listPorts;

  /// Connects to the configured generator or throws [MacroSiggenException].
  Future<MacroSiggenSession> connect() async {
    final family = await _configuredFamily();
    final ownsService = service == null;
    final generator =
        service ??
        SignalGeneratorService(driverFactory: _driverFactoryFor(family));

    try {
      if (generator.isConnected) {
        if (!await _matchesConfiguredFamily(generator, family)) {
          throw MacroSiggenException(
            'The connected signal generator is not a ${_familyName(family)}.',
          );
        }
        generator.clearErrors();
        return _ServiceMacroSiggenSession(generator, owned: ownsService);
      }

      for (final port in await _candidatePorts(generator)) {
        try {
          await generator.connect(port);
          if (await _matchesConfiguredFamily(generator, family)) {
            generator.clearErrors();
            return _ServiceMacroSiggenSession(generator, owned: ownsService);
          }
        } catch (_) {
          // Port unavailable or not the configured device; try the next one.
        }
        try {
          await generator.disconnect();
        } catch (_) {
          // The connect attempt already cleaned up after a failure.
        }
      }

      generator.clearErrors();
      throw MacroSiggenException(
        'No ${_familyName(family)} signal generator was found on a USB '
        'serial port.',
      );
    } catch (_) {
      if (ownsService) generator.dispose();
      rethrow;
    }
  }

  /// Reads the generator family selected in the settings.
  Future<SiggenFamily> _configuredFamily() async {
    final device = await _readPreference(_devicePreferenceKey);
    return switch (device) {
      'jds6600' => SiggenFamily.jds6600,
      'fy6900' => SiggenFamily.fy6900,
      _ => throw const MacroSiggenException(
        'No signal generator is configured. Select JDS6600 or FY6900 in the '
        'settings.',
      ),
    };
  }

  /// Candidates in scan order: current port, remembered port, serial scan.
  Future<List<String>> _candidatePorts(SignalGeneratorService generator) async {
    final candidates = <String>{};
    final current = generator.port;
    if (current != null && current.isNotEmpty) candidates.add(current);
    final remembered = await _readPreference(_portPreferenceKey);
    if (remembered != null && remembered.isNotEmpty) {
      candidates.add(remembered);
    }
    try {
      candidates.addAll(await _listPorts());
    } catch (_) {
      // Without a native scanner only the remembered ports remain.
    }
    return candidates.toList();
  }

  /// Whether [generator] answers with the identity of [family].
  Future<bool> _matchesConfiguredFamily(
    SignalGeneratorService generator,
    SiggenFamily family,
  ) async {
    final info = generator.deviceInfo;
    if (info != null && info.family != family) return false;
    final identity = await generator.executeScpi('*IDN?');
    if (identity == null) return false;
    return identity.toUpperCase().contains(_identityToken(family));
  }

  static SiggenDriverFactory _driverFactoryFor(SiggenFamily family) =>
      family == SiggenFamily.fy6900
      ? (port) => Fy6900Driver(LibSerialPortFy6900Transport(port))
      : (port) => Jds6600Driver(LibSerialPortJds6600Transport(port));

  static Future<List<String>> _listSerialPortNames() async =>
      listSerialPorts().map((port) => port.name).toList();

  static String _familyName(SiggenFamily family) =>
      family == SiggenFamily.fy6900 ? 'FY6900' : 'JDS6600';

  static String _identityToken(SiggenFamily family) =>
      family == SiggenFamily.fy6900 ? 'FY6900' : 'JDS6600';
}

/// Adapts [SignalGeneratorService] to the macro session contract.
class _ServiceMacroSiggenSession implements MacroSiggenSession {
  _ServiceMacroSiggenSession(this._service, {required bool owned})
    : _owned = owned;

  final SignalGeneratorService _service;

  /// Whether this session owns the service and must close it.
  final bool _owned;

  @override
  Future<String?> execute(String command) async {
    if (!_service.isConnected) {
      throw const MacroSiggenException('Signal generator is not connected.');
    }
    final errorsBefore = _service.errorCount;
    final response = await _service.executeScpi(command);
    if (_service.errorCount > errorsBefore) {
      final error = _service.takeLastError();
      if (error != null) {
        throw MacroSiggenException(
          'SCPI error ${error.code}: ${error.message}',
        );
      }
    }
    return response;
  }

  @override
  Future<void> close() async {
    if (_owned) await _service.shutdown();
  }
}
