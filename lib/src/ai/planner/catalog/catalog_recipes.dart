/// The typed measurement catalog of the planner.
///
/// The recipes mirror the deterministic tools of [ScopeAnalystAgent],
/// [AudioAgent] and [DigitalAgent]. They are Dart constants so the planner
/// stays testable and can be externalized later.
library;

import '../models/input_form.dart';
import '../planner_config.dart';
import 'param_spec.dart';
import 'recipe.dart';

/// Physical setup shared by all standard recipes.
const String standardSetupId = 'standard_scope_setup';

/// Scope channels offered by the catalog.
const List<InputOption> scopeChannelOptions = <InputOption>[
  InputOption(value: 'ch1', label: 'CH1'),
  InputOption(value: 'ch2', label: 'CH2'),
  InputOption(value: 'ch3', label: 'CH3'),
  InputOption(value: 'ch4', label: 'CH4'),
];

// ---------------------------------------------------------------------------
// Shared parameters
// ---------------------------------------------------------------------------

const ParamSpec _channel = ParamSpec(
  key: PlannerKeys.channel,
  type: ParamType.singleChoice,
  source: ParamSource.userRequired,
  priority: 10,
  question: 'Which scope channel is the DUT connected to?',
  options: scopeChannelOptions,
);

const ParamSpec _sweepChannel = ParamSpec(
  key: PlannerKeys.channel,
  type: ParamType.singleChoice,
  source: ParamSource.userRequired,
  priority: 10,
  question: 'Which scope channel carries the DUT output?',
  help:
      'Connect the signal generator to the DUT input and measure the DUT '
      'output on this channel, for example CH2.',
  options: scopeChannelOptions,
);

const ParamSpec _channelB = ParamSpec(
  key: PlannerKeys.channelB,
  type: ParamType.singleChoice,
  source: ParamSource.userRequired,
  priority: 11,
  question: 'Which scope channel carries the second signal?',
  options: scopeChannelOptions,
);

const ParamSpec _aggressorChannel = ParamSpec(
  key: 'aggressorChannel',
  type: ParamType.singleChoice,
  source: ParamSource.defaulted,
  priority: 13,
  question: 'Which channel carries the aggressor signal?',
  options: scopeChannelOptions,
  defaultValue: 'ch1',
);

const ParamSpec _victimChannel = ParamSpec(
  key: 'victimChannel',
  type: ParamType.singleChoice,
  source: ParamSource.defaulted,
  priority: 14,
  question: 'Which channel carries the victim signal?',
  options: scopeChannelOptions,
  defaultValue: 'ch2',
);

const ParamSpec _inputChannel = ParamSpec(
  key: 'inputChannel',
  type: ParamType.singleChoice,
  source: ParamSource.defaulted,
  priority: 13,
  question: 'Which channel carries the input signal?',
  options: scopeChannelOptions,
  defaultValue: 'ch1',
);

const ParamSpec _outputChannel = ParamSpec(
  key: 'outputChannel',
  type: ParamType.singleChoice,
  source: ParamSource.defaulted,
  priority: 14,
  question: 'Which channel carries the output signal?',
  options: scopeChannelOptions,
  defaultValue: 'ch2',
);

const ParamSpec _generatorChannel = ParamSpec(
  key: PlannerKeys.generatorChannel,
  type: ParamType.singleChoice,
  source: ParamSource.defaulted,
  priority: 20,
  question: 'Which signal-generator channel drives the DUT?',
  options: <InputOption>[
    InputOption(value: '1', label: 'Generator channel 1'),
    InputOption(value: '2', label: 'Generator channel 2'),
  ],
  defaultValue: '1',
);

const ParamSpec _generatorWaveform = ParamSpec(
  key: PlannerKeys.generatorWaveform,
  type: ParamType.singleChoice,
  source: ParamSource.defaulted,
  priority: 21,
  question: 'Which generator waveform should be used?',
  options: <InputOption>[
    InputOption(value: 'sine', label: 'Sine'),
    InputOption(value: 'square', label: 'Square'),
    InputOption(value: 'triangle', label: 'Triangle'),
  ],
  defaultValue: 'sine',
);

