/// Built-in macro templates for common test tasks.
///
/// Each template is a complete macro source that the macro parser accepts and
/// that runs without a device until the first SCPI query.
library;

/// One selectable macro template.
class MacroTemplate {
  final String name;
  final String description;
  final String content;

  const MacroTemplate({
    required this.name,
    required this.description,
    required this.content,
  });
}

const List<MacroTemplate> macroTemplates = [
  MacroTemplate(
    name: '5 V power supply',
    description: 'Checks a 5 V rail on CH1 by Vpp and mean voltage.',
    content: '''# 5 V power supply check on CH1
connect(usb)
cmd("C1:TRA ON")
cmd("C1:VDIV 1V")
cmd("C1:OFST -2.5V")
wait(2)
vpp = query("C1:PAVA? PKPK")
mean = query("C1:PAVA? MEAN")
rms = query("C1:PAVA? RMS")
print("CH1 Vpp=" + vpp + " V, Mean=" + mean + " V, RMS=" + rms + " V")
assert("Vpp must be between 4.8 V and 5.2 V", vpp >= 4.8 && vpp <= 5.2)
assert("Mean must be between 4.75 V and 5.25 V", mean >= 4.75 && mean <= 5.25)
''',
  ),
  MacroTemplate(
    name: 'UART baud rate',
    description:
        'Measures a UART data line on CH1 and estimates the baud rate.',
    content: '''# UART baud rate hint on CH1
connect(usb)
cmd("C1:TRA ON")
cmd("C1:VDIV 1V")
cmd("C1:OFST -1.5V")
cmd("C1:TRMD SINGLE")
wait(2)
freq = query("C1:PAVA? FREQ")
width = query("C1:PAVA? WID")
print("UART frequency=" + freq + " Hz, pulse width=" + width + " s")
assert("No UART traffic detected", freq >= 100)
if(width > 0) {
    baud = 1 / width
    print("Estimated baud rate: " + baud)
}
''',
  ),
  MacroTemplate(
    name: 'PWM duty cycle',
    description: 'Checks the duty cycle of a PWM signal on CH1.',
    content: '''# PWM duty cycle check on CH1
connect(usb)
cmd("C1:TRA ON")
cmd("C1:VDIV 1V")
cmd("C1:OFST -2.5V")
wait(2)
duty = query("C1:PAVA? DUTY")
freq = query("C1:PAVA? FREQ")
print("PWM duty=" + duty + " %, frequency=" + freq + " Hz")
assert("PWM duty must be between 40 % and 60 %", duty >= 40 && duty <= 60)
''',
  ),
  MacroTemplate(
    name: 'Clock signal present',
    description: 'Verifies that a clock is present on CH1 (frequency and Vpp).',
    content: '''# Clock presence check on CH1
connect(usb)
cmd("C1:TRA ON")
cmd("C1:VDIV 0.5V")
cmd("C1:OFST 0V")
wait(2)
freq = query("C1:PAVA? FREQ")
vpp = query("C1:PAVA? PKPK")
print("Clock frequency=" + freq + " Hz, Vpp=" + vpp + " V")
assert("No clock signal detected", freq >= 1000 && vpp >= 0.5)
''',
  ),
];
