import 'package:sdsremote/src/signal_generator/models.dart';
import 'package:sdsremote/src/signal_generator/siggen_window_controller.dart';
import 'package:sdsremote/src/signal_generator/siggen_window_protocol.dart';
import 'package:test/test.dart';

import 'fake_siggen_window_client.dart';

void main() {
  late FakeSigGenWindowClient client;
  late SignalGeneratorPanelController controller;

  setUp(() async {
    client = FakeSigGenWindowClient();
    controller = SignalGeneratorPanelController(
      client: client,
      refreshInterval: const Duration(hours: 1),
    );
    await controller.init();
  });

  tearDown(() {
    controller.dispose();
  });

  test('init copies the confirmed state into the drafts', () {
    expect(controller.selection, SigGenDeviceSelection.ch1);
    expect(controller.draft.frequencyText, equals('1'));
    expect(controller.draft.frequencyUnit, equals('kHz'));
    expect(controller.draft.amplitudeText, equals('1'));
    expect(controller.isDirty, isFalse);
    expect(controller.canApply, isFalse);
  });

  test('edits mark the draft dirty and revert restores the device state', () {
    controller.updateFrequencyText('2.5');

    expect(controller.isDirty, isTrue);
    expect(controller.canApply, isTrue);
    expect(controller.draft.frequencyHz, equals(2500));

    controller.revertDraft();

    expect(controller.isDirty, isFalse);
    expect(controller.draft.frequencyText, equals('1'));
  });

  test('rejects a frequency above the model limit', () {
    controller.updateFrequencyUnit('MHz');
    controller.updateFrequencyText('20');

    expect(controller.validationError, contains('Frequency'));
    expect(controller.canApply, isFalse);
  });

  test('rejects an amplitude above the frequency-dependent limit', () {
    controller.updateAmplitudeText('25');

    expect(controller.validationError, contains('Amplitude'));
    expect(controller.canApply, isFalse);
  });

  test('rejects an out-of-range offset', () {
    controller.updateOffsetText('12');

    expect(controller.validationError, contains('Offset'));
    expect(controller.canApply, isFalse);
  });

  test('duty is only applicable to square and pulse', () {
    controller.updateWaveform(Jds6600Waveform.triangle);
    expect(controller.dutyApplicable, isFalse);

    controller.updateWaveform(Jds6600Waveform.square);
    expect(controller.dutyApplicable, isTrue);
    expect(controller.draft.waveform, equals(Jds6600Waveform.square));
  });

  test('exposes all predefined waveforms except arbitrary', () {
    expect(
      controller.selectableWaveforms,
      isNot(contains(Jds6600Waveform.arbitrary)),
    );
    expect(controller.selectableWaveforms, contains(Jds6600Waveform.sine));
  });

  test('apply sends only changed fields', () async {
    client.calls.clear();
    controller.updateFrequencyText('2');
    controller.updateAmplitudeText('2');

    await controller.applyChanges();

    expect(
      client.calls,
      equals(['setFrequency:1:2000.0', 'setAmplitude:1:2.0']),
    );
    expect(controller.isDirty, isFalse);
    expect(controller.message, equals('Settings applied'));
    expect(controller.messageIsError, isFalse);
  });

  test('apply sends the waveform before the frequency', () async {
    client.calls.clear();
    controller.updateWaveform(Jds6600Waveform.square);
    controller.updateFrequencyText('2');

    await controller.applyChanges();

    expect(
      client.calls,
      equals(['setWaveform:1:square', 'setFrequency:1:2000.0']),
    );
  });

  test('apply with no changes reports it without sending commands', () async {
    client.calls.clear();

    await controller.applyChanges();

    expect(client.calls, isEmpty);
    expect(controller.message, equals('No changes to apply'));
  });

  test('failed apply keeps the draft and reports the error', () async {
    client.calls.clear();
    client.failMethods.add('setFrequency:1:2000.0');
    controller.updateFrequencyText('2');

    await controller.applyChanges();

    expect(controller.busy, isFalse);
    expect(controller.message, equals('Command failed'));
    expect(controller.messageIsError, isTrue);
    expect(controller.draft.frequencyText, equals('2'));
    expect(controller.isDirty, isTrue);
  });

  test('output switching calls the client directly', () async {
    client.calls.clear();

    await controller.setOutput(true);

    expect(client.calls, equals(['setOutput:1:true']));
    expect(controller.generator.ch1Output, isTrue);
  });

  test('JDS6600 phase is global and editable from both channels', () async {
    controller.updatePhaseText('90');
    client.calls.clear();
    await controller.applyChanges();

    expect(client.calls, equals(['setPhase:1:90.0']));
    expect(controller.generator.ch1.phaseDeg, equals(90));
    expect(controller.generator.ch2.phaseDeg, equals(90));
    expect(controller.generator.phaseDeg, equals(90));

    controller.selectDevice(SigGenDeviceSelection.ch2);
    controller.updatePhaseText('180');
    client.calls.clear();
    await controller.applyChanges();
    expect(client.calls, equals(['setPhase:2:180.0']));
    expect(controller.generator.ch1.phaseDeg, equals(180));
    expect(controller.generator.ch2.phaseDeg, equals(180));
  });

  test('applies every field to the selected CH2', () async {
    controller.selectDevice(SigGenDeviceSelection.ch2);
    controller.updateWaveform(Jds6600Waveform.square);
    controller.updateFrequencyText('2');
    controller.updateAmplitudeText('2');
    controller.updateOffsetText('0.5');
    controller.updateDutyText('25');
    controller.updatePhaseText('30');
    client.calls.clear();

    await controller.applyChanges();

    expect(
      client.calls,
      equals([
        'setWaveform:2:square',
        'setFrequency:2:2000.0',
        'setAmplitude:2:2.0',
        'setOffset:2:0.5',
        'setDuty:2:25.0',
        'setPhase:2:30.0',
      ]),
    );
    expect(controller.generator.ch2.waveform, Jds6600Waveform.square);
    expect(controller.generator.ch2.dutyPercent, equals(25));
    expect(controller.generator.ch2.phaseDeg, equals(30));
    expect(controller.generator.ch1.frequencyHz, equals(1000));
  });

  test('FY6900 phase is applied only to the selected channel', () async {
    controller.dispose();
    client = FakeSigGenWindowClient(
      fakeWindowState(family: SiggenFamily.fy6900, modelMHz: 60),
    );
    controller = SignalGeneratorPanelController(
      client: client,
      refreshInterval: const Duration(hours: 1),
    );
    await controller.init();

    controller.updatePhaseText('45');
    client.calls.clear();
    await controller.applyChanges();

    expect(client.calls, equals(['setPhase:1:45.0']));
    expect(controller.generator.ch1.phaseDeg, equals(45));
    expect(controller.generator.ch2.phaseDeg, equals(0));

    controller.selectDevice(SigGenDeviceSelection.ch2);
    controller.updatePhaseText('90');
    client.calls.clear();
    await controller.applyChanges();

    expect(client.calls, equals(['setPhase:2:90.0']));
    expect(controller.generator.ch1.phaseDeg, equals(45));
    expect(controller.generator.ch2.phaseDeg, equals(90));
  });

  test('duty can be applied for any waveform', () async {
    controller.updateDutyText('25');
    client.calls.clear();
    await controller.applyChanges();

    expect(client.calls, equals(['setDuty:1:25.0']));
    expect(controller.generator.ch1.dutyPercent, equals(25));
  });

  test('refreshFromDevice pulls the confirmed values', () async {
    client.calls.clear();

    await controller.refreshFromDevice();

    expect(client.calls, contains('refreshGenerator'));
    expect(controller.message, equals('Device state refreshed'));
  });

  test('periodically pulls fresh snapshots', () async {
    controller.dispose();
    client = FakeSigGenWindowClient();
    controller = SignalGeneratorPanelController(
      client: client,
      refreshInterval: const Duration(milliseconds: 20),
    );
    await controller.init();
    expect(controller.generator.connected, isTrue);

    // Change the main-window state without emitting a push.
    client.state = fakeWindowState(connected: false);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(controller.generator.connected, isFalse);
  });

  test('a pushed state updates a non-edited draft', () async {
    client.push(
      fakeWindowState(
        ch1: const SigGenChannelSnapshot(
          waveform: Jds6600Waveform.sine,
          frequencyHz: 4000,
          amplitudeVpp: 1,
          offsetV: 0,
          dutyPercent: 50,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.confirmedChannel.frequencyHz, equals(4000));
    expect(controller.draft.frequencyText, equals('4'));
    expect(controller.isDirty, isFalse);
  });

  test('a pushed state does not overwrite a dirty draft', () async {
    controller.updateFrequencyText('2');
    client.push(
      fakeWindowState(
        ch1: const SigGenChannelSnapshot(
          waveform: Jds6600Waveform.sine,
          frequencyHz: 3000,
          amplitudeVpp: 1,
          offsetV: 0,
          dutyPercent: 50,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.confirmedChannel.frequencyHz, equals(3000));
    expect(controller.draft.frequencyText, equals('2'));
    expect(controller.isDirty, isTrue);
  });

  test('offline generator disables editing and apply', () async {
    controller.dispose();
    client = FakeSigGenWindowClient(fakeWindowState(connected: false));
    controller = SignalGeneratorPanelController(client: client);
    await controller.init();

    expect(controller.directEditingAllowed, isFalse);
    expect(controller.canApply, isFalse);

    await controller.applyChanges();
    expect(controller.message, equals('Signal generator is not connected'));
  });

  test('Bode sweep blocks mutations with a clear message', () async {
    controller.dispose();
    client = FakeSigGenWindowClient(fakeWindowState(mutable: false));
    controller = SignalGeneratorPanelController(client: client);
    await controller.init();
    controller.updateFrequencyText('2');

    await controller.applyChanges();

    expect(controller.message, contains('Bode sweep'));
    expect(controller.messageIsError, isTrue);
  });

  test('FY6900 limits come from the identified 60 MHz model', () async {
    controller.dispose();
    client = FakeSigGenWindowClient(
      fakeWindowState(family: SiggenFamily.fy6900, modelMHz: 60),
    );
    controller = SignalGeneratorPanelController(
      client: client,
      refreshInterval: const Duration(hours: 1),
    );
    await controller.init();

    expect(controller.deviceInfo.family, SiggenFamily.fy6900);
    expect(controller.deviceInfo.modelName, 'FY6900-60M');

    controller.updateFrequencyUnit('MHz');
    controller.updateFrequencyText('60');
    expect(controller.validationError, isNull);
    controller.updateFrequencyText('60.1');
    expect(controller.validationError, contains('Frequency'));

    controller.updateFrequencyText('25');
    controller.updateWaveform(Jds6600Waveform.square);
    expect(controller.validationError, isNull);
    controller.updateFrequencyText('25.1');
    expect(controller.validationError, contains('Frequency'));

    controller.updateWaveform(Jds6600Waveform.sine);
    controller.updateFrequencyText('15');
    controller.updateAmplitudeText('10');
    expect(controller.validationError, isNull);
    controller.updateAmplitudeText('10.1');
    expect(controller.validationError, contains('Amplitude'));

    controller.updateFrequencyText('1');
    controller.updateAmplitudeText('1');
    controller.updateOffsetText('12');
    expect(controller.validationError, isNull);
    controller.updateOffsetText('12.1');
    expect(controller.validationError, contains('Offset'));

    controller.updateOffsetText('0');
    controller.updateWaveform(Jds6600Waveform.square);
    controller.updateDutyText('0');
    expect(controller.validationError, contains('Duty'));
    controller.updateDutyText('99.9');
    expect(controller.validationError, isNull);
  });

  test('FY6900 uses a 100 MHz identified model as the sine limit', () async {
    controller.dispose();
    client = FakeSigGenWindowClient(
      fakeWindowState(family: SiggenFamily.fy6900, modelMHz: 100),
    );
    controller = SignalGeneratorPanelController(
      client: client,
      refreshInterval: const Duration(hours: 1),
    );
    await controller.init();

    controller.updateFrequencyUnit('MHz');
    controller.updateFrequencyText('100');
    expect(controller.validationError, isNull);
    controller.updateFrequencyText('100.1');
    expect(controller.validationError, contains('Frequency'));
  });
}