const ParamSpec _amplitudeVpp = ParamSpec(
  key: PlannerKeys.amplitudeVpp,
  type: ParamType.number,
  source: ParamSource.defaulted,
  priority: 22,
  question: 'Which generator amplitude should be used?',
  unit: 'Vpp',
  min: 0.001,
  max: 24,
  defaultValue: 1.0,
);

const ParamSpec _offsetV = ParamSpec(
  key: PlannerKeys.offsetV,
  type: ParamType.number,
  source: ParamSource.defaulted,
  priority: 23,
  question: 'Which generator offset should be used?',
  unit: 'V',
  min: -12,
  max: 12,
  defaultValue: 0.0,
);

const ParamSpec _expectedCornerFrequencyHz = ParamSpec(
  key: PlannerKeys.expectedCornerFrequencyHz,
  type: ParamType.number,
  source: ParamSource.given,
  priority: 11,
  question: 'At which frequency do you expect the -3 dB point?',
  help:
      'If you know roughly where the cutoff is, the sweep range is chosen '
      'around it. For a range, enter its lower bound.',
  unit: 'Hz',
  min: 0.01,
  required: false,
);

const ParamSpec _startFrequencyHz = ParamSpec(
  key: PlannerKeys.startFrequencyHz,
  derive: Derivation.sweepStartFromCorner,
  dependsOn: <String>[PlannerKeys.expectedCornerFrequencyHz],
  type: ParamType.number,
  source: ParamSource.askedOrDerived,
  priority: 15,
  question: 'At which frequency should the sweep start?',
  help:
      'The sweep starts here. If you state an expected -3 dB corner, the '
      'planner derives the range around it instead of asking.',
  unit: 'Hz',
  min: 0.01,
  defaultValue: 20.0,
);

const ParamSpec _stopFrequencyHz = ParamSpec(
  key: PlannerKeys.stopFrequencyHz,
  derive: Derivation.sweepStopFromCorner,
  dependsOn: <String>[PlannerKeys.expectedCornerFrequencyHz],
  type: ParamType.number,
  source: ParamSource.askedOrDerived,
  priority: 16,
  question: 'At which frequency should the sweep stop?',
  help: 'The sweep stops here. It must be above the start frequency.',
  unit: 'Hz',
  min: 0.02,
  defaultValue: 20000.0,
);

const ParamSpec _pointCount = ParamSpec(
  key: PlannerKeys.pointCount,
  type: ParamType.number,
  source: ParamSource.defaulted,
  priority: 17,
  question: 'How many sweep points should be measured?',
  min: 2,
  max: 50,
  defaultValue: 10,
);

const ParamSpec _generatorFrequencyHz = ParamSpec(
  key: PlannerKeys.frequencyHz,
  type: ParamType.number,
  source: ParamSource.given,
  priority: 12,
  question: 'At which frequency should the generator run?',
  unit: 'Hz',
  min: 0.01,
);

const ParamSpec _gainFrequencyHz = ParamSpec(
  key: PlannerKeys.frequencyHz,
  type: ParamType.number,
  source: ParamSource.readable,
  priority: 12,
  question: 'At which frequency should the gain be measured?',
  unit: 'Hz',
  min: 0.01,
  reading: ReadingSpec(
    tool: 'read_waveform_summary',
    outputField: 'channels.{inputChannel}.frequencyHz',
  ),
);

const ParamSpec _nominalFrequencyHz = ParamSpec(
  key: 'nominalFrequencyHz',
  type: ParamType.number,
  source: ParamSource.readable,
  priority: 15,
  question: 'What is the nominal clock frequency?',
  unit: 'Hz',
  min: 0.01,
  reading: ReadingSpec(
    tool: 'read_waveform_summary',
    outputField: 'channels.{channel}.frequencyHz',
  ),
);

const ParamSpec _logicFamily = ParamSpec(
  key: PlannerKeys.logicFamily,
  type: ParamType.singleChoice,
  source: ParamSource.userRequired,
  priority: 12,
  question: 'Which logic family does the DUT use?',
  options: <InputOption>[
    InputOption(value: 'ttl_5v', label: 'TTL 5 V'),
    InputOption(value: 'lvttl_3v3', label: 'LVTTL 3.3 V'),
    InputOption(value: 'cmos_3v3', label: 'CMOS 3.3 V'),
    InputOption(value: 'cmos_2v5', label: 'CMOS 2.5 V'),
    InputOption(value: 'cmos_1v8', label: 'CMOS 1.8 V'),
  ],
);

