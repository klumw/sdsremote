/// Flutter-facing controller of the calculator window.
///
/// It owns the shared [CalcSession] and the transient keypad state (SHIFT,
/// INV). All evaluation rules stay in the engine/session; the controller only
/// adds notifications for the widgets.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'calc_error.dart';
import 'calc_format.dart';
import 'calc_formulas.dart';
import 'calc_session.dart';
import 'calc_value.dart';

/// Controller for the engineering calculator window.
class CalculatorController extends ChangeNotifier {
  CalculatorController({CalcSession? session})
    : session = session ?? CalcSession.withDefaultStorage();

  final CalcSession session;

  bool shift = false;
  bool inverse = false;
  bool initialized = false;
  bool busy = false;
  CalcOutcome? lastOutcome;

  String? get lastError => lastOutcome?.error?.message;

  CalcErrorType? get lastErrorType => lastOutcome?.error?.type;

  String get lastResult => lastOutcome?.display ?? '';

  /// The most recent successful value, or null.
  CalcOutcome? get lastSuccess =>
      lastOutcome != null && lastOutcome!.ok ? lastOutcome : null;

  Future<void>? _initialization;

  Future<void> initialize() {
    if (initialized) return Future<void>.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    await session.load();
    initialized = true;
    notifyListeners();
  }

  void toggleShift() {
    shift = !shift;
    if (shift) inverse = false;
    notifyListeners();
  }

  void toggleInverse() {
    inverse = !inverse;
    if (inverse) shift = false;
    notifyListeners();
  }

  void clearModifiers() {
    shift = false;
    inverse = false;
    notifyListeners();
  }

  /// Clears the display without touching the history or variables.
  void clearResult() {
    lastOutcome = null;
    shift = false;
    inverse = false;
    notifyListeners();
  }

  void refresh() => notifyListeners();

  CalcOutcome evaluate(String expression) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) {
      return lastOutcome ??
          CalcOutcome.failure(argumentError('expression is empty'));
    }
    busy = true;
    notifyListeners();
    final outcome = session.evaluate(trimmed);
    lastOutcome = outcome;
    busy = false;
    notifyListeners();
    return outcome;
  }

  CalcOutcome runFormula(
    CalcFormula formula, [
    Map<String, String> inputs = const {},
  ]) {
    busy = true;
    notifyListeners();
    final outcome = session.runFormula(formula, inputs);
    lastOutcome = outcome;
    busy = false;
    notifyListeners();
    return outcome;
  }

  CalcOutcome defineVariable(String name, String expression) {
    final outcome = session.defineVariable(name, expression);
    lastOutcome = outcome;
    notifyListeners();
    return outcome;
  }

  void deleteVariable(String name) {
    session.deleteVariable(name);
    notifyListeners();
  }

  void deleteFunction(String name) {
    session.deleteFunction(name);
    notifyListeners();
  }

  void clearHistory() {
    session.clearHistory();
    notifyListeners();
  }

  void addFavorite(String name, String expression) {
    session.addFavorite(name, expression);
    notifyListeners();
  }

  void removeFavorite(String id) {
    session.removeFavorite(id);
    notifyListeners();
  }

  void saveProgram(String name, String source) {
    session.saveProgram(name, source);
    notifyListeners();
  }

  void deleteProgram(String id) {
    session.deleteProgram(id);
    notifyListeners();
  }

  void setAngleMode(bool degrees) {
    session.setAngleMode(
      degrees ? CalcAngleMode.degrees : CalcAngleMode.radians,
    );
    notifyListeners();
  }

  void toggleAngleMode() {
    setAngleMode(session.settings.angleMode != CalcAngleMode.degrees);
  }

  void setNumberFormat(CalcNumberFormat format) {
    session.setNumberFormat(format);
    notifyListeners();
  }

  void setNumberBase(CalcIntegerBase base) {
    session.setNumberBase(base);
    notifyListeners();
  }

  void cycleNumberBase() {
    const order = [
      CalcIntegerBase.decimal,
      CalcIntegerBase.hexadecimal,
      CalcIntegerBase.octal,
      CalcIntegerBase.binary,
    ];
    final index = order.indexOf(session.settings.numberBase);
    session.setNumberBase(order[(index + 1) % order.length]);
    notifyListeners();
  }

  void updateSettings(CalcFormatSettings settings) {
    session.settings = settings;
    notifyListeners();
  }

  Future<void> save() => session.save();

  @override
  void dispose() {
    unawaited(session.save());
    super.dispose();
  }
}
