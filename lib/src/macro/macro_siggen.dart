/// Connection seam for signal-generator commands in macros.
///
/// `connect(SIG, usb)`, `scpi(SIG, …)` and `query(SIG, …)` address the
/// signal generator configured in the settings. The evaluator only depends on
/// this narrow interface; `AppMacroSiggenConnector` in `macro_siggen_app.dart`
/// binds it to the application's signal-generator service and drivers so that
/// macro playback and the rest of the UI share one SCPI implementation.
library;

/// A connected signal generator addressed by the `SIG` selector.
abstract class MacroSiggenSession {
  /// Executes one SCPI line and returns the response of a query.
  ///
  /// Returns `null` for set commands. Throws [MacroSiggenException] when the
  /// command is not supported by the device driver.
  Future<String?> execute(String command);

  /// Closes this session.
  ///
  /// A session that reuses the application's signal-generator service does
  /// not disconnect it, because the generator stays available to the UI.
  Future<void> close();
}

/// Opens the signal generator configured in the settings.
///
/// Used by `connect(SIG, usb)`; the returned session is closed when macro
/// playback ends.
typedef MacroSiggenConnector = Future<MacroSiggenSession> Function();

/// A signal-generator error that stops macro playback.
class MacroSiggenException implements Exception {
  const MacroSiggenException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Connector used when the host did not provide one.
Future<MacroSiggenSession> unavailableMacroSiggenConnector() =>
    throw const MacroSiggenException(
      'Signal generator connections are not available in this context.',
    );