const ParamSpec _edge = ParamSpec(
  key: 'edge',
  type: ParamType.singleChoice,
  source: ParamSource.defaulted,
  priority: 16,
  question: 'Which edge should be measured?',
  options: <InputOption>[
    InputOption(value: 'rising', label: 'Rising'),
    InputOption(value: 'falling', label: 'Falling'),
  ],
  defaultValue: 'rising',
);

// ---------------------------------------------------------------------------
// Safety parameters
// ---------------------------------------------------------------------------

/// Safety questions shared by every request, in policy order.
const List<ParamSpec> standardSafetyParameters = <ParamSpec>[
  ParamSpec(
    key: PlannerKeys.maxVoltageV,
    type: ParamType.number,
    source: ParamSource.userRequired,
    priority: 0,
    question: 'What is the expected maximum voltage at the probe tip?',
    help:
        'Enter the highest voltage that can occur, including transients. '
        'Leave the value unknown only if you cannot estimate it.',
    unit: 'V',
    min: 0,
    max: 1000,
  ),
  ParamSpec(
    key: PlannerKeys.coupling,
    type: ParamType.singleChoice,
    source: ParamSource.userRequired,
    priority: 1,
    question: 'What is the input coupling?',
    options: <InputOption>[
      InputOption(value: 'dc', label: 'DC'),
      InputOption(value: 'ac', label: 'AC'),
    ],
  ),
  ParamSpec(
    key: PlannerKeys.mainsReferenced,
    type: ParamType.boolean,
    source: ParamSource.userRequired,
    priority: 2,
    question: 'Is the DUT referenced to mains potential?',
  ),
  ParamSpec(
    key: PlannerKeys.probeAttenuation,
    type: ParamType.singleChoice,
    source: ParamSource.userRequired,
    priority: 3,
    question: 'What probe attenuation is used?',
    options: <InputOption>[
      InputOption(value: '1x', label: '1x'),
      InputOption(value: '10x', label: '10x'),
      InputOption(value: '100x', label: '100x'),
    ],
    requiredWhen: SafetyCondition.voltageAboveWarning,
  ),
  ParamSpec(
    key: PlannerKeys.differentialOrIsolated,
    type: ParamType.boolean,
    source: ParamSource.userRequired,
    priority: 4,
    question: 'Is the measurement setup differential or isolated?',
    requiredWhen: SafetyCondition.mainsReferenced,
  ),
  ParamSpec(
    key: PlannerKeys.floatingDut,
    type: ParamType.boolean,
    source: ParamSource.userRequired,
    priority: 5,
    question: 'Is the DUT floating?',
    requiredWhen: SafetyCondition.voltageAboveWarning,
  ),
];

// ---------------------------------------------------------------------------
// Recipes
// ---------------------------------------------------------------------------

const List<String> _probeSetup = <String>[
  'Connect the probe to the DUT and to the requested scope channel.',
];

const List<String> _generatorSetup = <String>[
  'Connect the signal-generator output to the DUT input and the measurement '
      'channels to the oscilloscope.',
];

/// The standard recipe set of the planner.
const List<Recipe> standardRecipes = <Recipe>[
  // ---------------------------------------------------------------- simple
  Recipe(
    id: 'scope.vpp',
    type: RecipeType.simpleReading,
    title: 'Peak-to-peak voltage',
    focus: 'measurement',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel],
    estimatedToolCalls: 1,
    requestTemplate:
        'Measure Vpp on {channel} from the current acquisition and return the '
        'value with its unit.',
    manualInstructions: _probeSetup,
    expectedOutput: 'Peak-to-peak voltage in volts',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'scope.vrms',
    type: RecipeType.simpleReading,
    title: 'RMS voltage',
    focus: 'measurement',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel],
    estimatedToolCalls: 1,
    requestTemplate:
        'Measure the RMS voltage on {channel} from the current acquisition and '
        'return the value with its unit.',
    manualInstructions: _probeSetup,
    expectedOutput: 'RMS voltage in volts',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'scope.dc_mean',
    type: RecipeType.simpleReading,
    title: 'DC mean voltage',
    focus: 'measurement',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel],
    estimatedToolCalls: 1,
    requestTemplate:
        'Measure the mean (DC) voltage on {channel} from the current '
        'acquisition and return the value with its unit.',
    manualInstructions: _probeSetup,
    expectedOutput: 'Mean voltage in volts',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'scope.frequency',
    type: RecipeType.simpleReading,
    title: 'Frequency',
    focus: 'measurement',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel],
    estimatedToolCalls: 1,
    requestTemplate:
        'Measure the frequency on {channel} from the current acquisition and '
        'return the value with its unit.',
    manualInstructions: _probeSetup,
    expectedOutput: 'Frequency in hertz',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'scope.period',
    type: RecipeType.simpleReading,
    title: 'Period',
    focus: 'measurement',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel],
    estimatedToolCalls: 1,
    requestTemplate:
        'Measure the period on {channel} from the current acquisition and '
        'return the value with its unit.',
    manualInstructions: _probeSetup,
    expectedOutput: 'Period in seconds',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'scope.min',
    type: RecipeType.simpleReading,
    title: 'Minimum voltage',
    focus: 'measurement',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel],
    estimatedToolCalls: 1,
    requestTemplate:
        'Measure the minimum voltage on {channel} from the current acquisition '
        'and return the value with its unit.',
    manualInstructions: _probeSetup,
    expectedOutput: 'Minimum voltage in volts',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'scope.max',
    type: RecipeType.simpleReading,
    title: 'Maximum voltage',
    focus: 'measurement',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel],
    estimatedToolCalls: 1,
    requestTemplate:
        'Measure the maximum voltage on {channel} from the current acquisition '
        'and return the value with its unit.',
    manualInstructions: _probeSetup,
    expectedOutput: 'Maximum voltage in volts',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'scope.duty_cycle',
    type: RecipeType.simpleReading,
    title: 'Duty cycle',
    focus: 'measurement',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel],
    estimatedToolCalls: 1,
    requestTemplate:
        'Measure the duty cycle on {channel} from the current acquisition and '
        'return the value in percent.',
    manualInstructions: _probeSetup,
    expectedOutput: 'Duty cycle in percent',
    setupId: standardSetupId,
  ),

  // ----------------------------------------------------------------- audio
  Recipe(
    id: 'audio.level',
    type: RecipeType.audio,
    title: 'Audio level',
    focus: 'level_distortion',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel],
    estimatedToolCalls: 3,
    requestTemplate:
        'Measure the audio level on {channel}: RMS, peak, crest factor and '
        'dBFS.',
    manualInstructions: _probeSetup,
    expectedOutput: 'Audio level values with units',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'audio.thdn_sinad',
    type: RecipeType.audio,
    title: 'THD+N and SINAD',
    focus: 'level_distortion',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel],
    estimatedToolCalls: 4,
    requestTemplate:
        'Measure THD+N and SINAD on {channel}, including the fundamental and '
        'the noise floor.',
    manualInstructions: _probeSetup,
    expectedOutput: 'THD+N and SINAD values with units',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'audio.snr',
    type: RecipeType.audio,
    title: 'Signal-to-noise ratio',
    focus: 'level_distortion',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel],
    estimatedToolCalls: 3,
    requestTemplate:
        'Measure the signal-to-noise ratio on {channel}, including the '
        'fundamental and noise levels.',
    manualInstructions: _probeSetup,
    expectedOutput: 'SNR in decibels',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'audio.frequency_response',
    type: RecipeType.audio,
    title: 'Frequency response and -3 dB cutoff',
    aliases: <String>[
      'bode',
      'frequency response',
      'gain/phase curve',
      '-3 db',
      'cutoff',
      'corner frequency',
      'bandwidth',
      'tiefpass',
    ],
    focus: 'frequency_response',
    needsGenerator: true,
    hostManagesGenerator: true,
    needsLiveScope: true,
    parameters: <ParamSpec>[
      _sweepChannel,
      _expectedCornerFrequencyHz,
      _startFrequencyHz,
      _stopFrequencyHz,
      _pointCount,
      _amplitudeVpp,
    ],
    estimatedToolCalls: 6,
    requestTemplate:
        'Run a frequency-response sweep on {channel} from {startFrequencyHz} to '
        '{stopFrequencyHz} with {pointCount} points at {amplitudeVpp}.',
    manualInstructions: <String>[
      'Connect the generator output to the DUT input and the DUT output to the '
          'requested scope channel.',
    ],
    expectedOutput:
        'Gain and phase versus frequency, including the -3 dB '
        'crossings',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'audio.crosstalk',
    type: RecipeType.audio,
    title: 'Crosstalk',
    focus: 'frequency_response',
    needsGenerator: true,
    needsLiveScope: true,
    parameters: <ParamSpec>[
      _aggressorChannel,
      _victimChannel,
      _generatorFrequencyHz,
      _amplitudeVpp,
      _generatorChannel,
      _generatorWaveform,
      _offsetV,
    ],
    estimatedToolCalls: 4,
    requestTemplate:
        'Measure crosstalk from aggressor channel {aggressorChannel} into '
        'victim channel {victimChannel} at {frequencyHz} with {amplitudeVpp} '
        'generator amplitude on generator channel {generatorChannel}.',
    manualInstructions: _generatorSetup,
    expectedOutput: 'Crosstalk in dBc and percent',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'audio.gain',
    type: RecipeType.audio,
    title: 'Gain',
    focus: 'time_domain',
    needsGenerator: true,
    needsLiveScope: true,
    parameters: <ParamSpec>[
      _inputChannel,
      _outputChannel,
      _gainFrequencyHz,
      _amplitudeVpp,
      _generatorChannel,
      _generatorWaveform,
      _offsetV,
    ],
    estimatedToolCalls: 4,
    requestTemplate:
        'Measure the gain from input channel {inputChannel} to output channel '
        '{outputChannel} at {frequencyHz} with {amplitudeVpp} generator '
        'amplitude on generator channel {generatorChannel}.',
    manualInstructions: _generatorSetup,
    expectedOutput: 'Gain in decibels and as a ratio',
    setupId: standardSetupId,
  ),

  // --------------------------------------------------------------- digital
  Recipe(
    id: 'digital.rise_fall',
    type: RecipeType.digital,
    title: 'Rise and fall time',
    focus: 'timing',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel],
    estimatedToolCalls: 2,
    requestTemplate:
        'Measure the rise and fall times on {channel}, including the edge '
        'slopes.',
    manualInstructions: _probeSetup,
    expectedOutput: 'Rise and fall times in seconds',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'digital.pulse_width',
    type: RecipeType.digital,
    title: 'Pulse width',
    focus: 'timing',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel],
    estimatedToolCalls: 2,
    requestTemplate:
        'Measure the high and low pulse widths, period and duty cycle on '
        '{channel}.',
    manualInstructions: _probeSetup,
    expectedOutput: 'Pulse width, period and duty cycle',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'digital.jitter',
    type: RecipeType.digital,
    title: 'Jitter',
    focus: 'timing',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel, _nominalFrequencyHz],
    estimatedToolCalls: 3,
    requestTemplate:
        'Measure the jitter and clock stability on {channel} at the nominal '
        'frequency {nominalFrequencyHz}.',
    manualInstructions: _probeSetup,
    expectedOutput: 'RMS, peak-to-peak and cycle-to-cycle jitter',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'digital.setup_hold',
    type: RecipeType.digital,
    title: 'Setup and hold time',
    focus: 'timing',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel, _channelB, _logicFamily, _edge],
    estimatedToolCalls: 3,
    requestTemplate:
        'Measure the setup and hold time between clock channel {channel} and '
        'data channel {channelB} for the {logicFamily} logic family using the '
        '{edge} clock edge.',
    manualInstructions: <String>[
      'Connect the clock signal to {channel} and the data signal to {channelB}.',
    ],
    expectedOutput: 'Setup and hold times in seconds',
    setupId: standardSetupId,
  ),
  Recipe(
    id: 'digital.overshoot_undershoot',
    type: RecipeType.digital,
    title: 'Overshoot and undershoot',
    focus: 'signal_integrity',
    needsGenerator: false,
    needsLiveScope: true,
    parameters: <ParamSpec>[_channel],
    estimatedToolCalls: 2,
    requestTemplate:
        'Measure overshoot and undershoot on {channel} in volts and percent '
        'of the top-base amplitude.',
    manualInstructions: _probeSetup,
    expectedOutput: 'Overshoot and undershoot in volts and percent',
    setupId: standardSetupId,
  ),
];
