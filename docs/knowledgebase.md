# Knowledgebase for SDS1000X-E Oscilloscopes

## Introduction (models, bandwidth, sample rate) [2+4-channel]

This user knowledge base includes important safety and installation information related to the SDS1000X-E and SDS1000X-U series oscilloscopes, and includes simple tutorials for basic operation of the oscilloscope.

The series includes the following models:

| Model | Analog Bandwidth |
|--------------|-------------------------------------------------------|
| SDS1204X-E | 200 MHz bandwidth, 4-channel, 1 GSa/s Sample rate |
| SDS1104X-E | 100 MHz bandwidth, 4-channel, 1 GSa/s Sample rate |
| SDS1202X-E | 200 MHz bandwidth, 2-channel, 1 GSa/s Sample rate |
| SDS1104X-U | 100 MHz bandwidth, 4-channel, 1 GSa/s Sample rate |

## General Features (SPO, digital trigger, capture rate, intensity grading, FFT, history, sequence, display, interfaces) [2+4-channel]

The SDS1000X-E series uses SPO (Super-Phosphor Oscilloscope) technology with a digital trigger system, 256-level intensity grading and a color temperature display mode. The waveform capture rate is up to 100,000 wfm/s in normal mode and 400,000 wfm/s in sequence mode. The record length is up to 14 Mpts; History stores up to 80,000 frames; Sequence mode supports up to 80,000 segments. The FFT math function supports up to 1 Mpts. The display is a 7-inch TFT-LCD with 800×480 resolution. Standard interfaces are USB Host, USB Device (USBTMC), LAN, Pass/Fail and Trigger Out. Serial bus triggering and decoding (IIC, SPI, UART/RS232, CAN, LIN) is standard.

## Two-Channel Architecture (SDS1202X-E, single ADC, 1GSa/s, 2+EXT, 14Mpts) [2-channel only]

The two-channel models (SDS1202X-E, 200 MHz) use one 1 GSa/s ADC and one 14 Mpts memory module. The channel configuration is 2 analog channels + EXT. With one channel active, the maximum sample rate is 1 GSa/s and the maximum record length is 14 Mpts. With both channels active, each channel samples at 500 MSa/s with 7 Mpts per channel (interleave mode).

## Four-Channel Architecture (SDS1104X-E, SDS1204X-E, two ADCs, 500MSa/s, 7Mpts/CH, 14Mpts interleave) [4-channel only]

The four-channel models (SDS1104X-E 100 MHz, SDS1204X-E 200 MHz) use two 1 GSa/s ADCs and two 14 Mpts memory modules. With all four channels active, each channel samples at 500 MSa/s with 7 Mpts per channel. With only one channel per ADC pair active, that channel samples at 1 GSa/s with 14 Mpts.

## General Safety Summary (precautions, electric shock, grounding) [2+4-channel]

Carefully read the following safety precautions to avoid any personal injury or damage to the instrument and any products connected to it. To avoid potential hazards, please use the instrument as specified.

## Service Safety (qualified personnel, hazardous voltage, ESD, capacitor discharge, external fan) [2+4-channel]

Only qualified personnel should perform service procedures. Disconnect the power cord before removing or replacing parts. Hazardous voltages exist on the power supply module and the LCD module; after disconnecting the power cord, wait at least three minutes for the capacitors to discharge. Use ESD precautions: place the oscilloscope on a properly grounded ESD mat and wear a grounded ESD strap. When the metal shield is removed, use an external fan to provide airflow over the heat sinks and main board; if the rear cover is removed but the metal shield remains installed, the internal fan is sufficient.

## Use Proper Power Line (power cord) [2+4-channel]

Only the power cord designed for the instrument and authorized by local country could be used.

## Ground the Instrument (protective earth, electric shock) [2+4-channel]

The instrument is grounded through the protective earth conductor of the power line. To avoid electric shock, please make sure the instrument is grounded correctly before connecting its input or output terminals.

## Connect the Signal Wire Correctly (signal wire, earth potential) [2+4-channel]

The potential of the signal wire is equal to the earth, so do not connect the signal wire to a high voltage.

## Look Over All Terminals' Ratings (fire, electric shock) [2+4-channel]

To avoid fire or electric shock, please look over all ratings and sign instruction of the instrument. Before connecting the instrument, please read the manual carefully to gain more information about the ratings.

## Use Proper Overvoltage Protection (thunderstorm, electrical shock) [2+4-channel]

Make sure that no overvoltage (such as that caused by a thunderstorm) can reach the product, or else the operator might expose to danger of electrical shock.

## Electrostatic Prevention (ESD, static discharge) [2+4-channel]

Operate in an electrostatic discharge protective area environment to avoid damages induced by static discharge. Always ground both the internal and external conductors of the cable to release static before connecting.

## Keep Well Ventilation (temperature, fan) [2+4-channel]

Inadequate ventilation may cause increasing of temperature, which will eventually damage the instrument. So keep well ventilation and inspect the intake and fan regularly.

## Avoid Circuit or Components Exposed (exposed contacts) [2+4-channel]

Do not touch exposed contacts or components when the power is on.

## Use proper Fuse (specified fuse) [2+4-channel]

Use only the specified fuse.

## Do Not Operate Without Covers (panels removed) [2+4-channel]

Do not operate the instrument with covers or panels removed.

## Do Not Operate With Suspected Failures (maintenance, qualified service) [2+4-channel]

If you suspect damage occurs to the instrument, have it inspected by qualified service personnel before further operations. Any maintenance, adjustment or replacement especially to circuits or accessories must be performed by SIGLENT authorized personnel.

## Do Not Operate in Wet Conditions (humid environment, short circuit) [2+4-channel]

In order to avoid short circuiting to the interior of the device or electric shock, please do not operate in a humid environment.

## Do Not Operate in an Explosive Atmosphere (explosive atmosphere) [2+4-channel]

In order to avoid damages to the device or personal injuries, it is important to operate the device away from an explosive atmosphere.

## Keep Product Surfaces Clean and Dry (dust, moisture) [2+4-channel]

To avoid the influence of dust and/or moisture in air, please keep the surface of device clean and dry.

## Handling Safety (transportation, probe assemblies, UL 61010) [2+4-channel]

Please handle with care during transportation to avoid damages to buttons, knob interfaces and other parts on the panels.
Only probe assemblies which meet the manufacturer's specifications shall be used. When use 2X/…/10000X probe assemblies, the probe assemblies shall be insulated from the measured circuits by double or reinforced insulation.
All probe assemblies should meet the requirements of UL 61010-031 and CAN/CSA-C22.2 No. 61010 -031 -07.
Not to position the equipment so that it is difficult to operate the disconnecting device (detachable plug).
If the equipment is used in a manner not specified by the manufacturer, the protection provided by the equipment may be impaired

## Safety Terms and Symbols (WARNING, CAUTION, DANGER, hazardous voltage, protective earth, test ground, power switch) [2+4-channel]

Terms in this manual. These terms may appear in this manual:

- WARNING: Warning statements indicate the conditions or practices that could result in injury or loss of life.
- CAUTION: Caution statements indicate the conditions or practices that could result in damage to this product or other property.

Terms on the product. These terms may appear on the product:

- DANGER: Indicates direct injuries or hazards that may happen.
- WARNING: Indicates potential injuries or hazards that may happen.
- CAUTION: Indicates potential damages to the instrument or other property that may happen.

Symbols on the product. These symbols may appear on the product: hazardous voltage, protective earth terminal, warning, test ground, power switch.
If such symbols are found on the product, consult the manual to find out the nature of the potential hazard and the actions which have to be taken.

## Measurement Category (CAT II, CAT III, CAT IV, mains circuits, WARNING) [2+4-channel]

This oscilloscope can make measurements in other circuits that are not directly connected to mains.

WARNING
- This oscilloscope can only be used for measurements within its specified measurement categories.
- Not to use the product for measurements within other measurement categories, such as CAT II, CAT III, CAT IV.
- Not to use the equipment for measurements on mains circuits.

## Measurement Category Definitions (CAT II, household appliances, CAT III, distribution boards, CAT IV, electricity meters) [2+4-channel]

Measurement category II is for measurements performed on circuits directly connected to the low voltage installation. Examples are measurements on household appliances, portable tools and similar equipment.

Measurement category III is for measurements performed in the building installation. Examples are measurements on distribution boards, circuit-breakers, wiring, including cables, bus-bars, junction boxes, switches, socket-outlets in the fixed installation, and equipment for industrial use and some other equipment, for example, stationary motors with permanent connection to the fixed installation.

Measurement category IV is for measurements performed at the source of the low-voltage installation. Examples are electricity meters and measurements on primary over current protection devices and ripple control units.

## Working Environment (indoor use, clean, dry) [2+4-channel]

## Environment use (indoor) [2+4-channel]

This instrument is intended for indoor use and should be operated in a clean, dry environment.

## Temperature (operating, non-operating, ambient) [2+4-channel]

Operating: 0℃ to +40℃
Non-operation:-20℃ to +60℃
Note: Direct sunlight, radiators, and other heat sources should be taken into account when assessing the ambient temperature.

## Humidity (RH, operating, non-operating) [2+4-channel]

Operating: 85% RH, 40 ℃, 24 hours
Non-operating: 85% RH, 65 ℃, 24 hours

## Altitude (operating, non-operating) [2+4-channel]

Operating: less than 3 Km
Non-operation: less than 15 Km

## Installation (overvoltage) Category (mains, category II) [2+4-channel]

This product is powered by mains conforming to installation (overvoltage) category II.

## Overvoltage WARNING (thunderbolt, electric shock) [2+4-channel]

Make sure that no overvoltage (such as that caused by thunderbolt) can reach the product, or else the operator might expose to danger of electric shock.

## Installation (overvoltage) Category Definitions (signal level, AC line, transient voltage) [2+4-channel]

Installation (overvoltage) category I refers to signal level which is applicable to equipment measurement terminals connected to the source circuit. In these terminals, precautions are done to limit the transient voltage to the corresponding low level.

Installation (overvoltage) category II refers to the local power distribution level which is applicable to equipment connected to the AC line (AC power).

## Degree of Pollution (Pollution Degree II, non-conductive pollution) [2+4-channel]

The oscilloscopes may be operated in environments of Pollution Degree II.

Note: Degree of Pollution II refers to a working environment which is dry and non-conductive pollution occurs. Occasional temporary conductivity caused by condensation is expected.

## IP Rating (IP20, IEC 60529) [2+4-channel]

IP20 (as defined in IEC 60529).

## Ventilation Requirement (fan, cooling, clearance) [2+4-channel]

This oscilloscope uses fan to force cooling. Please make sure that the air intake and exhaust areas are free from obstructions and have free air. When using the oscilloscope in a bench -top or rack setting, provide at least 10 cm clearance beside, above and behind the instrument for adequate ventilation.

## Ventilation WARNING (temperature increase, intake, fan) [2+4-channel]

Inadequate ventilation may cause temperature increase which would damage the instrument. So please keep the instrument well ventilated during operation and inspect the intake and fan regularly.

## AC Power and Ground Connections (single-phase, Vrms, IEC320, safety ground) [2+4-channel]

The instrument operates with a single-phase, 100 to 240 Vrms (±10%) AC power at 50/60 Hz (±5%), or single-phase 100 120 Vrms (±10%) AC power at 400Hz (±5%).

No manual voltage selection is required because the instrument automatically adapts to line voltage.

Depending on the type and number of options and accessories (probes, PC port plug-in, etc.), the SDS1xx2X-E can consume up to 25 W of power, the SDS1xx4X -E can consume up to 25 W of power, the SDS1xx4X -U can consume up to 50 W of power.

Note: The instrument automatically adapts to the AC line input within the following ranges:

| Voltage Range: | 90 - 264 Vrms | 90 - 132 Vrms |
|------------------|-----------------|------------------|
| Frequency Range: | 47 - 63 Hz | 380 - 420 Hz |

The instrument includes a grounded cord set containing a molded three-terminal
polarized plug and a standard IEC320 (Type C13) connector for making line voltage and safety ground connection. The AC inlet ground terminal is connected directly to the frame of the instrument. For adequate protection against electrical shock hazard, the power cord plug must be inserted into a mating AC outlet containing a safety ground contact. Use only the power cord specified for this instrument and certified for the country of use.

## WARNING (electrical shock, protective ground, power cord) [2+4-channel]

Electrical Shock Hazard!
Any interruption of the protective ground conductor within or outside of the scope or disconnection of the safety ground terminal creates a hazardous situation.
Intentional interruption is prohibited.
The position of the oscilloscope should allow easy access to the socket. To make the oscilloscope completely power off, unplug the instrument power cord from the AC socket.
The power cord should be unplugged from the AC outlet if the scope is not to be used for an extended period of time.

## CAUTION (front panel terminals, chassis, safety ground) [2+4-channel]

The outer shells of the front panel terminals (CH1, CH2, CH3, CH4, EXT) are connected to the instrument's chassis and therefore to the safety ground.

## Care (direct sunshine, storage) [2+4-channel]

Do not store or leave the instrument in direct sunshine for long periods of time.

## WARNING (fog, liquid, solvent) [2+4-channel]

To avoid damages to the instrument or probe, please do not leave them in fog, liquid, or solvent.

## Cleaning (soft cloth, LCD, corrosive liquid) [2+4-channel]

Please perform the following steps to clean the instrument and probe regularly according
to its operating conditions.
Disconnect the instrument from all power sources, and then clean it with a soft wet cloth. Clean the loose dust on the outside of the instrument and probe with a soft cloth. When cleaning the LCD, take care to avoid scarifying it.

## WARNING (corrosive liquid, chemical cleanser, short circuits) [2+4-channel]

To avoid damages to the surface of the instrument and probe, please do not use any corrosive liquid or chemical cleanser.
Make sure that the instrument is completely dry before restarting it to avoid short circuits or personal injuries.

## Safety Compliance (UL 61010, CAN/CSA, safety standards) [2+4-channel]

This section lists the safety standards with which the product complies.

## U.S. nationally recognized testing laboratory listing (UL 61010, NRTL) [2+4-channel]

- UL 61010 -1:2012/R:2018 -11. Safety Requirements for Electrical Equipment for Measurement, Control, and Laboratory Use – Part 1: General Requirements.
- UL 61010 -2 -030:2018. Safety Requirements for Electrical Equipment for Measurement, Control, and Laboratory Use – Part2-030: Particular requirements for testing and measuring circuits.

## Canadian certification (CAN/CSA, C22.2) [2+4-channel]

- CAN/CSA -C22.2 No. 61010 -1:2012/A1:2018 -11. Safety Requirements for Electrical Equipment for Measurement, Control, and Laboratory Use – Part 1: General Requirements.
- CAN/CSA -C22.2 No. 61010 -2 -030:2018. Safety Requirements for Electrical Equipment for Measurement, Control, and Laboratory Use – Part 2-030: Particular requirements for testing and measuring circuits.

## General Inspection (shipping container, damage, accessories) [2+4-channel]

1. Inspect the shipping container for damage.
Keep the damaged shipping container or cushioning material until the contents of the shipment have been checked for completeness and the instrument has passed both electrical and mechanical tests.
The consigner or carrier shall be liable for the damage to instrument resulting from shipment. SIGLENT would not be responsible for free maintenance/rework or replacement of the unit.

2. Inspect the instrument.
In case of any damage, or defect, or failure, notify your SIGLENT sales representative.

3. Check the Accessories
Please check the accessories according to the packing lists. If the accessories are incomplete or damaged, please contact your SIGLENT sales representative.

## Appearance and Dimensions (312mm, 149.5mm, 151mm, 132.5mm, 132.6mm, 107mm) [2+4-channel]

The manual shows front and top views for the 2-channel and 4-channel models:

- 2-channel scope front view: 312 mm wide × 149.5 mm high; top view: 132.5 mm deep overall, 107 mm body height.
- 4-channel scope front view: 312.0 mm wide × 151.0 mm high; top view: 132.6 mm deep overall, 107.0 mm body height.

## Prepare for Using Adjust the Supporting Legs (stands, tilt) [2+4-channel]

Adjust the supporting legs properly to use them as stands to tilt the oscilloscope upwards for stable placement of the oscilloscope as well as better operation and observation.

## Prepare for Using Connect the Power Supply (power cord, 100-240V) [2+4-channel]

The power requirements of the oscilloscope are 100-240 V, 50/60Hz or 100-120 V, 400Hz. Please use the power cord supplied with the accessories to connect the oscilloscope to the power source.

## Prepare for Using Power-on Inspection (self-test, relay switching, welcome screen) [2+4-channel]

When the oscilloscope is energized, press the power key at the lower-left corner of the front panel to start the oscilloscope. Several keys light for about 6 seconds until the boot screen appears. During the start-up process, the oscilloscope performs a series of self-tests and you can hear the sound of relay switching. After the self-test is finished, the welcome screen is displayed; press Default to recall the factory default settings.

## Prepare for Using Connect the Probe (BNC, probe tip, ground alligator clip) [2+4-channel]

SIGLENT provides passive probes for the oscilloscopes. For detailed technical information of the probes, please refer to the corresponding Probe User's Guide.

1. Connect the BNC terminal of the probe to a channel BNC connector of the oscilloscope at the front panel.
2. Connect the probe tip to the circuit point to be tested and connect the ground alligator clip of the probe to the circuit ground terminal.

## Prepare for Using Function Inspection (Default button, Auto Setup, square waveform) [2+4-channel]

1. Press the Default button on the front panel to restore the instrument to its default configuration.
2. Connect the ground alligator clip of the probe to the "Ground Terminal" under the probe compensation signal output terminal.
3. Use the probe to connect the input terminal of CH1 of the oscilloscope and the "Compensation Signal Output Terminal" of the probe.
4. Press the Auto Setup.
5. Observe the waveform on the display. In normal condition, the display should be a square waveform as shown in the figure below:
6. Use the same method to test the other channels. If the square waveforms actually shown do not match that in the figure above, please perform "Probe Compensation" in the next section.

To avoid electric shock during the use of probe, please make sure that the insulated wire of the probe is in good condition and do not touch the metallic part of the probe when the probe is connected to high voltage source

## Probe Compensation (10X, low-frequency compensation, perfectly compensated) [2+4-channel]

When the probes are used for the first time, you should compensate the probes to match the input channels of the oscilloscope. Non-compensated or poorly

compensated probes may cause measurement inaccuracy or error. The probe compensation procedures are as follows.

1. Set the switch to 10X on the probe.
2. Perform steps 1, 2, 3 and 4 of "Function Inspection" in the previous section.
3. Check the waveforms displayed and compare them with the following:
4. Use a nonmetallic driver to adjust the low-frequency compensation adjustment hole on the probe until the waveform displayed is as the "Perfectly compensated" in the figure above.

## USB Host Test (U disk, USB Flash Drive Detected, icon) [2+4-channel]

1. Insert a USB flash drive into the USB Host interface on the front panel.
2. The message "USB Flash Drive Detected." appears and an icon is shown in the lower right corner of the screen when the drive is recognized.

## USB Device Test (USBTMC, USB cable Type AB, PC, VISA query) [2+4-channel]

1. Connect the oscilloscope to a PC with a standard USB cable (Type AB).
2. The oscilloscope appears as a USBTMC device on the PC.
3. Open a VISA test panel, select the USBTMC device and send a query; the response confirms the interface is working.

## LAN Port Test (IP address, subnet mask, LAN cable, VISA query) [2+4-channel]

1. Press Utility → NextPage2/4 → I/O → LAN → IP Set and enter a valid IP address and subnet mask.
2. Connect the oscilloscope to the PC with a LAN cable.
3. Select the LAN device in the VISA test panel and send a query; a response confirms the interface is working.

## Pass/Fail Out Test (mask, X Mask, Y Mask, second oscilloscope, pulse) [2+4-channel]

1. Enable CH1 and configure Pass/Fail: Enable Test On, Source CH1, Msg Display On, X Mask 0.32div, Y Mask 0.32div; press Create Mask.
2. Connect the Pass/Fail output on the rear panel to a second oscilloscope.
3. Move the waveform out of the mask. A pulse appears on the second oscilloscope if the output works.

## Front Panel Overview (LCD, knobs, buttons, connectors) [2+4-channel]

| NO. | Description | NO. | Description |
|-------|-----------------------|-------|---------------------------------------|
| 1 | LCD Display | 8 | Vertical Control |
| 2 | Universal Knob | 9 | Probe Compensation/ Ground Terminal |
| 3 | Common Function Menus | 10 | Analog Channel and Ext Input |
| 4 | Run/Stop | 11 | USB Host |
| 5 | Auto Setup | 12 | Menu Soft key |
| 6 | Trigger Control | 13 | Menu on/off |
| 7 | Horizontal Control | 14 | Power Button |

| NO. | Description | NO. | Description |
|-------|------------------------------------------|-------|---------------------------------------|
| 1 | LCD Display | 12 | Horizontal Control |
| 2 | Universal Knob | 13 | Trigger Control |
| 3 | Common Function Menus | 14 | Menu on/off |
| 4 | Clear Sweeps | 15 | Menu Soft key |
| 5 | Run/Stop | 16 | One - Button shortcut for Save |
| 6 | Decode | 17 | Analog Channel |
| 7 | Auto Setup | 18 | Power Button |
| 8 | Navigate | 19 | USB Host |
| 9 | History | 20 | Digital Inputs |
| 10 | Default | 21 | Probe Compensation/ Ground Terminal |
| 11 | Vertical Control, Math, REF and Digital |  |  |

| NO. | Description | NO. | Description |
|-------|-----------------------------|-------|---------------------------------------|
| 1 | LCD Display | 12 | Horizontal Control |
| 2 | Universal Knob | 13 | Trigger Control |
| 3 | Common Function Menus | 14 | Menu on/off |
| 4 | Clear Sweeps | 15 | Menu Soft key |
| 5 | Run/Stop | 16 | One - Button shortcut for Save |
| 6 | Decode | 17 | Analog Channel |
| 7 | Auto Setup | 18 | Power Button |
| 8 | Navigate | 19 | USB Host |
| 9 | History | 20 | Probe Compensation/ Ground Terminal |
| 10 | Default |  |  |
| 11 | Vertical Control, Math, REF |  |  |

## Rear Panel Overview (handle, LAN, USB, Pass/Fail, AC power) [2+4-channel]

## 1. Handle (carrying) [2-channel only]

Pull up the handle vertically for easy carrying of the instrument. When you do not need the handle, press it down.

## 2. Safety lock Hole (security lock, Kensington) [2-channel only]

You can lock the instrument to a fixed location using the security lock (please buy it yourself) via the lock hole.

## 3. LAN (network, remote control) [2-channel only]

The instrument can be connected to network via this interface to perform remote control.

## 4. Pass/Fail or Trigger Out (BNC, waveform capture rate, test pulse) [2-channel only]

The BNC port can output a signal that reflects the current waveform capture rate of the oscilloscope at each trigger or a pass/fail test pulse.

## 5. USB Device (SCPI, remote control) [2-channel only]

The oscilloscope support SCPI remote control commands, user can control the oscilloscope through this interface.

## 1. Handle (carrying) [4-channel only]

Pull up the handle vertically for easy carrying of the instrument. When you do not need the handle, press it down.

## 2. LAN (network, remote control) [4-channel only]

The instrument can be connected to network via this interface to perform remote control.

## 3. USB Device (SCPI, remote control) [4-channel only]

The oscilloscope support SCPI remote control commands, user can control the oscilloscope through this interface

## 4. USB Host (function generators, SDG, SAG1021I) [4-channel only]

Communicate with external function generators (SIGLENT SDG and SAG1021I)

## 5. Safety lock Hole (security lock) [4-channel only]

You can lock the instrument to a fixed location using the security lock (please buy it yourself) via the lock hole.

## 6. AC Power Socket (power cord, 100-240V) [4-channel only]

AC power input terminal. The power requirements of this oscilloscope are 100 -240 V, 50/60/400 Hz. Use the power cord provided with the instrument to connect it to AC power.

## 7. Pass/Fail or Trigger Out (BNC, waveform capture rate, test pulse) [4-channel only]

The BNC port can output a signal that reflects the current waveform capture rate of the oscilloscope at each trigger or a pass/fail test pulse.

## LAN (network, remote control) [4-channel only]

The instrument can be connected to network via this interface to perform remote control.

## 5. Pass/Fail or Trigger Out (BNC, waveform capture rate, test pulse) [4-channel only]

The BNC port can output a signal that reflects the current waveform capture rate of the oscilloscope at each trigger or a pass/fail test pulse.

## 6. AC Power Socket (power cord, 100-240V) [4-channel only]

AC power input terminal. The power requirements of this oscilloscope are 100 -240 V, 50/60/400 Hz. Use the power cord provided with the instrument to connect it to AC power.

## Horizontal (roll mode, timebase, search function, white triangle) [2+4-channel]

Quickly enter the roll mode. The timebase range is from 50mS/div to 100S/div.

Enable or disable search function. This function can search for the events that users specify in the acquired data, the results are displayed with white triangle symbol.

## Horizontal Position Knob (horizontal delay, trigger point, reset) [2+4-channel]

adjust horizontal position. Turn the knob to change the horizontal delay time, waveforms of all channels will move horizontally with the trigger point. Press down this knob to quickly reset the horizontal delay to Zero.

## Horizontal Scale Knob (time base, zoom, expanded, compressed) [2+4-channel]

adjust the horizontal time base. Turn clockwise to reduce the time base and turn counterclockwise to increase the time base. During the modification, waveforms of all the channels will be displayed in expanded or compressed mode and the time base message at the upper-left side of the screen would change accordingly. Press down this knob to quickly turn on Zoom function.

## Vertical (analog input channels, colors, channel connectors) [2+4-channel]

Analog input channels. The two channels are marked by different colors which are also used to mark both the corresponding waveforms on the screen and the channel input connectors. 1

## Vertical Position Knob (vertical position, reset to zero) [2+4-channel]

adjust the vertical position of the current channel waveform. Turn clockwise to increase the position and turn counterclockwise to decrease. During the modification, the waveform would move up and down and the position message at the lower-left corner of the screen would change accordingly. Press down this knob to quickly reset the vertical position to zero. Zero

## Vertical Variable Knob (vertical scale, coarse, fine) [2+4-channel]

adjust the vertical scale of the current channel. Turn clockwise to decrease the scale and turn counterclockwise to increase. During the modification, the amplitude of the waveform would enlarge or reduce and the scale information at the right side of the screen would change accordingly. Press down this knob to quickly switch the vertical scale adjustment modes between "Coarse" and "Fine". Variahle

## MATH button (addition, subtraction, multiplication, FFT, differential, integral, square root) [2+4-channel]

press the button to enter the MATH function menu. The oscilloscope provides addition, subtraction, multiplication, FFT, differential, integral and square root operations. Math

## REF button (reference waveform, compare, digital channels) [2+4-channel]

press the button to enter the REF function menu. A reference waveform can be displayed and compared against other waveforms. Ref
:Press the button to open the digital channel function menu (Optional function). The SDS1000X-E (4-channel scope) supports 16 digital channels. Digital

## Trigger (trigger mode, auto, normal, single, advanced trigger) [2+4-channel]

press the button to enter the TRIGGER function menu. The oscilloscope provides abundant advanced trigger functions
press the button to set the trigger mode to Auto, Normal, Single.

## Trigger Level Knob (trigger level, 50%, reset) [2+4-channel]

adjust the trigger level. Turn clockwise to increase the level and turn counterclockwise to reduce the level. During the modification, the trigger level line would move up and down and the value in the trigger level message box at the up-right corner of the screen would change accordingly. Press down the knob to quickly reset the trigger level to center of the waveform. 50%

## Run Control (auto setup, run stop, acquisition state) [2+4-channel]

## Auto Setup (auto setting, vertical scale, horizontal time base, trigger mode) [2+4-channel]

press this key to enable the waveform auto setting function. The oscilloscope will automatically adjust the vertical scale, horizontal time base and trigger mode according to the input signal to realize optimum waveform display. The input signal frequency must be higher than 20 Hz with an amplitude greater than 8 mV. When several channels are connected to signals, select the channel with the lowest frequency.

## Run Stop (acquisition, run, stop, yellow, red) [2+4-channel]

press the button to set the acquisition state to Run or Stop. In RUN state, the key is illuminated in yellow.
In STOP state, the key is illuminated in red.

## 1. Universal Knob Adjust the waveform intensity (Display/Persist, intensity) [2+4-channel]

You can press the Display/Persist button; press the Next Page soft key to go to the second page of the DISPLAY function menu; press the Intensity soft key and then turn the Universal Knob to adjust the waveform intensity.

2.Select the desired submenu.

In menu operation, press any menu soft key and turn the Universal Knob to select the desired submenu under the menu and push down the knob to confirm the current submenu. Turn clockwise to up the intensity and counterclockwise to down.

## 3. Universal Knob Modify parameters (parameter modification, scale, offset) [2+4-channel]

After having chosen a parameter, turn the Universal Knob to modify the value. Turn clockwise to increase the intensity and counterclockwise to reduce. In addition, it can also be used to adjust scale and offset of MATH and REF.

## 4. Universal Knob Choose file or directory or input filename (file system, character selection) [2+4-channel]

After having entered the file system, turn the Universal Knob to select the desired file or directory. When inputting filename, turn the Universal Knob to select the desired character and the push the knob to confirm.

## Menu (Cursors, Display, Utility, Measure, Acquire, Save/Recall, History, Decode) [2+4-channel]

- **Cursors**: Press to enter the CURSOR function menu. The oscilloscope provides manual and track cursor mode.
- **Display/Persist**: Press to enter the DISPLAY function menu and quickly enable the persist function. User can set the grid, intensity, graticule, and transparence.
- **Utility**: Press to enter the UTILITY function menu to look at the system status, do self-calibration, set the sound, language and so on.
- **Clear Sweeps**: The button is a shortcut key for clear function. When the measurement statistics is ON, press the button to clear the count and recount it. When persist is enabled, press the button to clear persist.
- **Measure**: Press the button to enter the MEASURE function menu to set the measurement parameters, all measurement, statistics and gate.
- **Acquire**: Press the button to enter the ACQUIRE function menu to set the acquisition mode, memory depth, wave interpolation and so on.
- **Save/Recall**: Press the button to enter the SAVE/RECALL function menu to save setups, waveforms, pictures, or CSV files, binary data, matlab files, and default key presets to internal memory or USB flash driver.
- **Default**: Press the button to reset the oscilloscope to user default setup.
- **History**: Press the button to enter the history mode. In history mode, it can record most 80000 frames waveforms. If sequence function is enabled, it only records the frames which you set, the most you can set is 80000.
- **Decode**: Press the button to enter the DECODE function menu. The oscilloscope supports I2C, SPI, UART, CAN and LIN serial bus decode.
- **Navigate**: Press the button to turn off or turn on the navigate function. SDS1000X-E (4-channel scope) and SDS1000X-U support three navigate types: time, search event, history frame.

## Help (online help, multi-language, button press) [2+4-channel]

The oscilloscope has an on line help function that supplies multi-language help information.
You can access the help function by pressing any button for 2 seconds and a help window will explain the function. Also all of the submenus include help information.

## 1. Product Logo (SIGLENT trademark) [2+4-channel]

SIGLENT is the registered trademark of SIGLENT TECHNOLOGIES CO., LTD.

## 2. Channel Label/Waveform (channel colors, waveform color) [2+4-channel]

Different channels are marked by different colors and the color of the waveform complies with the color of the channel.

## 3. Trigger Status (Ready, Auto, Stop, Arm, Trig'd, FStop) [2+4-channel]

Available trigger status includes Ready, Auto, Stop, Arm, Trig'd, FStop.

## 4. Horizontal Time Base (time per grid, HORIZONTAL SCALE Knob, ns to s) [2+4-channel]

- Represent the time per grid on the horizontal axis on the screen.
- Use the HORIZONTAL SCALE Knob to adjust the parameter. The available range is from 1.0 ns to 100 s for SDS1000X-E; while from 2.0 ns to 100s for SDS1000X-U.

## 5. Horizontal Position (Delay) (trigger delay, reset to zero) [2+4-channel]

Turn the Horizontal Position Knob to adjust the parameter. Push the knob to set the value to 0 automatically.

## 6. Trigger Delay Label (trigger delay indication) [2+4-channel]

Indicate the trigger delay on the waveform.

## 7. Frequency Counter (frequency value, trigger channel) [2+4-channel]

Display the frequency value of the trigger channel.

## 8. Sampling Rate/ Memory Depth (Sa, Curr, sample rate, memory depth) [2+4-channel]

Display the current sampling rate and memory depth. Sa means the current sampling rate and Curr means the current memory depth.

## 9. Trigger Setup (trigger type, source, condition, coupling, level) [2+4-channel]

Trigger Type: display the current trigger type. The trigger type names display by the abbreviation when the name is too long to display.
Trigger source: display the currently trigger source. Different channels display in different color.
Trigger condition: display the current trigger condition.
Trigger coupling: display the current trigger coupling. Available trigger coupling mode: DC, AC, HF Reject, LF Reject.
Trigger level: display the current value of trigger level. Push the knob to set the trigger to the 50% of the waveform amplitude automatically.

## 10. Channel Setup (probe attenuation, input impedance, 1MΩ) [2+4-channel]

Probe attenuation factor: display the current probe attenuation factor of the channel. Available probe attenuation factors: 0.1X, 0.2X, 0.5X, 1X …properties 2000X, 5000X, 10000X.
Input impedance: display the current input impedance of the channel. Input impedance that available: 1MΩ.

## Channel coupling (DC, AC, GND) [2+4-channel]

display the current channel coupling of the channel. Channel coupling that available: DC, AC, and GND.

## Vertical Scale (Vertical Scale Knob, volts per division) [2+4-channel]

display the current vertical scale of the channel. Turn the Vertical Scale Knob to adjust the value.

## 11. Trigger Level Label (trigger level position, +4.5div, -4.5div) [2+4-channel]

Display the position of trigger level, the color is the same to the trigger channel. It can move from +4.5div to -4.5div of the screen center.

## 12. I/O status (USB Host, LAN, WLAN connection indicators) [2+4-channel]

Indicate that the USB Host is connected.
Indicate that the LAN port is connected.
Indicate that the LAN port is disconnected.
Indicate that the WLAN port is connected.
Indicate that the WLAN port is disconnected.

## 13. Menu (function menu, soft key) [2+4-channel]

Display the corresponding function menu of the selected button. Press the corresponding soft key to set the oscilloscope.

## Security Lock (lock hole, key, fixed location) [2+4-channel]

If needed, you can use the security lock (please buy it yourself) to lock the oscilloscope to a fixed location. The method is as follows, align the lock with the lock hole and plug it into the lock hole vertically, turn the key clockwise to lock the oscilloscope and then pull the key out.

## Vertical System (analog channels, vertical control, CH1) [2+4-channel]

## Vertical System Enable the Channel (CH1, vertical control area, channel label) [2+4-channel]

The oscilloscope provides 2/4 analog input channels and provides independent vertical control system for each channel. As the vertical system setting methods of every channel is the same, this chapter takes CH1 as an example to introduce the setting method of the vertical system.

Connect a signal to the CH1 channel connector; and then press the CH1 button in the vertical control area (VERTICAL) at the front panel to enable CH1.

The channel setting menu is displayed at the bottom of the screen and the channel label at the right side of the screen. The information displayed in the channel label is related to the current channel setting.

After the channel is turned on, modify the parameters such as the vertical scale, the horizontal time base and the trigger mode according to the input signal to make the waveform display easy to observe and measure.

Note: to turn off the channel, press the channel button twice.

## Vertical System Adjust Scale (coarse, fine, 1-2-5 step, vertical resolution) [2+4-channel]

The vertical scale can be adjusted in Coarse or Fine mode.

- Coarse adjustment (take counterclockwise as an example): set the vertical scale in 1 -2 -5 step namely 500uV/div, 1 mV/div, 2 mV/div, 5 mV/div, 10 mV/div …10 V/div.

Fine adjustment: further adjust the vertical scale within a relatively smaller range to improve vertical resolution. For example: 2 V/div, 1.98V/div, 1.96V/div, 1.94 V/div …1 V/div.

- If the amplitude of the input waveform is a little bit greater than the full scale under the current scale and the amplitude would be a little bit lower if the next scale is used, fine adjustment can be used to improve the amplitude of waveform display to view signal details.

Press the CH1 button on the front panel; then press the Adjust soft key to select the desired mode. Turn the VERTICAL Variable Knob to adjust the vertical scale (clockwise to reduce the scale and counterclockwise to increase).

The scale information in the channel label at the right side of the screen will change accordingly during the adjustment. The adjustable range of the vertical scale is related to the probe ratio currently set. By default, the probe attenuation factor is 1X and the adjustable range of the vertical scale is from 500uV/div to 10 V/div.

Note: push the VERTICAL Variable Knob to quickly switch between Coarse and Fine adjustments.

## Vertical Position (Volts Pos, vertical position range) [2+4-channel]

Turn the VERTICAL Position Knob to adjust the vertical position of the channel waveform. Turn the knob clockwise to increase the vertical position and the channel waveform moves up while counterclockwise to reduce the vertical position and the waveform moves down. Push the knob to set the vertical position of the channel waveform to zero.

During the adjustment, the vertical position information Volts Pos displays at the bottom of the screen. The table below shows the range of vertical position according to the volt scale.

| Oscilloscope | Volt Scale | Range of Vertical Position |
|----------------|-------------------------|------------------------------|
| SDS1000X-E | 500 μV/div ~ 100 mV/div | ±2V |
| SDS1000X-E | 102 mV/div ~ 1 V/div | ±20 V |
| SDS1000X-E | 1.02 V/div ~ 10 V/div | ±200 V |
| SDS1000X-U | 1mV/div ~ 200 mV/div | ±2 V |
| SDS1000X-U | 206 mV/div ~ 10 V/div | ±100 V |

## Coupling (DC, AC, GND, filter, coupling mode) [2+4-channel]

Set the coupling mode to filter out the undesired signals. For example, the signal under test is a square waveform with DC offset.

- When the coupling mode set to DC: the DC and AC components of the signal under test can both pass the channel.
- When the coupling mode set to AC: the DC components of the signal under test are blocked.
- When the coupling mode set to GND: the DC and AC components of the signal under test are both blocked.

Press the CH1 button on the front panel; then press the Coupling softkey and turn the Universal Knob to select the desired coupling mode. The default setup is DC.

The current coupling mode is displayed in the channel label at the right side of the screen. You can also press the Coupling softkey y continuously to switch the coupling mode.

## Bandwidth Limit (Full, 20M, noise reduction, high frequency) [2+4-channel]

Set the bandwidth limit to reduce display noise. For example, the signal under test is a pulse with high frequency oscillation.

- When the bandwidth limit set to Full, the high frequency components of the signal under test can pass the channel.
- When the bandwidth limit set to 20M, the high frequency components that exceed 20 MHz are attenuated.

Press the CH1 button on the front panel; then press the BW Limit softkey to select Full or 20M. The default setup is Full. When bandwidth limit is enabled, the character B will be displayed in the channel label at the right side of the screen.
SDS1000X-E has full BW with all V/div settings including 500uV/div to 2mV/div.

## Probe attenuation (attenuation factor, probe ratio, custom) [2+4-channel]

Set the probe attenuation factor to match the type of the probe that you are using to ensure correct vertical readouts.
Press the CH1 button on the front panel; then press the Probe softkey and turn the Universal Knob to select the desired value and push the knob to confirm. The default setup is 1X.

The current probe attenuation factor is displayed in the channel label at the right side of the screen. You can also press the Probe softkey y continuously to switch the probe attenuation factor.

The table shows the probe attenuation factor

| Menu | Attenuation Factor |
|--------|----------------------|
| 0.1X | 0.1 : 1 |
| 0.2X | 0.2 : 1 |
| 0.5X | 0.5 : 1 |
| 1X | 1 : 1 |
| 2X | 2 : 1 |
| … | … |
| 5000X | 5000 : 1 |
| 10000X | 10000 : 1 |
| Custom | 1000000:1~0.000001:1 |

You can also customize the probe attenuation factor. Press the Probe softkey, select Custom, and then press the Custom softkey to select Custom or Custom Fine. First, select Custom and turn the Universal Knob to achieve rough adjustment; and then select Custom Fine and turn the Universal Knob to achieve fine adjustment.

## Input Impedance (1MΩ, passive probes, loading effect) [2+4-channel]

The channel input impedance is 1MΩ.

- Impedance setting to 1MΩ is for use with many passive probes and for general-purpose measurements. The higher impedance minimizes the loading effect of the oscilloscope on the device under test.

The current channel input impedance is displayed in the channel label at the right side of the screen.

## Channel Unit softkey (V, A, amplitude display unit) [2+4-channel]

Select the amplitude display unit for the current channel. The available units are V and A. When the unit is changed, the unit displayed in the channel label will change accordingly.

1. Press CH1 button on the front panel to enter the CH1 function menu.
2. Press the Next Page softkey to enter the second page of the CH1 function menu.
3. Press the Unit softkey to select the desired unit V or A.

The default setup is V.

## Channel Deskew softkey (deskew, ±100ns) [2+4-channel]

The Deskew softkey is used to compensate for phase differences or time delays between input channels, which can occur due to varying cable lengths or different probe signal propagation delays. This feature allows you to shift the timing of an analog channel relative to others within a range of ±100 ns to ensure that signals appear correctly correlated on the display.

The valid range of each analog channel is ±100ns.

1. Press CH1button on the front panel to enter the CH1 function menu.
2. Press the Next Page softkey to enter the second page of the CH1 function menu.
3. Press the Deskew softkey. Then turn the Universal Knob to change deskew.

## Channel Invert softkey (invert, voltage values, trigger settings) [2+4-channel]

When Invert softkey is set to On, the voltage values of the displayed waveform are inverted. Invert affects how a channel is displayed and it keeps the trigger settings.
Inverting a channel also changes the result of any math function selected and measure function.

## Channel measure softkey function (measure, invert display) [2+4-channel]

1. Press CH1button on the front panel to enter the CH1 function menu.
2. Press the Next Page softkey to enter the second page of the CH1 function menu.
3. Press the Invert softkey to turn on or off the invert display.

## Channel Trace softkey Visible/Hidden (trace, visible, hidden) [2+4-channel]

Set whether the current channel waveform is visible.

1. Press CH1 button on the front panel to enter the CH1 function menu.
2. Press the Next Page softkey to enter the second page of the CH1 function menu.
3. Press the Trace softkey to visible or hidden the channel waveform

## Channel Label softkey (label text, source, display, 20 characters) [4-channel only]

SDS1000X-E (4-channel) supports setting label text for channels.

- 1 Press CH1 → Label to enter the LABEL function menu.
- 2 Press the Source softkey to select the source.
- 3 Press the Display softkey to turn on or off the label for the current channel.
- 4 Press the Label Setting softkey to enter the Text Input function menu. The length of the label is limited to 20 characters. The characters beyond this length will not be displayed. When the "Display" option is set to "on", the

## Horizontal Scale (time base, HORIZONTAL Scale Knob, sample rate, zoom) [2+4-channel]

Turn the HORIZONTAL Scale Knob on the front panel to adjust the horizontal time base. Turn clockwise to reduce the horizontal time base and turn counterclockwise to increase.

The time base information at the upper left corner of the screen will change accordingly during the adjustment. The range of the SDS1000X-E horizontal scale is from 1ns/div to 100s/div. The range of the SDS1000X-U horizontal scale is from 2ns/div to 100s/div.

The Horizontal Scale Knob works (in the Normal time mode) while acquisitions are running or when they are stopped. When in run mode, adjusting the horizontal scale knob changes the sample rate. When stopped, adjusting the horizontal scale knob lets you zoom into acquired data.

## Horizontal Delay (trigger point, delay time, memory depth) [2+4-channel]

Turn the Horizontal Position Knob on the front panel, the trigger point (solid inverted triangle) will move horizontally. The trigger point moves horizontally to the right when it rotates clockwise, while moves to left when it rotates counter-clockwise. Press down this knob to quickly reset the trigger delay.

When changing the horizontal delay, the delay time displayed in the information bar at the top of the screen changes in real time, indicating the distance between the time reference point and the trigger point. The amount of delay range available depends on the time/div selected and memory depth.

## Roll Mode (roll, strip chart, low-frequency, no trigger) [2+4-channel]

Press the Roll button to enter the roll mode.

In Roll mode the waveform moves slowly across the screen from right to left. It only operates on time base settings of 50 ms/div and slower. If the current time base setting is faster than the 50 ms/div limit, it will be set to 50 ms/div when Roll mode is entered.

In Roll mode there is no trigger. The fixed reference point on the screen is the right edge of the screen and refers to the current moment in time. Events that have occurred are scrolled to the left of the reference point. Since there is no trigger, no pre -trigger information is available.

If you would like to stop the display in Roll mode, press the Run/Stop button. To clear the display and restart an acquisition in Roll mode, press the Run/Stop button again.

Use Roll mode on low-frequency waveforms to yield a display much like a strip chart recorder. It allows the waveform to roll across the display.

## Zoom Mode (zoom, expanded, normal time base, zoom time base, box) [2+4-channel]

Zoom is a horizontally expanded version of the normal display. You can use Zoom to locate and horizontally expand part of the normal window for a more detailed (higher- resolution) analysis of signals.

Press the HORIZONTAL Scale Knob on the front panel to turn on the zoom function, and press the button again to turn off the function. When Zoom function is on, the display divides in half. The top half of the display shows the normal time base window and the bottom half displays a faster Zoom time base window.

## Normal time base Zoom time base (normal window, zoom window, expanded, box) [2+4-channel]

The area of the normal display that is expanded is outlined with a box and the rest of the normal display is ghosted. The box shows the portion of the normal sweep that is expanded in the lower half.

To change the time base for the Zoom window, turn the Horizontal Scale Knob. The Horizontal Scale Knob controls the size of the box. The Horizontal Position Knob sets the left -to- right position of the zoom window. The delay value, which is the time displayed relative to the trigger point is momentarily displayed in the upperright corner of the display when the Horizontal Position Knob is turned. Negative delay values indicate you're looking at a portion of the waveform before the trigger
event, and positive values indicate you're looking at the waveform after the trigger event.
To change the time base of the normal window, turn off Zoom; then, turn the Horizontal Scale Knob.

## Run Control (Run/Stop, Single, acquisition, trigger) [2+4-channel]

Press the Run/Stop or Single button on the front panel to run or stop the sampling system of the scope.

- When the Run/Stop button is green, the oscilloscope is running, that is, acquiring data when trigger conditions are met. To stop acquiring data, press the Run/Stop button. When stopped, the last acquired waveform is displayed.
- When the Run/Stop button is red, data acquisition is stopped. Red "Stop" is displayed next to the trademark logo in the status line at the top of the display. To start acquiring data, press Run/Stop.
- To capture and display a single acquisition (whether the oscilloscope is running or stopped), press Single. The Single run control lets you view singleshot events without subsequent waveform data overwriting the display. Use Single when you want maximum memory depth for pan and zoom.

When you press Single, the display is cleared, the trigger mode is temporarily set to Normal (to keep the oscilloscope from auto- triggering immediately), the trigger circuitry is armed, the Single key is illuminated, and the oscilloscope waits until a user defined trigger condition occurs before it displays a waveform.
When the oscilloscope triggers, the single acquisition is displayed and the oscilloscope is stopped (the Run/Stop button is illuminated in red).
Press Single again to acquire another waveform.

## Sampling Theory (Nyquist, sampling frequency, aliasing, bandwidth) [2+4-channel]

The Nyquist sampling theorem states that for a limited bandwidth (band- limited) signal with maximum frequency fMAX, the equally spaced sampling frequency fS must be greater than twice the maximum frequency fMAX, in order to have the signal be uniquely reconstructed without aliasing.

f MAX = f S/2 = Nyquist frequency (fN) = folding frequency

## Sample Rate (2GSa/s, Nyquist Frequency, waveform distortion, aliasing, leakage) [2+4-channel]

The maximum sample rate of the oscilloscope is 2GSa/s. The actual sample rate of the oscilloscope is determined by the horizontal scale. Turn the Horizontal Scale Knob to adjust the sample rate.

The actual sample rate is displayed in the information area at the upperright corner of the screen.

The influence on the waveform when the sample rate is too low:

1. Waveform Distortion: when the sample rate is too low, some waveform details are lost and the waveform displayed is rather different from the actual signal.
2. Waveform Confusion: when the sample rate is lower than twice the actual signal frequency (Nyquist Frequency), the frequency of the waveform rebuilt from the sample data is lower than the actual signal frequency. The most common aliasing is the jitter on fast edge.
3. Waveform Leakage: when the sample rate is too low, the waveform rebuilt from the sample data does not reflect all the actual signal information.

## Bandwidth and Sample Rate (3 dB, Gaussian frequency response, fS = 4fBW) [2+4-channel]

An oscilloscope's bandwidth is typically described as the lowest frequency at which input signal sine waves are attenuated by 3 dB (- 30% amplitude error).

At the oscilloscope bandwidth, sampling theory says the required sample rate is fS = 2f BW. However, the theory assumes there are no frequency components above fMAX (fBW in this case) and it requires a system with an ideal brickwall frequency response.
However, digital signals have frequency components above the fundamental frequency (square waves are made up of sine waves at the fundamental frequency and an infinite number of odd harmonics), and typically, for 500 MHz bandwidths and below, oscilloscopes have a Gaussian frequency response.

So, in practice, an oscilloscope's sample rate should be four or more times its bandwidth: f S = 4fBW. This way, there is less aliasing, and aliased frequency components have a greater amount of attenuation.

## Memory Depth (waveform points, storage ability, 14 Mpts, acquisition memories) [2+4-channel]

Memory depth refers to the number of waveform points that the oscilloscope can store in a single trigger sample and it reflects the storage ability of the sample memory.

Press the Acquire button on the front panel; press the Mem Depth softkey and then turn the Universal Knob to select the desired value and push down the knob to confirm. Press the Mem Depth softkey continually can also select the desired value.

The actual memory depth is displayed in the information area at the upperright corner of the screen. Since the oscilloscope of SDS1000X-E has two acquisition memories, when only one channel is on, the maximal memory depth is up to 14 Mpts. SDS1000X-U only has one acquisition memory, when only one channel is on, the maximal memory depth is up to 14 Mpts.

The maximum storage depth in single channel mode is twice that in dual channel mode, as shown in the following table:

| SDS1000X-E | SDS1000X-E | SDS1000X-U | SDS1000X-U | SDS1000X-U |
|----------------------|--------------------|----------------------|--------------------|-----------------------------|
| Single Channel Mode | Dual Channel Mode | Single Channel Mode | Dual Channel Mode | Three or Four Channel Mode |
| 14k | 7k | 14k | 7k | 3.5k |
| 140k | 70k | 140k | 70k | 35k |
| 1.4M | 700k | 1.4M | 700k | 350k |
| 14M | 7M | 14M | 7M | 3.5M |

The relation of memory depth, sample rate and waveform length fulfills the equation below:

Memory depth = sample rate (Sa/s) × waveform length (s/div × div)

## Sampling Mode (real-time sample, 1GSa/s, pan, zoom) [2+4-channel]

The oscilloscope only supports real-time sample. In this mode, the oscilloscope samples and displays waveform within a trigger event. The maximum real-time sample rate is 1GSa/s.
Press the RUN/STOP button to stop the sample, the oscilloscope will hold the last display. At this point, you can still use the vertical control and horizontal control to pan and zoom the waveform.

## Interpolation Method (Sinx/x, X, dots, connecting points) [2+4-channel]

Under real-time sampling, the oscilloscope acquires the discrete sample values of the waveform being displayed. In general, a waveform of dots display type is very difficult to observe. In order to increase the visibility of the signal, the digital oscilloscope usually uses the interpolation method to display a waveform.

Interpolation method is a processing method to "connect all the sampling points", and using some points to calculate the whole appearance of the waveform. For real-time sampling interpolation method is used, even if the oscilloscope in a single captures only a small number of sampling points. The oscilloscope can use interpolation method for filling out the gaps between points, to reconstruct an accurate waveform.

Press the Acquire button on the front panel to enter the ACQUIRE Function menu; then press the Interpolation softkey to select Sinx/x or X.

- X: In the adjacent sample points are directly connected on a straight line. This method is only confined to rebuild on the edge of signals, such as square wave.
- Sinx/x: Connecting the sampling points with curves has stronger versatility. Sinx interpolation method uses mathematical processing to calculation results in the actual sample interval. This method bending signal waveform, and make it produce more realistic regular shape than pure square wave and pulse. When the sampling rate is 3 to 5 times the bandwidth of the system. Recommended Sinx/s interpolation method.

## Acquisition Mode (Normal, Peak Detect, Average, Eres) [2+4-channel]

The acquisition mode is used to control how to generate waveform points from sample points. The oscilloscope provides the following acquisition mode: Normal, Peak Detect, Average and Eres.

1. Press the Acquire button on the front panel to enter the ACQUIRE function menu;
2. Press the Acquisition softkey; then turn the Universal Knob to select the desired acquisition mode and push down the knob to confirm. The default setup is Normal.

## Normal (equal time interval, default) [2+4-channel]

In this mode, the oscilloscope samples the signal at equal time interval to rebuild the waveform. For most of the waveforms, the best display effect can be obtained using this mode. It is the default acquisition mode.

## Peak Detect (envelope, narrow pulse, sample period) [2+4-channel]

In this mode, the oscilloscope acquires the maximum and minimum values of the signal within the sample interval to get the envelope of the signal or the narrow pulse of the signal that might be lost. In this mode, signal confusion can be prevented but the noise displayed would be larger.
In this mode, the oscilloscope can display all the pulses with pulse widths at least as wide as the sample period.

## Average (waveform average, random noise, vertical resolution, 4 to 1024) [2+4-channel]

In this mode, the oscilloscope averages the waveforms from multiple samples to reduce the random noise of the input signal and improve the vertical resolution. The greater the number of averages is, the lower the noise will be and the higher the vertical resolution will be but the slower the response of the displayed waveform to the waveform changes will be.
The available range of averages is from 4 to 1024 and the default is 16. When Average mode is selected, press Averages and turn the Universal knob or press the softkey continually to set the desired average time.

## Eres (ultra-sample, low-pass filter, dot average, single-shot) [2+4-channel]

This mode uses a kind of ultra -sample technique to average the neighboring points
of the sample waveform to reduce the random noise on the input signal and generate much smoother waveforms on the screen. This is generally used when the sample rate of the digital converter is higher than the storage rate of the acquisition memory.

Eres mode can be used on both single- shot and repetitive signals and it does not slow waveform update. This mode limits the oscilloscope's realtime bandwidth because it effectively acts like a low- pass filter.

Note: "Average" and "Eres" modes use different averaging methods. The former uses "Waveform Average" and the latter uses "Dot Average".

## Horizontal Format (YT, XY, volt-versus-time, volt-versus-volt) [2+4-channel]

Press the Acquire button on the front panel; then press the XY soft key to set the XY(On) or YT(Off) mode. The default setup is YT.

## YT (normal viewing mode, trigger point, pre-trigger, post-trigger) [2+4-channel]

It is the normal viewing mode for the oscilloscope. In the Normal time mode, signal events occurring before the trigger are plotted to the left of the trigger point and signal events after the trigger plotted to the right of the trigger point.

## XY (X-axis, Y-axis, Lissajous, phase deviation, frequency relationship) [2+4-channel]

XY mode changes the display from a voltversus- time display to a voltversusvolt display. Channel 1 amplitude is plotted on the X- axis and Channel 2 amplitude is plotted on the Y- axis, the two channels will be turned on or off together.
You can use XY mode to compare frequency and phase relationships between two signals. XY mode can also be used with transducers to display strain versus displacement, flow versus pressure, volts versus current, or voltage versus frequency.
The phase deviation between two signals with the same frequency can be easily measured via Lissajous method. The figure below shows the measurement schematic diagram of the phase deviation
According to sinθ=A/B or C/D (wherein, θ is the phase deviation angle between the two channels and the definitions of A, B, C and D are as shown in the figure above), the phase deviation angle is obtained, that is: θ=±arcsin (A/B) or ±arcsin (C/D)
If the principal axis of the ellipse is within quadrant I and III, the phase deviation angle obtained should be within quadrant I and IV, namely within (0 to π/2) or (3π/2 to 2π). If the principal axis of the ellipse is within quadrant II and IV, the phase deviation angle obtained should be within quadrant II and III, namely within (π/2 to π) or (π to 3π/2).
X -Y function can be used to measure the phase deviation occurred when the signal under test passes through a circuit network. Connect the oscilloscope to the circuit to monitor the input and output signals of the circuit.

## Sequence Mode (acquisition mode, waveform capture rate, 400000 wfs/s, memory segment) [2+4-channel]

Sequence is also a kind of acquisition mode, which does not display waveform during sampling process. It improves the waveform capture rate, and the maximal capture rate is 400, 000 wfs/s. So it can capture the small probability event effectively.

The oscilloscope runs and fills a memory segment for each trigger event. The oscilloscope is busy acquiring multiple segments. The oscilloscope continues to trigger until memory is filled, and then display the waveforms on the screen.

To use the sequence mode, the HORIZONTAL Format must be set to YT.

Do the following steps to use the sequence mode.

1. Press the Acquire button on the front panel to enter the ACQUIRE function menu;
2. Press the Sequence softkey to enter the SEQUENCE function menu.
3. Press the Segments Set softkey; and then turn the Universal Knob to select the desired value.

Do the following steps to replay the sequence waveform under history mode:

1. Press the History softkey to enable HISTORY function.
2. Press the List softkey to turn on the list display. The list records the acquisition time of every frame and shows the frame number that displaying on the screen.
3. Press the Frame No. softkey; and then turn the Universal Knob to select the frame to display.
4. Press the softkey to replay the waveform from the current frame to 1.
5. Press the softkey to stop replay.
6. Press the softkey to replay the waveform from the current frame to the last frame.

## Trigger (trigger condition, stable trigger, acquisition memory, trigger types) [2+4-channel]

For trigger, you set certain trigger condition according to the requirement and when a waveform in the waveform stream meets this condition, the oscilloscope captures this waveform as well as the neighboring part and displays them on the screen. For digital oscilloscope, it displays waveform continuously no matter whether it is stably triggered, but only stable trigger can ensures stable display. The trigger circuit ensures that every time base sweep or acquisition starts from the input signal and the user-defined trigger condition, namely every sweep is synchronous to the acquisition and the waveforms acquired overlap to display stable waveform.

The following is the schematic diagram of the acquisition memory. As shown in the figure below, the position of the trigger event is determined by the reference time point and the delay setting.

Trigger setting should be based on the features of the input signal, thus you need to have some knowledge of the signal under test to quickly capture the desired waveform.

The oscilloscope provides abundant advanced trigger functions which can help you to focus on the desired waveform details. These trigger types are edge, slope, pulse, video, window, interval, dropout, runt, pattern and serial trigger. This chapter will mainly introduce all these trigger functions which mentioned above in details and tell you how to set the trigger conditions to capture desired waveform.

## Trigger Source (analog channels, EXT, EXT/5, AC Line) [2+4-channel]

The 2-channel oscilloscope's trigger source includes analog channels, EXT, EXT/5 and AC Line. The 4-channel oscilloscope's trigger source includes analog channels and AC Line.

Press the Setup button on the front panel to enter the TRIGGER function menu; press the Source softkey and then turn the Universal Knob to select the desired trigger source.

The current trigger source is displayed at the upper right corner of the screen. Select channel with signal input as trigger source to obtain stable trigger.

## Analog channel input (trigger source, analog channels) [2+4-channel]

Signals input from analog channels can all be used as the trigger source. No matter whether the input of the channel selected is enabled, the channel can work normally.

## External trigger input (EXT TRIG, trigger level, -8 div to +8 div) [2-channel only]

External trigger source can be used to connect external trigger signal to the EXT TRIG channel when all of the four channels are sampling data. The trigger signal (such as external clock and signal of the circuit to be tested) will be connected to EXT and EXT/5 trigger source via the [EXT TRIG] connector. EXT/5 trigger source attenuates the signal by a factor of 5. It extends the trigger level. You can set the trigger condition within the range of trigger level (-8 div to +8 div).

## AC line (AC power, power supply, transformer) [2+4-channel]

The trigger signal is obtained from the AC power input of the oscilloscope. This kind of signals can be used to display the relationship between signal (such as illuminating device) and power (power supply device). For example, it is mainly used in related measurement of the power industry to stably trigger the waveform output from the transformer of a transformer substation.

Note: to select stable channel waveform as the trigger source to stabilize the display.

## Trigger Mode (auto, normal, single, pre-trigger, post-trigger, FIFO) [2+4-channel]

The oscilloscope's trigger mode includes auto, normal and single. Trigger mode affects the way in which the oscilloscope searches for the trigger

After the oscilloscope starts running, the oscilloscope operates by first filling the pre -trigger buffer. It starts searching for a trigger after the pre-trigger buffer is filled and continues to flow data through this buffer while it searches for the trigger. While searching for the trigger, the oscilloscope overflows the pre-trigger buffer and the first data put into the buffer is first pushed out (First Input First Out, FIFO).

When a trigger is found, the pre- trigger buffer contains the events that occurred just before the trigger. Then, the oscilloscope fills the posttrigger buffer and displays the acquisition memory.

Press the Auto, Normal and the Single buttons on the front panel to select the desired trigger mode, and the corresponding status light will be lighted.

- In the Auto trigger mode (the default setting), if the specified trigger conditions are not found, triggers are forced and acquisitions are made so hat signal activity is displayed on the oscilloscope.

The Auto trigger mode is appropriate when:

- Checking DC signals or signals with unknown levels or activity.
- When trigger conditions occur often enough that forced triggers are unnecessary.
- In the Normal trigger mode, triggers and acquisitions only occur when the specified trigger conditions are found. Otherwise, the oscilloscope holds the original waveform and waits for the next trigger.

The Normal trigger mode is appropriate when:

- You only want to acquire specific events specified by the trigger settings.
- Triggering on an infrequent signal from a serial bus (for example, I2C, SPI, CAN, LIN, etc.) or another signal that arrives in bursts. The Normal trigger mode lets you stabilize the display by preventing the oscilloscope from auto- triggering.
- In the Single trigger mode, the oscilloscope waits for a trigger and displays the waveform when the trigger condition is met and then stops.

The Single trigger mode is appropriate when:
- To capture single event or a periodic signal.
- To capture burst or other unusual signals.

Note: You can force the oscilloscope to trigger by pressing the Single button twice. The trigger status in the upper left corner of the screen will be displayed as "FStop".

## Trigger Level (trigger level, slope, 50%, trigger level icon) [2+4-channel]

Trigger level and slope define the trigger point,
You can adjust the trigger level for a selected analog channel by turning the Trigger Level Knob.
You can push the Trigger Level Knob to set the level to the waveform's 50% value immediately. If AC coupling is used, pushing the Trigger Level knob sets the trigger level to about 0 V.
The position of the trigger level for the analog channel is indicated by the trigger level icon (if the analog channel is on) at the left side of the display. The value of the analog channel trigger level is displayed in the upperright corner of the display.

## Trigger Coupling (DC, AC, LF Reject, HF Reject) [2+4-channel]

Press the Setup button on the front panel to enter the TRIGGER function menu, and then press the Coupling softkey and turn the Universal Knob or press the Coupling softkey continually to select the desired coupling mode.

The oscilloscope provides 4 kinds of trigger coupling modes:

- DC: allow DC and AC components into the trigger path.
- AC: block all the DC components and attenuate signals lower than 8 Hz. Use AC coupling to get a stable edge trigger when your waveform has a large DC offset.
- LF Reject: block the DC components and reject the low frequency components lower than 2 MHz. Low frequency reject removes any unwanted low frequency components from a trigger waveform, such as power line frequencies, etc. that can interfere with proper triggering. Use LF Reject coupling to get a stable edge trigger when your waveform has low frequency noise.
- HF Reject: reject the high frequency components higher 1.2 MHz)
Note: trigger coupling has nothing to do with the channel coupling.

## Trigger Holdoff (holdoff time, re-arming, complex waveforms, pulse series) [2+4-channel]

Trigger holdoff can be used to stably trigger the complex waveforms (such as pulse series). Holdoff time is the amount of time that the oscilloscope waits before re -arming the trigger circuitry. The oscilloscope will not trigger until the holdoff time expires.

Use the holdoff to trigger on repetitive waveforms that have multiple edges (or other events) between waveform repetitions. You can also use holdoff to trigger on the first edge of a burst when you know the minimum time between bursts.

For example, to get a stable trigger on the repetitive pulse burst shown below, set the holdoff time to be &gt;200 ns but &lt;600 ns.

The correct holdoff setting is typically slightly less than one repetition of the waveform. Set the holdoff to this time to generate a unique trigger point for a repetitive waveform. Only edge trigger and serial trigger have holdoff option. The holdoff time of the oscilloscope is adjustable from 80ns to 1.5s.

1. Press the Stop button, and then use the Horizontal Position Knob and the Horizontal Scale Knob to find where the waveform repeats. Measure this time using cursors; then, set the holdoff.
2. Press the Setup button on the front panel to enter the TRIGGER function menu. The default trigger type is edge.
3. Press the Holdoff Close softkey; and then turn the Universal Knob to set the desired holdoff time.

Note: adjust the time scale and horizontal position will not affect the holdoff time.

## Noise Rejection (hysteresis, trigger sensitivity, noisy signal) [2+4-channel]

Noise Reject adds additional hysteresis to the trigger circuitry. By increasing the trigger hysteresis band, you reduce the possibility of triggering on noise. However, this also decreases the trigger sensitivity so that a slightly larger signal is required to trigger the oscilloscope.

Press the Setup button on the front panel, and then press the Noise Reject softkey continually to set the option to On or Off to turn on or off the noise rejection function.
If the signal you are probing is noisy, you can set up the oscilloscope to reduce the noise in the trigger path and on the displayed waveform. First, stabilize the displayed waveform by removing the noise from the trigger path. Second, reduce the noise on the displayed waveform.

1. Connect a signal to the oscilloscope and obtain a stable display.
2. Remove the noise from the trigger path by setting trigger coupling to LF Reject, HF Reject or turning on Noise Reject.
3. Set the Acquisition option to Average to reduce noise on the displayed waveform.

## Trigger Types (edge, slope, pulse, video, window, interval, dropout, runt, pattern) [2+4-channel]

The oscilloscope provides abundant advanced trigger functions, including various serial bus triggers.

- Edge trigger
- Slope trigger
- Pulse trigger
- Video trigger
- Window trigger
- Interval trigger
- Dropout trigger
- Runt trigger
- Pattern trigger

## Edge Trigger (rising, falling, alternating, trigger level) [2+4-channel]

Edge trigger distinguishes the trigger points by seeking the specified edge (rising, falling, alternating) and trigger level.

1. Press the Setup button on the front panel to enter the TRIGGER system function menu.
2. Press the Type softkey; turn the Universal Knob to set select Edge and then push the knob to confirm.
3. Press the Source softkey; turn the Universal Knob to select the deserted trigger source.
4. Press the Slope softkey; turn the Universal Knob to select the desired trigger edge (rising, falling or alternating), and then press down the knob to confirm. The current trigger slope is displayed at the upper right corner of the screen.
5. Turn the Trigger Level Knob to adjust the trigger level to obtain stable trigger.
Holdoff, coupling and noise reject can be set in edge trigger, see the sections "Trigger Holdoff", "Trigger Coupling" and "Noise Rejection" for details.
Note: Press the Auto Setup button will set the trigger type to Edge and slope to rising.

## Slope Trigger (positive slope, negative slope, trigger level A/B, limit range) [2+4-channel]

The slope trigger looks for a rising or falling transition from one level to another level in greater than or less than a certain amount of time.
In the oscilloscope, positive slope time is defined as the time difference between the two crossing points of trigger level line A and B with the positive edge as shown in the figure below.
1. Press the Setup button on the front panel to enter the TRIGGER function menu.
2. Press the Type softkey; turn the Universal Knob to set select Slope and then push the knob to confirm.
3. Press the Source softkey; turn the Universal Knob to select the trigger source.
4. Press the Slope softkey; turn the Universal Knob to set select the desired trigger edge (rising or falling), and then push down the knob to confirm. The current trigger slope is displayed at the upper right corner of the screen.
5. Press Lower Upper softkey to select the Lower or Upper trigger level; then turn the Trigger Level Knob to adjust the position. The trigger level values are displayed at the upper right corner of the screen.
6. The lower trigger level cannot be upper than the upper trigger level. In the trigger state message box, L1 means the upper trigger lever while L2 means the lower trigger level.
6. Press the Limit Range softkey; then turn the Universal Knob to select the desired slope condition, and push down the knob to confirm.
2. &lt;= (less than a time value): trigger when the positive or negative slope time of the input signal is lower than the specified time value.
3. &gt;= (greater than a time value): trigger when the positive or negative slope time of the input signal is greater than the specified time value.
4. [--, --] (within a range of time value):trigger when the positive or negative slope time of the input signal is greater than the specified lower limit of time and lower than the specified upper limit of time value.
5. --][--(outside a range of time value): trigger when the positive or negative slope time of the input signal is greater than the specified upper limit of time and lower than the specified lower limit of time value.

Coupling and noise reject can be set in slope trigger, see the sections "Trigger Coupling" and "Noise Rejection" for details.

## Pulse Trigger (positive pulse, negative pulse, pulse width, polarity) [2+4-channel]

Trigger on the positive or negative pulse with a specified width.
1. Press the Setup button on the front panel to enter the TRIGGER function menu.
2. Press the Type softkey; turn the Universal Knob to select Pulse and then push the knob to confirm.
3. Press the Source softkey; turn the Universal Knob to select CH1 or CH2 as the trigger source.
4. Turn the Trigger Level Knob to adjust the trigger level to the desired place.
5. Press the Polarity softkey to select Positive or Negative pulse that to trigger on. The current trigger polarity is displayed at the upper right corner of the screen.
6. Press the Limit Range softkey; turn the Universal Knob to select the desired condition.
7. &lt;= (less than a time value): trigger when the positive or negative pulse time of the input signal is lower than the specified time value. For example, for a positive pulse, if you set t (pulse real width) ≤ 100ns, the waveform will trigger.
8. &gt;= (greater than a time value): trigger when the positive or negative pulse time of the input signal is greater than the specified time value. For example, for a positive pulse, if you set t (pulse real width) ≥ 100ns, the waveform will trigger.
9. [--, --] (within a range of time value):trigger when the positive or negative pulse time of the input signal is greater than the specified lower limit of time and lower than the specified upper limit of time value.
For example, for a positive pulse, if you set t (pulse real width) ≥100ns and t ≤ 300ns, the waveform will trigger.
- --][--(outside a range of time value): trigger when the positive or negative pulse time of the input signal is greater than the specified upper limit of time and lower than the specified lower limit of time value.
Coupling and noise reject can be set in pulse trigger, see the sections "Trigger Coupling" and "Noise Rejection" for details.

## Video Trigger (NTSC, PAL, HDTV, custom, sync pulse, field, line) [2+4-channel]

Video triggering can be used to capture the complicated waveforms of most standard analog video signals. The trigger circuitry detects the vertical and horizontal interval of the waveform and produces triggers based on the video trigger settings you have selected.

The oscilloscope supports standard video signal field or line of NTSC (National Television Standards Committee), PAL (Phase Alternating Line) HDTV (High Definition Television) and custom video signal trigger.

1. Press the Setup button on the front panel to enter the TRIGGER function menu.
2. Press the Type softkey; then turn the Universal Knob to select Video and push down the knob to confirm.
3. Press the Source softkey; turn the Universal Knob to select CH1 or CH2 as the trigger source. Turn the Trigger Level Knob does not change the trigger level because the trigger level is automatically set to the sync pulse.
4. Press the Standard softkey to select the desired video standard. The oscilloscope supports the following video standards.

| Standard | Type | Sync Pulse |
|---------------|-------------|--------------|
| NTSC | Interlaced | BI-level |
| PAL | Interlaced | BI-level |
| HDTV 720P/50 | Progressive | Tri-level |
| HDTV 720P/60 | Progressive | Tri-level |
| HDTV 1080P/50 | Progressive | Tri-level |
| HDTV 1080P/60 | Progressive | Tri-level |
| HDTV 1080i/50 | Progressive | Tri-level |
| HDTV 1080i/50 | Progressive | Tri-level |
| Custom |  |  |

The table below shows the parameters of the Custom video trigger.

| Frame Rate | 25Hz, 30Hz, 50Hz, 60Hz | 25Hz, 30Hz, 50Hz, 60Hz |
|------------------|--------------------------|--------------------------|
| Of Lines | 300~2000 | 300~2000 |
| Of Fields | 1, 2, 3, 4 | 1, 2, 3, 4 |
| Interlace | 1:1, 2:1, 4:1, 8:1 | 1:1, 2:1, 4:1, 8:1 |
| Trigger Position | Line | Field |
|  | (line value)/1 | 1 |
|  | (line value)/2 | 2 |
|  | (line value)/3 | 3 |
|  | (line value)/4 | 4 |
|  | (line value)/5 | 5 |
|  | (line value)/6 | 6 |
|  | (line value)/7 | 7 |
|  | (line value)/8 | 8 |

The table below takes Of Lines as 800 as an example to explain the relation between Of Lines, Of Fields, Interlace, Trigger Line and Trigger Field.

| Of Lines | Of Fields | Interlace | Trigger Line | Trigger Field |
|------------|-------------|-------------|----------------|------------------|
| 800 | 1 | 1:1 | 800 | 1 |
| 800 | 1,2,4 or 8 | 2:1 | 400 | 1, 1~2, 1~4, 1~8 |
| 800 | 1,2,4 or 8 | 4:1 | 200 | 1, 1~2, 1~4, 1~8 |
| 800 | 1,2,4 or 8 | 8:1 | 100 | 1, 1~2, 1~4, 1~8 |

5. Press the Sync softkey to select Any or Select trigger mode.
2. Any: trigger on any of the horizontal sync pulses
3. Select: trigger on the appointed line and field you have set. Press the Line or Field softkey; then turn the Universal Knob to set the value.

The following table lists the line numbers per field for each video standard.

| Standard | Field 1 | Field 2 |
|-------------------------------|-----------|-----------|
| NTSC | 1 to 262 | 1 to 263 |
| PAL | 1 to 312 | 1 to 313 |
| HDTV 720P/50, HDTV 720P/60 | 1 to 750 |  |
| HDTV 1080P/50, HDTV 1080P/60 | 1 to 1125 |  |
| HDTV 1080iP/50, HDTV 1080i/60 | 1 to 562 | 1 to 563 |

The following are exercises to familiarize you with video triggering.

- To trigger on a specific line of video
- To use Custom video trigger

## To Trigger on a Specific Line of Video (NTSC, field, line, sync amplitude) [2+4-channel]

Video triggering requires greater than 1/2 division of sync amplitude with any analog channel as the trigger source.

The example below set to trigger on field 2, line 124 using the NTSC video standard.

1. Press the Setup button on the front panel to enter the TRIGGER system function menu.
2. Press the Type softkey; then use the Universal Knob to select Video and push down the knob to confirm.
3. Press the Source softkey; turn the Universal Knob to select CH1 as the trigger source, and press the knob to confirm.
4. Press the Standard softkey; turn the Universal Knob to select NTSC, and press the knob to confirm.
5. Press the Sync softkey and set the option to Select; press the Line softkey and then turn the universal to select 022 and push the knob to confirm; press the

Field softkey and then turn the Universal Knob to select 1 and push the knob to confirm

## To Use Custom Video Trigger (frame rate, line range, interlace, of field) [2+4-channel]

Custom video trigger supports frame rate of 25Hz, 30Hz, 50Hz and 60Hz, and the line range is available from 300 to 2000. The steps below show how to set custom trigger.

1. Press the Setup button on the front panel to enter the TRIGGER function menu.
2. Press the Type softkey; then use the Universal Knob to select Video and push down the knob to confirm.
3. Press the Source softkey; turn the Universal Knob to select CH1 as the trigger source, and push down the knob to confirm.
4. Press the Standard softkey; turn the Universal Knob to select Custom, and push down the knob to confirm.
5. Press the Setting softkey to enter the custom setting function menu. Press the Interlace softkey; turn the Universal Knob to select the desired value.
6. Press the Of Field softkey; turn the Universal Knob to select the desired value.
7. Press the Sync softkey to enter the TRIG ON menu to set the line and field.
8. Press the Type softkey to select Select or Any.
9. If the Type option set to Select, press the Line softkey; turn the Universal Knob to select the desired value. Press the Field softkey; turn the Universal Knob to select the desired value.

## Window Trigger (high trigger level, low trigger level, absolute, relative) [2+4-channel]

Windows trigger provides a high trigger level and a low trigger level. The instrument triggers when the input signal passes through the high trigger level or the low trigger level.

There are two kinds of window types: Absolute and Relative. They have different trigger level adjustment methods. Under Absolute window type, the lower and the upper trigger levels can be adjusted respectively via the Level knob; under Relative window type, adjust the Center value to set the window center; adjust the Delta value to set the window range, the lower and the upper trigger levels always move together.
- If the lower and the upper trigger levels are both within the waveform amplitude range, the oscilloscope will trigger on both rising and falling edge.
- If the upper trigger level is within the waveform amplitude range while the lower trigger level is out of the waveform amplitude range, the oscilloscope will trigger on rising edge only.
- If the lower trigger level is within the waveform amplitude range while the upper trigger level is out of the waveform amplitude range, the oscilloscope will trigger on falling edge only.

## To set window trigger via Absolute window type (absolute, lower, upper) [2+4-channel]

1. Press the Setup button on the front panel to enter the TRIGGER function menu.
2. Press the Type softkey; then use the Universal Knob to select Window and push down the knob to confirm.
3. Press the Source softkey; turn the Universal Knob to select CH1 or CH2 as the trigger source.
4. Press the Window Type softkey to select Absolute.
5. Press the Lower Upper softkey to select Lower or Upper trigger level; then turn the Trigger Level Knob to adjust the position. The trigger level values are displayed at the upper right corner of the screen.
The Lower trigger level cannot be upper than the upper trigger level. In the trigger state message box, L1 means the upper trigger level while L2 means the lower trigger level.

## To set window trigger via Relative window type (relative, center, delta) [2+4-channel]

1. Press the Setup button on the front panel to enter the TRIGGER system function menu.
2. Press the Type softkey; then use the Universal Knob to select Window and push down the knob to confirm.
3. Press the Source softkey; turn the Universal Knob to select CH1 or CH2 as the trigger source.
4. Press the Window Type softkey to select Relative.
5. Press the Center Delta softkey to select Center or Delta trigger level mode; then turn the Trigger Level Knob to adjust the position. The Center and Delta values are displayed at the upper right corner of the screen.
6. In the trigger state message box, C means Center, the center value of the lower and upper trigger levels; D means Delta, the difference between the lower (or upper) trigger level and the trigger level center.
Coupling and noise reject can be set in Window trigger, see the sections "Trigger Coupling" and "Noise Rejection" for details.

## Interval Trigger (neighboring edges, time limit, limit range) [2+4-channel]

Trigger when the times difference between the neighboring rising or falling edges meets the time limit (&lt;=, &gt;=, [--, --], --][--).

To set interval trigger:

1. Press the Setup button on the front panel to enter the TRIGGER system function menu.
2. Press the Type softkey; then use the Universal Knob to select Interval and push down the knob to confirm.
3. Press the Source softkey; turn the Universal Knob to select CH1 or CH2 as the trigger source.
4. Press the Slope softkey to select rising or falling edge.
5. Press the Limit Range softkey; turn the Universal Knob to select desired condition.
6. &lt;= (less than a time value): trigger when the positive or negative pulse time of the input signal is lower than the specified time value.
7. &gt;= (greater than a time value): trigger when the positive or negative pulse time of the input signal is greater than the specified time value.
8. [--, --] (within a range of time value):trigger when the positive or negative pulse time of the input signal is greater than the specified lower limit of time and lower than the specified upper limit of time value.
9. --][--(outside a range of time value): trigger when the positive or negative pulse time of the input signal is greater than the specified upper limit of time and lower than the specified lower limit of time value.
6. Press the Time Setting softkey (&lt;=, &gt;=, [--, --], --][--), turn the Universal Knob to select the desired value.
Coupling and noise reject can be set in interval trigger, see the sections "Trigger Coupling" and "Noise Rejection" for details.

## Dropout Trigger (edge, state, timeout, trigger level) [2+4-channel]

Dropout trigger includes two types: edge and state.

## Trigger Edge (time interval, rising edge, falling edge, timeout) [2+4-channel]

Trigger when the time interval (△T) from when the rising edge (or falling edge) of the input signal passes through the trigger level to when the neighboring rising edge (or falling edge) passes through the trigger level is greater than the timeout time set, as shown in the figure below.

## Trigger State (time interval, timeout, edge, state) [2+4-channel]

Trigger when the time interval (△T) from when the rising edge (or falling edge) of the input signal passes through the trigger level to when the neighboring falling edge (or rising edge) passes through the trigger level is greater than the timeout time set, as shown in the figure below.
To set edge Dropout trigger:

1. Press the Setup button on the front panel to enter the TRIGGER system function menu.
2. Press the Type softkey; then use the Universal Knob to select Dropout and push down the knob to confirm.
3. Press the Source softkey; turn the Universal Knob to select CH1 or CH2 as the trigger source. The current trigger source is displayed at the upper right corner of the screen. Select channel with signal input as trigger source to obtain stable trigger.
4. Press the Slope softkey to select rising or falling edge.
5. Press the OverTime Type softkey to select Edge.
6. Press the Time softkey; turn the universal to select the desired value.

To set state Dropout trigger:

1. Press the Setup button to enter the TRIGGER system function menu.
2. Press the Type softkey; then turn the Universal Knob to select Dropout and push down the knob to confirm.
3. Press the Source softkey; turn the Universal Knob to select CH1 or CH2 as the trigger source.
4. Press the Slope softkey to select rising or falling edge.
5. Press the OverTime Type softkey to select State.
6. Press the Time softkey; turn the Universal Knob to select the desired value.

Coupling and noise reject can be set in dropout trigger, see the sections "Trigger Coupling" and "Noise Rejection" for details.

## Runt Trigger (runt pulse, lower threshold, upper threshold, polarity) [2+4-channel]

The Runt trigger looks for pulses that cross one threshold but not another as shown in the picture below.
- A positive runt pulse across through a lower threshold but not an upper threshold.
- A negative runt pulse across through an upper threshold but not a lower threshold.

## To trigger on runt pulse (Polarity, Limit Range, Time Setting, Lower, Upper) [2+4-channel]

1. Press the Setup button on the front panel to enter the TRIGGER system function menu.
2. Press the Type softkey; then turn the Universal Knob to select Runt and push down the knob to confirm.
3. Press the Source softkey; turn the Universal Knob to select CH1 or CH2 as the trigger source.
4. Press the Polarity softkey to select Positive or Negative pulse to trigger.
5. Press the Limit Range softkey; turn the Universal Knob to select the desired condition (&lt;=, &gt;=, [--, --] or --][--).
6. Press the Time Setting softkey, and then turn the Universal Knob to select the desired value.
7. Press the Next Page softkey to enter the second page of the TRIGGER system function menu. Press the Lower Upper softkey to select Lower or Upper trigger level, and the turn the Universal Knob to set the position.
Coupling and noise reject can be set in runt trigger, see the sections "Trigger Coupling" and "Noise Rejection" for details.

## Pattern Trigger (logical AND, OR, NAND, NOR, low, high, invalid, don't care) [2+4-channel]

The Pattern trigger identifies a trigger condition by looking for a specified pattern. The pattern trigger can be expanded to incorporate delays similar to other triggers. Pattern durations are evaluated using a timer. The timer starts on the last edge that makes the pattern "true". Potential triggers occur on the first edge that makes the pattern false, provided that the time qualifier criterion has been met. The oscilloscope provides 4 patterns: logical AND, OR, NAND and NOR combination of the channels. Each channel can set to low, high or invalid.
Do the following steps to set pattern trigger:

1. Press the Setup button on the front panel to enter the TRIGGER function menu.
2. Press the Type softkey; turn the Universal Knob to select Pattern, and then push down the knob to confirm.
3. Press each channel softkey to select Invalid, High or Low.
4. Low sets the pattern to low on the selected channel. A low is a voltage level that is less than the channel's trigger level or threshold level.
5. High sets the pattern to high on the selected channel. A high is a voltage level that is greater than the channel's trigger level or threshold level.
6. Don't care sets the pattern to don't care on the selected channel. Any channel set to don't care is ignored and is not used as part of the pattern.
7. However, if all channels in the pattern are set to Don't care, the oscilloscope will not trigger.
8. Adjust the trigger level for the selected analog channel by turning the Trigger Level knob. Don't care doesn't need to set trigger level.
4. Press the Next Page softkey to enter the second page of the pattern trigger menu.
5. Press the Logic softkey and then turn the Universal Knob to select the desired logic combination AND, OR, NAND or NOR.
6. Press the Time softkey; then turn the Universal Knob to select the desired time value.
7. Press the Holdoff Close softkey to turn on the Holdoff function; then turn the Universal Knob to select the desired value.
Holdoff can be set in pattern trigger, see the sections "Trigger Holdoff" for details.

## Serial Triggers and Decode (I2C, SPI, UART, CAN, LIN, serial bus) [2+4-channel]

The oscilloscope provides I2C, SPI, UART, CAN and LIN serial trigger and decode. This chapter introduces the method of triggering and decoding these serial signals in details.

The contents of this chapter:

- I2C Trigger and Decode
- SPI Trigger and Decode
- UART Trigger and Decode
- CAN Trigger and Decode
- LIN Trigger and Decode

## I2C Trigger and Serial Decode (Inter-IC bus, SDA, SCL, threshold) [2+4-channel]

Please in order of "Setup for I2C Signals", "I2C Trigger" and "I2C Serial Decode" to trigger and decode the signals.

## Setup for I2C Signals (SDA, SCL, threshold voltage, clock signal, data signal) [2+4-channel]

Setting the I2C (Inter-IC bus) signal includes two steps: connecting the serial data signal (SDA) and serial clock signal (SCK) to oscilloscope, specifying the threshold voltage of each input signal.

1. Press the Decode key to enter the DECODE function menu as Figure 42 shows.
2. Press the Decode softkey and select the desired slot (Decode1 or Decode2).
3. Press the Protocol softkey and then select I2C by turning Universal Knob.
4. Press the Signal softkey to enter the SIGNAL menu as Figure 43 shows.
5. Set SCL (I2C's clock signal):
- a. Press the SCL softkey to select the channel that is connected to the I2C clock signal.
- b. Press the first Threshold softkey to set the I2C clock signal's threshold voltage level by Universal Knob. The threshold voltage level is for decoding, and it will be regard as the trigger voltage level when set the trigger type to serial.
6. Set SDA (I2C's data signal):
- a. Press the SDA to select the channel that is connected to the I2C data signal.
- b. Press the second Threshold softkey to set the I2C data signal's threshold voltage level by Universal Knob. The threshold voltage level is for decoding, and it will be regard as the trigger voltage level when set the trigger type to serial.
(Tips: SDA should keep stable during the whole high clock cycle, otherwise it will be interpreted as a start or stop condition (data transitioning while the clock is high))
7. Press the softkey to return previous menu.

## I2C Trigger (Start, Stop, Restart, No Ack, EEPROM, 7 Addr&Data, 10 Addr&Data, Data Length) [2+4-channel]

This part introduces the nine kinds of trigger conditions (Start, Stop, Restart, No Ack, EEPROM, 7 Addr&Data, 10 Addr&Data and Data Length) and the methods of setting them.

## I2C Trigger Conditions (Start, Stop, Restart, No Ack, EEPROM, address, data) [2+4-channel]

- Start Condition — the oscilloscope will be triggered when SDA signal transitions from high to low while the SCL clock is high. If it is chosen as the condition of trigger (including frame triggers), a restart will be treated as a "Start condition".
- Stop Condition— the oscilloscope will be triggered when SDA transitions from low to high while the SCL is high.
- Restart— the oscilloscope will be triggered when another "Start condition" occurs before a "Stop condition".
- No Ack — the oscilloscope will be triggered when SDA data is high during any SCL's ACK bit.
- EEPROM — the trigger searches for EEPROM control byte (the value is 1010xxx) on the SDA bus. And there is a Read bit and an ACK bit behind EEPROM. Using Limit Range softkey to set the qualifier and Data1 softkey to set the data's value. If EEPROM's data is greater(less, equal) than Data1, the oscilloscope will be triggered at the edge of ACK bit behind Data byte. It's unnecessary that the Data byte musts follow the EEPROM.
- 7 Address & Data — the oscilloscope will be triggered when the following conditions are satisfied.
- The address's length must be 7 bits and the address's value is the same as set value.
- If you have set either Data1's or Data2's value, and the signal has a data is the same as that value. If you have set both Data1's and Data2's value, the signal should has two consecutive data, the first data's value is Data1, second data value is Data2.
(Note: If the data's value is 0xXX, any data value will be matched)
- 10 Address & Data — the oscilloscope will be triggered when the following conditions are satisfied.
- The address's length must be 10 bits and the address's value is the same as set value.
- If you have set either Data1's or Data2's value, and the signal has a data is the same as that value. If you have set both Data1's and Data2's value, the signal should has two consecutive data, the first data's value is Data1, second data value is Data2.

(Note: If the set value is 0xXX, any data value will be matched)

- Data Length — When SDA data's length is equal to the value of Byte Length and address's length is the same as set value, the oscilloscope will be triggered. Byte length is in the range of 1 to 12 bits.

## I2C Operation Steps (Setup, Protocol, Trigger Setting, Condition) [2+4-channel]

1. Press the Setup to enter the TRIGGER function menu.
2. Press the Type and select Serial.
3. Press the Protocol and select I2C.
4. Press the Trigger Setting softkey.
5. Press the Condition softkey and turn the Universal Knob to select the trigger condition:
6. If you select the EEPROM condition:
- a. Press the Limit Range softkey to set the qualifier (=, &lt; or &gt;).
- b. Press the Data1 softkey and set its value by turning the Universal Knob.
9. If you select 7 Addr & & Data or 10 Addr & & Data condition:
- a. Press the Addr softkey and turn the Universal Knob to select the 7bit or 10 -bit device address.
- b. Press the Data1 or Data2 softkey and set the value about them.
- c. Press the R/W bit softkey and select write-frame or read-frame to trigger the oscilloscope.
(Tips: If device address is 7-bit, the value of address is in range of 0x00 to 0x7F. If device's address is 10 -bit, the value of address is in range of 0x00 to 0x3FF.)
- If you select the Data Length condition:
- a. Press the Address to set the SDA address length 7bit or 10 bit.
- b. Press the Byte Length softkey and set the byte length by Universal Knob. The range of the Byte Length is 1 to 12.

## I2C Serial Decode (Decode, Display, List, Format, Copy Setting) [2+4-channel]

After completing the setup of I2C signal and trigger, we will decode I2C signals. Operation steps as follows.
1. Press Decode→ Decode. Select one of the options from the Decode1 and Decode2.
2. Press the Display and select On to display the result of decoding.
3. Press the Configure to turn on or off the read or write bit.
4. Press the List to enter the LIST function menu.
5. Press the Display and choose the same options as the first step.
6. Press the Scroll and turn the Universal Knob to view all frames.
7. Press the Lines and set the number of lines by Universal Knob. The range of the lines is 1 to 7.
8. When a packet of data is long, all decoded data are not displayed. Turn on the Long Data to display the complete data.
9. Users can export the result list of the package to the external USB storage device in csv format (only when the USB flash disk is detected). Saving the data (*.csv) is similar to the operation of setup files, see the section "External save and recall" for details.
5. Press the Format to change the character encoding format of the decoding's result.
6. Press the Copy Setting to enter the COPY function menu to synchronize the corresponding bus configuration and trigger configuration.
7. Press the Tips Info to turn on or off the decoding limit prompt. When the decoding frame number reaches the maximum, it will pop up "Decoding to maximum frame number limitation!"

## I2C, The frames of decoding result (address, W/R, data, no acknowledgement) [2+4-channel]

- The address value is displayed at the beginning of a frame. The write address is displayed in green, and read address in yellow.
- W/R bit is represented by (W) and (R), following the address value.
- The data value is displayed in white.
-"~A" after a data or address bits indicates no acknowledgement. For example, DB~A.
- Indicates there is not enough space on the display to show the complete content of a frame, and some content is hidden.

## The lists of decoding result (Time, Address, R/W, Data) [2+4-channel]

- Time — the horizontal displacement between current frame and trigger position.
- Address — the address of a frame.
- R/W — — the type of a frame (write or read).
- Data — the value of data.

## SPI Trigger and Serial Decode (Serial Peripheral Interface, CLK, MISO, MOSI, CS) [2+4-channel]

Please in order of "Setup for SPI Signals", "SPI Trigger" and "SPI Serial Decode" to trigger and decode the signals.

## Setup for SPI Signals (CLK, MISO, MOSI, CS, threshold, edge select) [2+4-channel]

Setting the SPI (Serial Peripheral Interface) signal includes two steps: connecting the CLK, MISO, MOSI and CS signals to oscilloscope; specifying the parameters of each input signal.

1. Press the Decode key to enter the DECODE function menu.
2. Press the Decode softkey and select the desired slot (Decode1 or Decode2).
3. Press the Protocol softkey and then select SPI by turning Universal Knob.
4. Press the Signal softkey to enter the SIGNAL menu as Figure 47 shows.
5. Set CLK (clock signal):
- a. Press the CLK softkey to enter CLK menu.
- b. Press the CLK softkey to select the channel that is connected to the SPI clock signal.
- c. Press the Threshold softkey to set the SPI clock signal's threshold voltage level by Universal Knob. The threshold voltage level is for decoding, and it will be regard as the trigger voltage level when set the trigger type to serial.
- d. Press the Edge Select softkey to set the oscilloscope will samples at clock signal's rising edge or falling edge.
- e. Press the softkey to return previous menu.
6. Set MISO:
- a. Press the MISO softkey to enter the MISO menu.
- b. Press the MISO softkey to select the channel that is connected to the SPI MISO signal.
- c. Press the Threshold softkey to set the SPI MISO signal's threshold voltage

level by Universal Knob. The threshold voltage level is for decoding, and it will be regard as the trigger voltage level when set the trigger type to serial.

- d. Press the softkey to return previous menu.

## 7. SPI, Set MOSI (Master-Out Slave-In, threshold, channel) [2+4-channel]

- a. Press the MOSI softkey to enter the MOSI menu.
- b. Press the MOSI softkey to select the channel that is connected to the SPI MOSI signal.
- c. Press the Threshold softkey to set the SPI MOSI signal's threshold voltage level by Universal Knob. The threshold voltage level is for decoding, and it will be regard as the trigger voltage level when set the trigger type to serial.
- d. Press the softkey to return previous menu.

## 8. SPI, Set CS (chip select, Cs Type, polarity) [2+4-channel]

- a. Press the CS softkey to enter the MOSI menu.
- b. Press the Cs Type softkey to select the chip select type.
- c. Modify the Cs type's value.
- d. Press the softkey to return previous menu.

The Cs Type settings are:

| Settings | Explanation |
|----------|-------------|
| ~CS | low voltage level of CS signal is available |
| CS | high voltage level of CS signal is available |
| CLK Timeout | If the time between two edges of clock signal is less than (or equal to) the value of timeout, the signal between the two edges is treated as a frame. The range of clock timeout is 100ns-5ms. |

## SPI, Example (data width, bit order, CS polarity, clock timeout) [2+4-channel]

Connect the data, CLK and ~CS signals of a SPI bus respectively to C1, C2 and C3. Data width = 8 -bit, Bit order = MSB, CS polarity = ~CS, and 12 data bytes are transmitted in one frame.

In the SPI trigger signal menu, set the source and threshold of CLK, MISO and CS signals, then copy the trigger settings to decoding. Adjust the timebase, so that there is a falling edge on CS signal shown in the screen:
When the CS type is set to Clock Timeout, the clock idle time between frames is T3, the clock period is T1, then set the timeout to a value between T1 and T3：
If the data width is set to be greater than 8 bits (such as 16 bits), the clock idle time between 8 -bit data packets T2, and then set the timeout time to a value between T1/2+T2 and T3.

## SPI Trigger (MISO, MOSI, data length, bit value, bit order) [2+4-channel]

This part will provide a brief introduction and description for the operation of the SPI trigger.

1. Press the Setup button to enter the TRIGGER function menu.
2. Press the Type and select Serial.
3. Press the Protocol and select SPI.
4. Press the Trigger Setting softkey.
5. Press the Trigger Type softkey to select the trigger condition.
6. Press the Data Length softkey, and turn the Universal Knob to set the length of a data. The range of data length is 4 to 96 bits.
7. Set the value of the trigger data.
8. Set the value of a bit:
- a. Press the Bit Roll softkey to select a bit in data.
- b. Press the Bit Value softkey to set the value of the selected bit.
11. Set the value of all bits:
- a. Press the All Same softkey to set the value of all bits.
8. Press the Next Page softkey.
9. Press the Bit Order softkey to set the bit order (MSB or LSB).

Table 2 Menu Explanations of the SPI trigger type

| Function Menu | Settings | Explanation |
|------------------|------------|------------------------|
| Trigger Type | MISO | Master - In, Slave-Out |
| Trigger Type | MOSI | Master - Out, Slave-In |

Table 3 Menu Explanations of the SPI Bit value

| Function Menu | Settings | Explanation |
|------------------|------------|------------------------------|
| Bit Value | 0 | High voltage level |
| Bit Value | 1 | Low voltage level |
| Bit Value | X | Don’t care the voltage level |

## SPI Serial Decode (Decode, Configure, Display, List, Format) [2+4-channel]

After completing the setup of SPI signal and trigger, we will decode SPI signals. Operation steps as follows.

1. Press Decode → Decode. Select one of the options from the Decode1 and Decode2.
2. Press the Configure to set the bitstream format and bits (4-32 bits)
3. Press the Display and select On to display the result of decoding.
4. Press the Configure to set bit order and data length.
5. Press the List to enter the LIST function menu.
6. Press the Display and choose the same options as the first step.
7. Press the Scroll and turn the Universal Knob to view all frames.
8. Press the Lines and set the number of lines by Universal Knob. The range of the lines is 1 to 7.
9. Users can export the result list of the package to the external USB storage device in csv format (only when the USB flash disk is detected). Saving the data (*.csv) is similar to the operation of setup files, see the section "External save and recall" for details.
6. Press the Format to change the character encoding format of the decoding's result.
7. Press the Copy Setting to enter the COPY function menu to synchronize the corresponding bus configuration and trigger configuration.
8. Press the Tips Info to turn on or off the decoding limit prompt. When the decoding frame number reaches the maximum, it will pop up "Decoding to maximum frame number limitation!"

## SPI Decode, The frames of decoding result (MISO, MOSI, data values) [2+4-channel]

- The data values are displayed in frames and are shown in white. Support 4~96 bit data display.
- MISO — — the decoding result of "Master-In, Slave-Out" line.
- MOSI — — the decoding result of "Master-Out, Slave-In" line.
- Indicates there is not enough space on the display to show the complete content of a frame, and some content is hidden.

## The lists of decoding result (Time, MISO, MOSI) [2+4-channel]

- Time — the horizontal displacement between current frame and trigger position.
- MISO — — the decoding result of "Master-In, Slave-Out" line.
- MOSI — — the decoding result of "Master-Out, Slave-In" line.

## UART Trigger and Serial Decode (RX, TX, baud rate, parity, stop bit) [2+4-channel]

Please in order of "Setup for UART Signals", "UART Trigger" and "UART Serial Decode" to trigger and decode the signals.

## Setup for UART Signals (RX, TX, threshold, baud rate, data length, parity, stop bit, bit order, idle level) [2+4-channel]

1. Press the Decode key to enter the DECODE function menu.
2. Press the Decode softkey and select the desired slot (Decode1 or Decode2).
3. Press the Protocol softkey and then select UART by turning Universal Knob.
4. Press the Signal softkey to enter the SIGNAL menu as below shows.

## 5. UART, Set RX (receive, threshold, channel) [2+4-channel]

- a. Press the RX to select the channel that is connected to the RX signal.
- b. Press the first Threshold key y to set the RX signal's threshold voltage level by Universal Knob. The threshold voltage level is for decoding, and it will be regard as the trigger voltage level when set the trigger type to serial.

## 6. UART, Set TX (transmit, threshold, channel) [2+4-channel]

- a. Press the TX to select the channel that is connected to the TX signal.
- b. Press the second Threshold key y to set the TX signal's threshold voltage level by Universal Knob. The threshold voltage level is for decoding, and it will be regard as the trigger voltage level when set the trigger type to serial.
7. Press the softkey to return previous menu.
8. Press the Configure softkey to enter BUS CONFIG menu.
9. Press the Baud softkey to set baud rate.
6. The baud rate can be set as predefined value.
7. If the desired baud rate is not listed, press the Baud and select custom option, press the Custom and turn the Universal Knob to set the desired baud rate.
10. Press the Data Length softkey and set byte bits (5-8) by Universal Knob.
11. Press the Parity Check softkey to set the type of parity check (Even, Odd, Mark, Space or None).
12. Press the Stop Bit softkey to set the length of stop bit (1, 1.5 or 2 bits).
13. Press the Next Page softkey.
14. Press the Bit Order softkey to select the bit order (LSB or MSB).
15. Press the Idle Level softkey to set the idle level (LOW or HIGH).

## UART Trigger (Start, Stop, Data, Error, compare type) [2+4-channel]

This part shows a brief introduction and description for the operation of the UART trigger.

1. Press the Setup button to enter the TRIGGER function menu.
2. Press the Type and select Serial.
3. Press the Protocol and select UART.
4. Press the Trigger Setting softkey to enter UART TRIG SET menu.
5. Press the Source Type softkey to select the source of trigger (RX or TX).
6. Press the Condition softkey and set up the desired trigger condition:
3. Start — the oscilloscope will be triggered at the position of start bit.
4. Stop — the oscilloscope will be triggered at the position of stop bits.
5. Data — the oscilloscope will be triggered when found a byte which is equal to (greater or less than) the specified data.
- a. Press the Compare Type softkey and choose an equality qualifier (&gt;, &lt; or =).
- b. Press the Value softkey to set data's value. Data's value is in range of 0x00 to 0xff.
8. ERROR — if the parity check has been set, and the bit of parity check is error, the oscilloscope will be triggered.

## UART Serial Decode (Decode, Display, Configure, List, Format) [2+4-channel]

After completing the setup of UART signal and trigger, we will decode UART signals. Operation steps as follows.

1. Press Decode → Decode. Select one of the options from the Decode1 and Decode2.
2. Press the Display and select On to display the result of decoding.
3. Press the Configure to set the baud rate, data length, parity check, stop bit, idle level and bit order. Refer to "Setup for UART Signals" to set parameters.
4. Press the List to enter the LIST function menu.
5. Press the Display and choose the same options as the first step.
6. Press the Scroll and turn the Universal Knob to view all frames.
7. Press the Lines and set the number of lines by Universal Knob. The range of the lines is 1 to 7.
8. Users can export the result list of the package to the external USB storage device in csv format (only when the USB flash disk is detected). Saving the data (*.csv) is similar to the operation of setup files, see the section "External save and recall" for details.
5. Press the Format to change the character encoding format of the decoding's result.
6. Press the Copy Setting to enter the COPY function menu to synchronize the corresponding bus configuration and trigger configuration.
7. Press the Tips Info to turn on or off the decoding limit prompt. When the decoding frame number reaches the maximum, it will pop up "Decoding to maximum frame number limitation!"

## UART Decode, The frames of decoding result (RX, TX) [2+4-channel]

- RX — — the decoding result of the data received.
- TX — — the decoding result of the data transmitted.
- Indicates there is not enough space on the display to show the complete content of a frame, and some content is hidden.

## UART Decode, The lists of decoding result (Time, RX, TX, RX Err, TX Err) [2+4-channel]

- Time — the horizontal displacement between current frame and trigger position.
- RX — the receiving channel.
- TX — the transmitting channel.
- RX Err — Parity error or unknown error in the data received.
- TX Err — Parity error or unknown error in the data transmitted.

## CAN Trigger and Serial Decode (Controller Area Network, baud rate, threshold) [2+4-channel]

Please in order of "Setup for CAN Signals", "CAN Trigger" and "CAN Serial Decode" to trigger and decode the signals.

## Setup for CAN Signals (Source, Threshold, Baud, predefined, custom) [2+4-channel]

1. Press the Decode key to enter the DECODE function menu.
2. Press the Decode softkey and select the desired slot (Decode1 or Decode2).
3. Press the Protocol softkey and then select CAN by turning Universal Knob.
4. Press the Signal softkey to enter the SIGNAL menu as below shows.
- a. Press the Source softkey to select the channel that is connected to the CAN signal.
- b. Press the Threshold key y to set the CAN signal's threshold voltage level by Universal Knob. The threshold voltage level is for decoding, and it will be regard as the trigger voltage level when set the trigger type to serial.
5. Press the Configure softkey to enter the BUS CONFIG menu.
6. Press the Baud to set baud rate by Universal Knob.
5. The baud rate can be set as predefined value (from 5kb/s to 1Mb/s) or custom value (from 5kb/s to 1Mb/s).
6. If the desired baud rate is not listed, press Baud and select custom option, press the Custom and turn the Universal Knob to set the desired baud rate.

Press Decode Source to select the signal to be decoded:
- CAN_H — CAN_H signal will be decoded.
- CAN_L — CAN_L signal will be decoded.
- CAN_H-CAN_L — CAN_H and CAN_L are both used as the source of decoding.

## CAN Trigger (Start, Remote, ID, ID+DATA, Error) [2+4-channel]

This part will provide a brief introduction and description for the operation of the CAN trigger.

## CAN Trigger Conditions (Start, Remote, ID, ID+DATA, Error) [2+4-channel]

- Start — the oscilloscope will be triggered at the start bit of a frame.
- Remote — the oscilloscope will be triggered by a remote frame with specified ID.
- ID — the oscilloscope will be triggered by a remote or data frame that have specified ID.
- ID+DATA — the oscilloscope will be triggered by data frame that have specified ID and data.
- Error — the oscilloscope will be triggered by an error frame.

## CAN Operation Steps (Trigger Setting, Condition, ID Bits, ID, Data) [2+4-channel]

1. Press the Setup to enter the TRIGGER function menu.
2. Press the Type and select Serial.
3. Press the Protocol and select CAN.
4. Press the Trigger Setting to enter the CAN TRIG SET menu.
5. Press the Condition and select the trigger condition by Universal Knob:
6. If you select the REMOTE and ID condition:
- a. Press the ID Bits to set the length of ID (11bits or 29 bits).
- b. Press the Curr ID Byte and use the Universal Knob to select the byte that you want to set.
- c. Press the ID and set the ID's value by the Universal Knob.

(Tips: In order to make it convenient for the operation to set the parameters, ID b is split into several bytes. For example, if the ID's length is 11 bits, it will be split into two bytes, a byte includes 8 bits. If "1st byte" is selected, only the 8 least significant bits can be changed.)

- If you select the ID+DATA condition:
- a. Press the ID bits softkey to select the ID's length (11 or 29 bits).
- b. Press the Curr ID Byte softkey and use Universal Knob to select the byte that you want to modify.
- c. Press the ID softkey and set the ID's value by Universal Knob.
- d. Press the Data softkey and set the value of the first byte by Universal Knob

## CAN Serial Decode (Decode, Display, Configure, List, Format) [2+4-channel]

After completing the setup of can signal and trigger, we will decode CAN signals. Operation steps as follows.

1. Press Decode → Decode. Select one of the options from the Decode1 and Decode2.
2. Press the Display and select On to display the result of decoding.
3. Press the Configure to set the baud rate.
4. Press the List to enter the LIST function menu.
5. Press the Display and choose the same options as the first step.
6. Press the Scroll and turn the Universal Knob to view all frames.
7. Press the Lines and set the number of lines by Universal Knob. The range of the lines is 1 to 7.
8. Users can export the result list of the package to the external USB storage device in csv format (only when the USB flash disk is detected). Saving the data (*.csv) is similar to the operation of setup files, see the section "External save and recall" for details.
5. Press the Format to change the character encoding format of the decoding's result.
6. Press the Copy Setting to enter the COPY function menu to synchronize the corresponding bus configuration and trigger configuration.
7. Press the Tips Info to turn on or off the decoding limit prompt. When the decoding frame number reaches the maximum, it will pop up "Decoding to maximum frame number limitation!"

## CAN Decode: The frame of decoding result (Arbitration, Control, Data, CRC) [2+4-channel]

- Arbitration field is displayed in frame
- Control field is displayed in frame
- Data field is displayed in frame
- CRC field is displayed in frame
- Indicates there is not enough space on the display to show complete content of a frame and some content is hidden.

## CAN Decode: The list of decoding result (Time, Type, ID, Length, Data, CRC, ACK) [2+4-channel]

- Time — the horizontal displacement between current frame and trigger position.
- Type — the type of frames, "D" represents data frame, "R" represents remote frame.
- ID — the id of frames, the oscilloscope can automatically detect the length of frame's id (11 bits or 27 bits).
- Length — the length of data field.
- Data — the value of data field.
- CRC — — the value of CRC (Cyclic Redundancy Check) field.
- ACK — — Acknowledgment bit.

## LIN Trigger and Serial Decode (Local Interconnect Network, baud rate, threshold) [2+4-channel]

Please take the order of "Setup for LIN Signals", "LIN Trigger" and "LIN Serial Decode" to trigger and decode the signals.

## Setup for LIN Signals (Source, Threshold, Baud, predefined, custom) [2+4-channel]

There are two steps of setting the LIN signal, connecting the signal to oscilloscope, specifying the parameters of each input signal.

1. Press the Decode button to enter the DECODE function menu.
2. Press the Decode softkey and select the desired slot (Decode1 or Decode2).
3. Press the Protocol softkey and then select LIN by turning Universal Knob.
4. Press the Signal softkey to enter the SIGNAL menu as below shows.
5. Press the Source softkey to select the channel that is connected to the LIN signal.
6. Press the Threshold softkey and set the LIN signal's threshold voltage level by Universal Knob. The threshold voltage level is for decoding, and it will be regard as the trigger voltage level when set the trigger type to serial.
7. Press the softkey to return previous menu.
8. Press the Configure softkey to enter the BUS CONFIG menu.
9. Press the Baud softkey to set baud rate.
10. The baud rate can be set as predefined value.
11. If the desired baud rate is not listed, select custom option, press the Custom and turn the Universal Knob to set the desired baud rate.

## LIN Trigger (Break, ID, ID+Data, Data Error) [2+4-channel]

This part will provide a brief introduction and description for the operation of the LIN trigger.

## Trigger Conditions (Break, ID, ID+Data, Data Error) [2+4-channel]

- Break — the oscilloscope will be triggered at the position of break field's break delimiter.
- ID (Frame ID) — the oscilloscope will be triggered at the position of identifier field's stop bit, if the value of a frame's ID is equal to specified value.
- (Note: If the data's value is 0xXX, any data value will be matched)
- ID + Data (Frame ID and Data) — the oscilloscope triggers when a frame with an ID and data equal to the selected values is detected. Use the Universal Knob to select the value for the ID, Data1 and Data2.
- a. The ID's value is the same as set value.
- b. If you have set either Data1's or Data2's value, and the signal has a data is the same as that value. If you have set both Data1's and Data2's value, the signal should has two consecutive data, the first data's value is Data1, second data value is Data2.

(Note: If the data's value is 0xXX, any data value will be matched)

- Data Error —the oscilloscope will be triggered when errors (such as ID check error, checksum error, sync byte field error) are detected.

## Operation Steps (Setup, Protocol, Trigger Setting, Condition, ID, DATA) [2+4-channel]

1. Press the Setup button to enter the TRIGGER function menu.
2. Press the Type and select Serial.
3. Press the Protocol and select I2C.
4. Press the Trigger Setting softkey to enter LIN TRIG SET menu.
5. Press the Condition and select the trigger condition by Universal Knob:
6. If you select ID condition:
- a. Press the ID softkey and set its value by turning the Universal Knob.
8. If you select ID+DATA condition:
- a. Press the ID softkey and set its value by turning the Universal Knob.
- b. Press the DATA1 softkey and set its value by turning the Universal Knob.
- c. Press the DATA2 softkey and set its value by turning the Universal Knob.

## LIN Serial Decode (Decode, Display, Configure, List, Format) [2+4-channel]

After completing the setup of LIN signal and trigger, we will decode LIN signals. Operation steps as follows.

1. Press Decode → Decode. Select one of the options from the Decode1 and Decode2.
2. Press the Display and select On to display the result of decoding.
3. Press the Configure to set the baud rate.
4. Press the List to enter the LIST function menu.
5. Press the Display and choose the same options as the first step.
6. Press the Scroll and turn the Universal Knob to view all frames.
7. Press the Lines and set the number of lines by Universal Knob. The range of the lines is 1 to 7.
8. Users can export the result list of the package to the external USB storage device in csv format (only when the USB flash disk is detected). Saving the data (*.csv) is similar to the operation of setup files, see the section "External save and recall" for details.
5. Press the Format to change the character encoding format of the decoding's result.
6. Press the Copy Setting to enter the COPY function menu to synchronize the corresponding bus configuration and trigger configuration.
7. Press the Tips Info to turn on or off the decoding limit prompt. When the decoding frame number reaches the maximum, it will pop up "Decoding to maximum frame number limitation!"

## Interpreting LIN Decode (Protected Identifier, Data Length, Checksum) [2+4-channel]

## The frame of decoding result (Protected Identifier, Data Length, Data Field, Checksum) [2+4-channel]

- Protected Identifier Field is displayed in frame
- Data Length is displayed in frame
- Data Field is displayed in frame.
- Checksum Field is displayed in frame.
- Indicates there is not enough space on the display to show complete content of a frame and some content is hidden.

## The list of decoding result (Time, ID, Data Length, ID Parity, Data, Checksum) [2+4-channel]

- Time — the horizontal displacement between current frame and trigger position.
- ID — — the value of frame's Protected Identifier Field.
- Data Length — the length of Data Field.
- ID Parity — the two check bits of Protected Identifier Field.
- Data — the value of Data Field.
- Checksum — the value of Checksum Field.

## Reference Waveform (REF, analog channel, math waveform, compare) [2+4-channel]

The oscilloscope can save analog channel or math waveforms to the reference waveform locations in the oscilloscope. Then, a reference waveform can be displayed and compared against other waveforms. All reference waveforms can be displayed at a time.

The contents of this chapter:

- Save REF Waveform to Internal Memory
- Display REF Waveform
- Adjust REF Waveform
- Clear REF Waveform

## Save REF Waveform to Internal Memory (Source, Location, Save, non-volatile) [2+4-channel]

Do the following steps to save the REF waveform to internal memory:

1. Press the REF button on the front panel to enter the REF WAVE function menu. Note that when the time horizontal format is in X -Y mode, REF function cannot be enabled.
2. Press the Source softkey; then, turn the Universal Knob to select the source of reference channel. The source includes analog channel and math waveforms.
3. Press the Location softkey; then, turn the Universal Knob to select the position to save the REF waveform. The source includes analog channel and math waveforms.
4. Press the Save softkey to save the channel or math waveform to the appointed location. The vertical scale information and the vertical offset of the waveform will be saved at the same time. It will pop out the message "Saved to internal file REF*" when the waveform has been saved successfully.

Note: The REF waveforms are non-volatile. The REF waveform can still be saved after restarts or default operation.

## Display REF Waveform (Location, Display, On, four reference waveforms) [2+4-channel]

To the following steps to display REF waveform:

1. Press the REF button on the front panel to enter the REF WAVE function menu.
2. Press the Location softkey; then, turn the Universal Knob to select the REF waveform that you want to display.
3. Press the Display softkey to select On to display the REF waveform on the screen. Only saved location can be displayed. The oscilloscope can display all four reference waveforms at the same time.

## Adjust REF Waveform (Scale, Position, vertical scale, vertical position) [2+4-channel]

1. Please refer to the "Display REF Waveform" above to display the desired reference waveform.
2. Press the Scale and Position softkey and turn the Universal Knob to adjust the vertical scale and position of the reference waveform. The vertical scale and position information display at the middle of the screen.
The initial values display at the middle of the screen is the setup that when the reference waveform been saved.

Note: The vertical Variable knob and the vertical Position knob only work for the reference waveform and the math waveform. Please make a difference with the channel vertical system.

## Clear REF Waveform (Security Erase, overwrite, Save/Recall) [2+4-channel]

The oscilloscope does not have the "Clear" option under the REF WAVE function menu. To clear the appointed reference waveform, you can save a new reference waveform to the same location to cover it. Or follow the Save/Recall → Recall → type and select Security Erase to clear the stored waveform.

## Math (addition, subtraction, multiplication, division, FFT, differential, integral, square root) [2+4-channel]

The oscilloscope supports many math operations between analog channels including addition (+), subtraction (-), multiplication (*), division (/), FFT, differential (d/dt), integral (∫dt), square root (√). The resulting math waveform is displayed in white and labeled with "M". You can use cursors to measure it.
Note: if the analog channel or the math function is cut off (waveforms do not display on the screen completely), the resulting math will also be cut off.

## Units for Math Waveforms (V, A, W, dBVrms, V/S, Wb, C) [2+4-channel]

Use the channel function menu to set the unit of each channel to "V" or "A". The oscilloscope math operation includes units as below:

| Math Operation | Unit |
|--------------------------------|------------------------------------------------------------------------------------------------------------------|
| Addition (+)or subtraction (-) | V, A |
| multiplication (*) | V ∧ 2, A ∧ 2 or W |
| division (/) | SDS1000X-E：None, Ω (Resistance unit Ohms) or S (conductance unit Siemens) SDS1000X-U： None, V*A^-1 or V^-1*A |
| FFT | dBVrms, Vrms, dBm, dBArms, Arms |
| differential (d/dt) | SDS1000X-E：V/S or A/S (V/second or A/second) SDS1000X-U： V*S^ - 1 or A*S^ - 1 |
| integral (∫dt) | Wb, C |
| square root () | V ∧ 1/2 or A∧1/2 |

## Math Operators (arithmetic, FFT, differential, integral, square root) [2+4-channel]

The oscilloscope supports math count operation (Addition, subtraction, multiplication, division), FFT (Fourier transform) operation and math function operation (differential, integral, square root).

## MATH Addition or Subtraction (Source A, Source B, add, subtract, invert) [2+4-channel]

Math operators perform arithmetic operations add or subtract operation on any two analog input channels. When you select addition or subtraction, the Source A and Source B values are added or subtracted point by point, and the result is displayed.

1. Press the Math button on the front panel to enter the MATH function menu.
2. Press the Source A and Source B softkey respectively, and then turn the Universal Knob to select the source to do math operation. Addition or Subtraction can be applied between analog channels.
3. Press the Operator softkey and then turn the Universal Knob to select + or -to make addition or subtraction operation. The resulting math waveform is displayed in white and labeled with "M".
4. If you want to invert the math waveform, press the Invert button and set the option to On to invert the display of the math waveform.

## MATH Multiplication and Division (Source A, Source B, multiply, divide, invert) [2+4-channel]

Math operators perform arithmetic operations multiplication or division operation on any two analog input channels. When you select multiplication or division, the Source A and Source B values are multiplied or divided point by point and the result is displayed.

1. Press the Math button on the front panel to enter the MATH function menu.
2. Press the Source A and Source B softkey respectively, and then turn the Universal Knob to select the source to do math operation. Multiplication or Division can be applied between analog channels.
3. Press the Operator softkey and then turn the universal to select * or / to make multiplication or division operation. The resulting math waveform is displayed in white and labeled with "M".
4. If you want to invert the math waveform, press the Invert button and set the option to On to invert the display of the math waveform.

## MATH FFT Operation (fast Fourier transform, frequency domain, dBV, spectrum) [2+4-channel]

FFT is used to compute the fast Fourier transform using analog input channels. FFT takes the digitized time record of the specified source and transforms it to the frequency domain. When the FFT function is selected, the FFT spectrum is plotted on the oscilloscope display as magnitude in dBV versus frequency. The readout for the horizontal axis changes from time to frequency (Hertz) and the vertical readout changes from V to dB.

FFT operation can facilitate the following works:

- Measure harmonic components and distortion in the device under test
- Measure the characteristics of the noise in DC power
- Analyze vibration

## Display a FFT waveform (Source, Config, Window, Rectangle, Hanning, Hamming, Flat Top, Blackman) [2+4-channel]

1. Press the Math button on the front panel to open the MATH function menu.
2. Press the Operator softkey and then turn the Universal Knob to select FFT. The resulting math waveform is displayed in white and labeled with "M".
3. Press the Source softkey, and then turn the Universal Knob to select the source to do FFT operation. Analog channels can be used as the source.
4. Press the Config softkey to enter CONFIG menu.
5. Press the Maximum points softkey, and then turn the Universal Knob to select the Maximum points.
6. Press the Window softkey, and then turn the Universal Knob to select an appropriate window.
7. Spectral leakage can be considerably decreased when a window function is used. The oscilloscope provides five windows (Rectangle, Blackman, Hanning, Hamming and Flattop) which have different characteristics and are applicable to measure different waveforms. You need to select the window function according to different waveforms and their characteristics. Please read the table below carefully to make an appropriate option according to the input signal.

| Window | Applications and Characteristics |
|-----------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Rectangle | These are normally used when the signal is transient (completely contained in the time-domain window) or known to have a fundamental frequency component that is an integer multiple of the fundamental frequency of the window. Signals other than these types will show varying amounts of spectral leakage and scallop loss, which can be corrected by selecting another type of window. |
| Hanning | These reduce leakage and improve amplitude accuracy. However, frequency resolution is also reduced. |
| Hamming | These reduce leakage and improve amplitude accuracy. However, frequency resolution is also reduced. |
| Flat Top | This window provides excellent amplitude accuracy with moderate reduction of leakage, but with reduced frequency resolution. |
| Blackman | It reduces the leakage to a minimum, but with reduced frequency resolution. |

- Press the Auto set softkey to automatically set the appropriate parameters for the FFT measurement.
- Press the Display softkey to select Split Screen, Full Screen or Exclusive display mode.

Split Screen: Time domain waveform and frequency domain waveform are displayed separately. The time domain waveform is on the upper half screen, while the frequency domain waveform is located within the lower half of the display. In Split mode, if Zoom is enabled, the zoom waveform and the frequency domain waveform are displayed on the lower half screen together.

Full Screen: Time -domain waveform and frequency-domain waveform are displayed together.

Exclusive: Only the frequency-domain waveform is displayed.

- Press the Mode softkey to select Normal, Max-Hold or Average. When you select Average, it is necessary to set the average times.
5. Press the Vertical softkey to enter VERTICAL menu.
- Press the Scale softkey, and then turn the Universal Knob to select the desired vertical FFT scale
- Press the Ref Level softkey, and then turn the Universal Knob to select the desired vertical FFT offset.
- Press the Unit softkey to select the unit of vertical axis. The units of the vertical axis can be dBVrms, dBm, Vrms or dBArms, Arms, which use a logarithmic scale or a linear scale to display vertical amplitude respectively.
- Press the Ext Lode softkey and then turn the Universal Knob to select the external load value.
6. Press the Horizontal softkey to enter HORIZONTAL menu.
- Press the Center softkey, and then turn the Universal Knob to select the desired center frequency.
- Press the Hz/div softkey, and then turn the Universal Knob to select the desired resolution frequency.
7. Press the Tools softkey to enter TOOLS menu(only 4-channel supports this function). Press Type softkey to select the type of tools. The type of the tools can be Peaks, Markers, or Off.
Peaks: Automatically mark the peak of the current FFT waveform according to the search configuration.
- Press the Show Table softkey to display a table of peak, and press Show Frequency softkey to display the frequency value of the peak. Press the Sort By softkey continuously to set the table sorting by Amplitude or Frequency.
- Press the Search Config softkey to set search configuration.
- a. Press the Threshold softkey and turn the Universal knob to set the minimum peak amplitude. Only peaks larger than the peak limit can be judged as peaks.
- b. Press the Excursion softkey and turn the Universal knob to set the difference between the peak value and the minimum Amplitude on both sides. Only when the difference is greater than the peak value of peak offset can the peak value be determined.
Markers: Customize the marker locations on the FFT waveform based on search configuration.
- Press Markers Control softkey to enter MARKER Menu.
- a. Press the Marker softkey continuously to select the marker number from NO.1~NO.8.
- b. Press the Show Marker softkey continuously to turn on or off the selected mark.
- c. Press the Frequency softkey to set the frequency value of the selected marker.
- d. Press the Next Peak softkey to move the selected mark to the next peak. And press the Next Amplitude softkey to move the selected marker to the next peak with lower amplitude.(Up to 10 peaks are supported)
- Press the Search Config softkey to enter the SEARCH menu. Similar to the search configuration for peak markers.
- Press the Markers on Peaks softkey to set the markers on peaks, and press the Markers on Harmonics softkey to set the markers on harmonics.
- Press the Show Table softkey to show the amplitude of the markers; press the Show Frequency softkey to show the frequency value of the markers, and press the Show Delta softkey to show the delta amplitude between markers.
- Signals with DC components or deviation would cause error or deviation of the FFT waveform components. To reduce the DC components, set the Channel Coupling to AC.
- To reduce the random noise and aliasing frequency components of repetitive or single pulse, set the Acquisition of the oscilloscope to Average.

## measure FFT waveform (Cursors, X1, X2, Y1, Y2, frequency, amplitude) [2+4-channel]

To make cursor measurements, press the Cursors button, and then press the Mode softkey to select On to turn the cursors, Use the X1 and X2 cursors to measure frequency values and the difference between two frequency values (ΔX). Use the Y1 and Y2 cursors to measure amplitude in dB and difference in amplitude (ΔY). You can find the frequency value at the first occurrence of the waveform maximum by using the X at Max Y measurement.
Note: please refer to the cursors chapter to obtain the method of using cursors.

## Math Function Operation (differential, integral, square root) [2+4-channel]

The oscilloscope supports math function operation including differential (d/dt), integral (∫dt) and square root ().

## Math Differentiate (d/dt, discrete time derivative, slew rate, instantaneous slope) [2+4-channel]

d/dt (differentiate) calculates the discrete time derivative of the selected source.

Where:
- d = differential waveform
- y = channel 1, 2, 3, or 4 data points
- i = data point index
- Δ t = point- to- point time difference

The dx option under d/dt math function operation menu shows the point- to- point time difference, and it ranges from 0.02div to 0.40div. "div" indicates the number of the pixel points that each division has. The oscilloscope has 50 pixel points per division. Take 0.2div as an example: 0.2*50=10. It means to calculate the ten point's discrete time derivative of the selected source, and the Δ t is the ten point's pointto- point time difference.

You can use differentiate to measure the instantaneous slope of a waveform. For example, the slew rate of an operational amplifier may be measured using the differentiate function

Note: Because differentiation is very sensitive to noise, it is helpful to set acquisition mode to Average.

## Math Integrate (∫dt, integral, energy, voltseconds, area under waveform) [2+4-channel]

dt (integrate) calculates the integral of the selected source. You can use integrate to calculate the energy of a pulse in voltseconds or measure the area under a waveform.

## MATH Square Root (square root, holes, zero values) [2+4-channel]

Square root () calculates the square root of the selected source.
Where the transform is undefined for a particular input, holes (zero values) appear in the function output.

## Cursors (X cursors, Y cursors, voltage, time, measurements) [2+4-channel]

Cursors are horizontal and vertical markers that indicate X -axis values and Y -axis values on a selected waveform source. You can use cursors to make custom voltage, time measurements on oscilloscope signals.

## X Cursors (vertical dashed lines, time, frequency, X1, X2, ΔT) [2+4-channel]

X cursors are vertical dashed lines that adjust horizontally and can be used to measure time (when the source is FFT waveform, X cursors measure frequency).
X1 cursor is the left (default position) vertical dotted line; it can be moved to any place of the screen.
X2 cursor is the right (default position) vertical dotted line; it can be moved to any place of the screen.
Use the Universal Knob to set the X1 and X2 cursor values and the values are displayed in the cursors box in the upper-left corner of the screen along with the difference between X1 and X2 (△T) and 1/△T.
When set cursor type to X2-X1, use Universal Knob will move the X1 and X2 cursors together. The value under the menu option is the difference between the X1 and X2 cursors.

## Y Cursors (horizontal dotted lines, voltage, current, Y1, Y2, ΔY) [2+4-channel]

Y cursors are horizontal dotted lines that adjust vertically and can be used to measure voltage (V) or current (A). When the cursors source is the math function, the unit will match the math function.
Y1 cursor is the top (default position) horizontal dotted line; it can be moved to any vertical place of the screen.
Y2 cursor is the down (default position) horizontal dotted line; it can be moved to any vertical place of the screen.
Use the Universal Knob to set the Y1 and Y2 cursor values and the values are displayed in the cursors box in the top left corner of the screen along with the difference between Y1 and Y2 (△Y).

When set cursor type to Y2-Y1, use Universal Knob will move the Y1 and Y2 cursors together. The value under the menu option is the difference between the Y1 and Y2 cursors.

## Make Cursor Measurements (Manual, Track, Source, X Ref, Y Ref, transparence) [2+4-channel]

1. Press the Cursors button on the front panel to enter the CURSOR function menu.
2. Press the Mode softkey and set the cursors mode to Manual or Track.
3. Press the Source softkey, and then use the Universal Knob to select the desired source. Only analog channels, math waveforms and reference waveforms that are displayed are available for cursors.
4. Press the X Ref and Y Ref softkey to set the reference of X cursors and Y cursors.
5. Position: when the horizontal/vertical scale is changed, the X/Y cursors remain fixed to the grid position on the display.
6. Delay/Offset: when the horizontal/vertical is changed, the value of X/Y cursors remain fixed.
5. To make cursor measurements:
8. To measure the horizontal time, use the Universal Knob to move the X1 and X2 cursors to desired place. If necessary, set the cursor type to X2-X1, move X1 and X2 cursors together.
9. To measure vertical voltage or current, use the Universal Knob to move the Y1 and Y2 cursors to desired place. If necessary, set the cursor type to "Y2 -Y1", move Y1 and Y2 cursors together.
10. To adjust the transparence of the cursors message box, press the Display/Persist button and go to the second page, press the Transparence (20% to 80%) softkey and then turn the Universal Knob to adjust the transparence to the desired value.

## Measure (38 waveform parameters, voltage, time, delay, statistics) [2+4-channel]

The oscilloscope provides measurements of 38 waveform parameters and the statistics. It contains voltage, time and delay parameters.
Voltage and time parameters are under Type option. The results of the last four selected measurements are displayed at the bottom of screen and above the menu. Delay parameters are under the All Measure submenu. Set the Delay option to On to display all the delay parameters.

The contents of this chapter:

- Type of measurement
- Add measurement
- Clear measurement
- All measurement
- Gate measurement

## Voltage Measurements (Peak-Peak, Maximum, Minimum, Amplitude, Top, Base, Mean, Stdev, Rms, Overshoot, Preshoot) [2+4-channel]

Voltage measurements include 17 kinds of voltage parameter measurements.
1. Peak -Peak: Difference between maximum and minimum data values.
2. Maximum: Highest value in input waveform.
3. Minimum: Lowest value in input waveform.
4. Amplitude: Difference between top and base in a bimodal signal, or between max and min in a unimodal signal.
5. Top: Value of most probable higher state in a bimodal waveform.
6. Base: Value of most probable lower state in a bimodal waveform.
7. Mean: Average of all data values
8. Cycle mean: Average of data values in the first cycle.
9. Stdev: Standard deviation of all data values
10. Cycle Stdev: Standard deviation of all data values in the first cycle
11. Rms: Root mean square of all data values.
12. Cycle RMS: Root mean square of all data values in the first cycle.
13. Overshoot: Overshoot is distortion that follows a major edge transition expressed as a percentage of Amplitude. ROV means rising edge overshoot and FOV means falling edge overshoot.
14. Preshoot: Preshoot is distortion that precedes a major edge transition expressed as a percentage of Amplitude. The X cursors show which edge is being measured (edge closest to the trigger reference point).
15. Level@X: the voltage value between the trigger point and the vertical position of the channel

## Time Measurements (Period, Frequency, +Width, -Width, Rise Time, Fall Time, +Duty, -Duty, Delay) [2+4-channel]

Time measurements include 11 kinds of time parameter measurements.
1. Period: Period for every cycle in waveform at the 50% level, and positive slope.
2. Frequency: Frequency for every cycle in waveform at the 50% level,and positive slope
3. + Width: Width measured at 50% level and positive slope.
4. -Width: Width measured at 50% level and negative slope.
4. Rise Time: Duration of rising edge from 10-90%.
5. Fall Time: Duration of falling edge from 90-10%.
6. BWid: Time from the first rising edge to the last falling edge, or the first falling edge to the last rising edge at the 50% crossing.
7. + Duty: Ratio of positive width to period.
9. -Duty: Ratio of negative width to period.
8. Delay：Time from the trigger to the first transition at the 50% crossing.
9. T@L： Time from trigger of each transition at a specific level and slope, include: Current, Max, Min, Mean, and Std-dev.

## Delay Measurements (Phase, FRFR, FRFF, FFFR, FFFF, FRLR, FRLF, FFLR, FFLF, Skew) [2+4-channel]

Delay measurements measure the time different between arbitrary two channels, including 10 kinds of delay measurements.
1. Phase: Calculate the phase difference between two edges.
2. FRFR: Time between the first rising edges of the two channels.
3. FRFF: Time from the first rising edge of channel A to the first falling edge of channel B.
4. FFFR: Time from the first falling edge of channel A to the first rising edge of channel B.
5. FFFF: Time from the first falling edge of channel A to the first falling edge of channel B.
6. FRLR: Time from the first rising edge of channel A to the last rising edge of channel B.
7. FRLF: Time from the first rising edge of channel A to the last falling edge of channel B.
8. FFLR: Time from the first falling edge of channel A to the last rising edge of channel B.
9. FFLF: Time from the first falling edge of channel A to the last falling edge of channel B.
10. Skew：Time of source A edge minus time of nearest source B edge.

## Add Measurement (Source, Type, Statistics, measurement parameters) [2+4-channel]

Perform the steps below and select voltage or time parameters to make automatic measurement.

1. Press the Measure button on the front panel to enter the MEASURE function menu. At the same, the frequency and period are enabled with the current trigger channel, the statistics also was enabled.
2. Press the Source softkey, and then use the Universal Knob to select the desired channel. Only analog channels that are displayed are available for measurements.
3. To select and display measurement parameters. Press the Type softkey, and then turn the Universal Knob to select the desired measurement parameter.
4. Press the Universal Knob to add the measurement parameter, the parameters and value will be shown above the menu, and the statistics status will update.
5. To turn off the statistic function, press the Statistics softkey to select Off.

The measurement display area can display 4 measurement parameters at most, and the measurements will arrange according to the selecting order. If add the fifth measurement parameter, it will delete the first measurement.

Note: if the parameter does not match the measure condition, it will display as "****"

## Clear Measurement (selective clearing, clear all, recover) [2+4-channel]

SDS1000X-E (4-channel) supports selective clearing of measurement parameters that are displaying on the screen. SDS1000X-E (2 channel) and SDS1000X-U only support one key to clear all measurement items.

Press the Clear softkey to call up the clear measurement box. Rotate and press the Universal Knob to clear a measurement or all measurement. Press Recover to recover the selected measurement.

## All Measurement (all voltage, all time, All Measure, source) [2+4-channel]

All measurement could measure all the voltage and time parameters of the current measurement source and display the results on the screen.
Do the following steps to make all parameters measurement.

1. Press the Measure button on the front panel to enter the MEASURE function menu.
2. Press the All Measure softkey to select On.
3. Press the Source softkey to select the measure source.

## Gate Measurement (Gate A, Gate B, upper limits, lower limits) [2+4-channel]

The SDS1000X-E/SDS1000X-U support gate measurement and perform the selected measurement within the upper and lower limits of the gate. Setting the gate will affect the measurement of all voltage, time, and delay parameters.
1. Press Measure → Gate → On to open the gate measurement.
2. Press the Gate A to move the position of gate A by the Universal Knob.
3. Press the Gate B to move the position of gate B by the Universal Knob.
4. Press the Gate A -B to move the positions of the gate A and B simultaneously by the Universal Knob.

## Measuring Phase Shift Between 2 Signals [2+4-channel]

1. Initial Oscilloscope Setup
Enable both channels, CH1 and CH2.
Select DC coupling unless AC coupling is specifically required.
Set the trigger source to CH1.
Select the rising edge as the trigger slope.
Adjust the trigger level to obtain a stable display.
For the most reliable phase measurement, both signals should have the same frequency and reasonably stable waveforms.
Press the Measure button on the oscilloscope's front panel.
Open the measurement selection menu.
Locate the phase measurement function, typically listed under the delay-related measurements.
Select Phase.
Configure the measurement sources to compare CH1 and CH2.
Read the resulting phase value from the measurement display.

## Gain Measurement in dB (gain, gain measurement, decibel, dB, amplification, attenuation, voltage gain, DUT, Rms, CH1, CH2, channel ratio) [2+4-channel]

How to measure the gain in dB: measure the RMS voltage on both channels and take the ratio.

Gain is the ratio between the signal level at the output of a device under test (DUT) and the signal level at its input, expressed in decibels. For a voltage ratio:

gain (dB) = 20 × log10(V_signal / V_reference)

A positive result means the signal channel carries the higher voltage (amplification), a negative result means it carries the lower one (attenuation). The ratio is independent of the absolute level.

Note that this is a VOLTAGE gain, not a power gain. A power gain in dB would additionally require the impedance at both measurement points to be known and equal.

The SDS1000X-E has no dedicated single-value gain parameter in its measurement menu. To read a gain in dB, measure both channels with the same parameter type and calculate the ratio:

1. Connect the DUT input to CH2 (reference channel) and the DUT output to CH1 (signal channel).
2. Use the same probe attenuation on both channels, or account for the difference. The oscilloscope displays the voltage present at its input; a 10X probe has already divided the signal by 10.
3. Press Measure → Add Measurement and add the Rms parameter for CH1 and for CH2. The Source softkey selects the channel. Use the same parameter on both channels so that the ratio is meaningful, e.g. Rms on CH1 and Rms on CH2.
4. Read both values and calculate gain (dB) = 20 × log10(CH1 Rms / CH2 Rms).
   Example: CH1 Rms = 2 V, CH2 Rms = 1 V → 20 × log10(2) = +6.02 dB.
   Example: CH1 Rms = 500 mV, CH2 Rms = 100 mV → 20 × log10(5) = +13.98 dB.
   Example: CH1 Rms = 10 mV, CH2 Rms = 100 mV → 20 × log10(0.1) = -20.00 dB.
5. If a measurement displays "****", the parameter does not match the measure condition. Adjust the channel vertical scale and the trigger, then read the value again.

Related functions of the oscilloscope:

- Bode Plot II (4-channel models only) sweeps a sine wave over a frequency range and displays gain and phase versus frequency for a DUT. Use it when you need the gain over a frequency range instead of a single value.
- FFT displays the spectrum with a vertical unit of dBVrms (or dBm). This is useful to compare spectral amplitudes in dB, but it is not a Vout/Vin gain measurement.
- The Y cursors measure amplitude in dB and the difference between two amplitudes (ΔY) on FFT traces.

For exact help, use the Help function in sdsremote:

- The Data Logger of sdsremote records a Gain (dB) measurement, so the ratio does not have to be calculated by hand. It queries the RMS voltage on CH1 (signal) and on CH2 (reference) at the configured interval and logs 20 × log10(CH1 / CH2), scaled by the probe attenuation of each channel. See the Data Logger section of the sdsremote help.
- In the AI chat you can simply ask to "measure the gain". The instrument agent measures both channels and returns the gain in dB together with the way it was measured.
- Press the Help button in sdsremote and search for "Gain (dB)".

## Display (display type, color, persistence, grid, intensity, brightness, transparence) [2+4-channel]

You can set the display type, color, persistence, grid type, waveform intensity, grid brightness and transparence.

## Display Type (Vectors, Dots, sample points, lines) [2+4-channel]

Press the Display button on the front panel, and then press the Type softkey to select Vectors or Dots display type.
- Vectors: the sample points are connected by lines and displayed. Normally, this mode can provide the most vivid waveform to view the steep edge of the waveform (such as square waveform).
- Dots: display the sample points directly. You can directly view each sample point and use the cursor to measure the X and Y values of the sample point.

## Color Grade (color temperature, appearing probability, cold, warm) [2+4-channel]

Color temperature adopts the change of waveforms' color to reflect the change of the waveforms' appearing probability. The greater the probability that the waveform appears, the warmer the color is; the smaller the waveform appears, the colder the color is.

The picture below shows the change of color from cold to warm. Press the Display button on the front panel, and then press the Color Grade softkey and set the option to On to turn on the color temperature function. You can compare the waveform's color with the picture below to just the probability that the waveform appears.

## Persistence (Variable, Infinite, previous acquisitions, intensity, noise, jitter) [2+4-channel]

With persistence, the oscilloscope updates the display with new acquisitions, but does not immediately erase the results of previous acquisitions. All previous acquisitions are displayed with reduced intensity. New acquisitions are shown in their normal color with normal intensity.

Do the following steps to set and clear persistence:

1. Press the Display/Persist button on the front panel to enter the DISPLAY function menu.
2. Press the Persist softkey; then turn the Universal Knob to select the desires option.
3. Off — turn of persistence.
4. Variable persistence time (1 second, 5 seconds, 10 seconds, 30 seconds) — select different persistence time, the results of previous acquisitions are erased after a certain amount of time
5. Infinite — select "Infinite" Results of previous acquisitions are never erased. Use infinite persistence to measure noise and jitter, to see the worst- case extremes of varying waveforms, to look for timing violations, or to capture events that occur infrequently.
3. When the Persist is On, to erase the results of previous acquisitions from the display, press the Clear Persist softkey. The oscilloscope will start to

accumulate acquisitions again.

4. To return to the normal display mode, turn off persist and the previous acquisitions will be clear at once.

## Clear Display (clear waveforms, acquire new waveforms) [2+4-channel]

Press the Display button on the front panel to enter the DISPLAY function menu; press the Clear Display softkey to clear all the waveforms displaying on the screen and acquire and display new waveforms.

## Display Grid Type (14X8, 2X2, without grid) [2+4-channel]

To select grid type

1. Press the Display/Persist button on the front panel to enter the DISPLAY function menu.
2. Press the Next Page softkey to go to the second page of the Display function menu.
3. Press the Grid softkey; and then turn the Universal Knob to select the desired grid type. Press the Grid softkey continually can also select the grid type.

There are 3 kinds of grid types that are available. Select the grid type according to your really demand.
Display 14X8 grid type
Display 2X2 grid type
Display without grid

## Display Intensity (waveform intensity, 0% to 100%, noise, infrequent events) [2+4-channel]

Do the following steps to adjust waveform intensity:

1. Press the Display/Persist button on the front panel to enter the DISPLAY function menu.
2. Press the Next Page softkey to go to the second page of the Display function menu.
3. Press the Intensity softkey; and then turn the Universal Knob to select the desired value. The default value is 50%, and the range is from 0% to 100%.

Increasing the intensity lets you see the maximum amount of noise and infrequently occurring events. Reducing the intensity can expose more detail in complex signals as shown in the following figures.

Note: Waveform intensity adjustment affects analog channel waveforms only (not math waveforms, reference waveforms, digital waveforms, etc.).

## Grid Brightness (graticule, 0% to 100%) [2+4-channel]

Do the following steps to adjust the grid brightness:
1. Press the Display button on the front panel to enter the DISPLAY function menu.
2. Press the Next Page softkey to go to the second page of the Display function menu.
3. Press the Graticule softkey; and then turn the Universal Knob to select the desired value. The default value is 40%, and the range is from 0% to 100%.

## Transparence (message box, cursor, measure, Pass/Fail, 20% to 80%) [2+4-channel]

Transparence can be used to adjust the transparence of the message box of cursor, measure, Pass/Fail and all pop-up menus to an appropriate value to observe the date more conveniently.

Under Cursor or Measure or any other menu operation, if want to change the transparence of the message box, do the following steps:

1. Press the Display button on the front panel to enter the DISPLAY function menu.
2. Press the Next Page softkey to go to the second page of the Display function menu.
3. Press the Transparence softkey; and then turn the Universal Knob to select the desired value. The default value is 80%, and the range is from 20% to 80%.

## Save and Recall (setups, waveforms, pictures, CSV, internal memory, USB) [2+4-channel]

Oscilloscope setups, waveforms, pictures, and CSV files can be saved to internal oscilloscope memory or to a USB storage device. The saved setups, waveforms can be recalled later. The oscilloscope provides an USB Host interface on the front panel to connect an USB device for external storage.

## Save Types (setups, waveforms, images, CSV, binary, Matlab) [2+4-channel]

The oscilloscope supports setups, waveforms, images and CSV files storage. The default save type is setups.

## 1. Savetype Setups (xml, internal memory, 20 setting files) [2+4-channel]

It's the default storage type of the oscilloscope. It saves the settings of the oscilloscope in internal or external memory in "*.xml" format. At most 20 setting files (from No.1～No.20) can be stored in internal memory. The stored settings can be recalled.

## REF waveform Reference (REF format, REFA, REFB) [2+4-channel]

The oscilloscope saves the waveform data in external memory in "*.REF" format. The data of the channel is you select channel. At recall, the data will be displayed on the screen by REFA or REFB.

## 3 BMP (bmp, screen image, external memory) [2+4-channel]

The oscilloscope saves the screen image in external memory in "*.bmp" format. You can specify the file name and saving directory under the same directory using the same file name. The recall of image is not supported.

## 4 JPG (jpg, screen image, external memory) [2+4-channel]

The oscilloscope saves the screen image in external memory in "*.jpg" format. You can specify the file name and saving directory under the same directory using the same file name. The recall of image is not supported.

## 5 PNG (png, screen image, external memory) [2+4-channel]

The oscilloscope saves the screen image in external memory in "*.png" format. You can specify the file name and saving directory under the same directory using the same file name. The recall of image is not supported.

## 6. Binary (BIN, waveform data, all channels) [2+4-channel]

The oscilloscope saves the waveform data in external memory in "*.BIN" format. The data of all the channels turned on can be saved in the same file. The recall of binary is not supported.

## 7. CSV (CSV, waveform data, Param Save) [2+4-channel]

The oscilloscope saves the waveform data in external memory in "*.CSV" format. The stored files contain the waveform data of the displayed analog channels and the main setting information of the oscilloscope. The recall of CSV file is not supported.
Set the save type to CSV, and set the Param Save option to On or Off to turn on or of the parameters storage function.

## 8. Matlab (DAT, waveform data, all channels) [2+4-channel]

The oscilloscope saves the waveform data in external memory in "*.DAT" format. The data of all the channels turned on can be saved in the same file. The recall of Matlab file is not supported.

## 9. To Default Key (factory config, user set config) [2+4-channel]

The oscilloscope saves the factory config and user set config. Then you can select the default function is the factory config or user set config.

## 10. FileConverter (binary to CSV, bin, slg, mlg, spreadsheet) [2+4-channel]

The mini tool is used to convert stored binary files to CSV format for viewing with a spreadsheet program. It supports for file of waveform data (*.bin), file of sample logger(*.slg) and file of measure logger (*.mlg) to convert.

This is ideal when collecting large datasets. For a waveform frame with deep memory such as 14 Mpts, to save directly as a CSV file will take long time and will occupy a large amount of memory on a USB storage device. It's recommended to save the data as binary file and then convert it to CSV file on a computer.

## Internal Save and Recall (Setups, internal memory, save, recall) [2+4-channel]

Internal save and recall support Setups in Save/Recall. In the following part, the save and recall method and procedures are introduced.

## Save the specified oscilloscope setting in internal memory (Save, Type, Setup, Internal, Press to Save) [2+4-channel]

1. Connect the signal to the oscilloscope and obtain stable display.
2. Press Save/Recall button on the front panel to enter the SAVE/RECALL function menu.
3. Press the Save softkey to enter the SAVE function menu.
4. Press the Type softkey and then turn the Universal Knob to select Setups; and then press the knob to confirm.
5. Press the Save to softkey to select Internal to save the current setup of the oscilloscope to the internal memory.
6. Press the Setup softkey button; and then turn the Universal Knob to select the location to save. The internal memory can save as many as 20 setup files, from No.1～No.20.
7. Press the Press to Save softkey to save the current setup to the appointed location. After a few seconds, it will pop-up the message "Saved to internal file NO.x!"

## Load the specified type of file in internal memory (Recall, Type, Setup, Internal, Press to Recall) [2+4-channel]

If want to recall the setup after having finished the steps above, please do the following steps:

1. Press the Recall softkey enter the RECALLING function menu.
2. Press the Type softkey and then turn the Universal Knob to select Setups; and then press the knob to confirm.
3. Press the Recall from softkey to select Internal.
4. Press the Setup softkey button; and then turn the Universal Knob to select the location to recall. The internal memory can recall as many as 20 setup files, from No.1～No.20.
5. Press the Press to Recall softkey to recall the current setup form the appointed location. After a few seconds, it will pop-up the message "Recalled file successfully!"

Note: if need to delete a setup file in the memory, please save a new setup to the same location to overwrite it.

## External save and recall (USB flash, external storage, file system) [2+4-channel]

Before using external storage and recall, make sure that the USB flash device is connected correctly. External storage supports all the types of files in save, but in recall, images and CSV are not supported.

## Save the specified type of file in the external USB flash device (Save, Type, External, New, file name) [2+4-channel]

1. Press the Save/Recall button on the front panel to enter the SAVE/RECALL function menu.
2. Press the Save softkey to enter the SAVE menu.
3. Press the Type softkey to select Setup and then press the knob to confirm.
4. Press the Save to softkey to select External.
5. Press the Press to Save softkey to enter the SAVE/RECALL file system.
6. Use the Universal Knob to select the desired location. File can be stored under the root directory or in a certain folder under the root directory of the USB storage device.
7. After the save position is selected, press the New softkey y to turn on the interface as shown in the figure below. Refer to the descriptions in "To Create a new file or fold" to create a new file name.
8. Press the Press to Save softkey to save the current setup to the external USB storage device.

## Load the specified type of file in the external USB storage device (Recall, Type, External, file selection) [2+4-channel]

1. Press the Save/Recall button on the front panel to enter the SAVE/RECALL function menu.
2. Press the Recall softkey to enter the RECALL menu.
3. Press the Type softkey to select Setups or Reference.
4. Press the Recall from softkey to select External.
5. Press the Press to Recall softkey to enter the SAVE/RECALL file system.
6. Turn the Universal Knob to select the file to be recalled, press the Press to Recall softkey to recall the reference or setup.

## Disk Management (create, delete, rename, file, folder) [2+4-channel]

Disk management aim at the save and recall operations after the oscilloscope is connected with a USB storage device. Before using external disk, make sure that the USB storage device is connected correctly.

Execute the following operations through the disk management menu:
- Create a New File or Folder
- Delete a File or Folder
- Rename a File or Folder

## Create a New File or Folder (New, name input, keyboard, English input) [2+4-channel]

This operation is only valid in external storage. The oscilloscope supports English input method. The file name or folder name can contain letters, numbers, underscores and spaces. Let's use an example to introduce how to create a file or folder.

Example: create a file or folder named “SDS105X ”

1. Press the Save/Recall button on the front to enter the SAVE/RECALL function menu.
2. Press the Save softkey, and then turn the Universal Knob to select one of the type (if select Setups, please set the Save to option to External).
3. Press the Press to Save softkey to enter the SAVE/RECAL file system.
4. Press the New softkey to open the interface shown as the figure below. It divides into two parts: name input area and keyboard area.
5. To delete the name in the name input area, press the Backspace softkey continuously to delete the character one by one.

## Delete a File or Folder (Delete, external storage) [2+4-channel]

This operation is only valid in external storage.

1. Press the Save/Recall button on the front to enter the SAVE/RECALL function menu.
2. Press the Save softkey, and then turn the Universal Knob to select one of the type (if select Setups, please set the Save to option to External).
3. Press the Press to Save or Press to Recall softkey to enter the SAVE/RECAL file system.
4. Turn the Universal Knob to select the file or folder to be deleted, and then press the Delete softkey. Then the file or folder will be deleted.

## Rename a File or Folder (Rename, external storage, U disk) [2+4-channel]

This operation is only valid with external storage (U disk storage), and only files of the corresponding type format can be renamed.

1. Press the Save/Recall button on the front to enter the SAVE/RECALL function menu.
2. Press the Save softkey, and then turn the Universal Knob to select one of the type (if select Setups, please set the Save to option to External).
3. Press the Press to Save or Press to Recall softkey to enter the SAVE/RECAL file system.
4. Turn the Universal Knob to select the file or folder to be rename, and then press the Rename softkey. For details, see the instructions in "Create a New File or Folder."

## Digital Channels (Option) (MSO, SLA1016, digital probes, logic threshold) [4-channel only]

The digital channels are enabled on SDS1000X-E (4-channel scope) that have installed the MSO activation license. As an external module, SLA1016 is independent of the host, and has its own system, so it needs to be upgraded if necessary.

## Connect the Digital Probes (digital probe cable, fly line, grabber, ground) [4-channel only]

1. If necessary, turn off the power supply to the device-under-test.
2. Turning off the power to the device-under-test prevents damage that might occur if you accidentally short lines together while connecting probes. You can leave the oscilloscope powered on because no voltage appears at the probes.
2. Connect one of the digital probe cable ports to the digital channels connector on the front panel of the SDS1000X-E, and the other one to the digital channels connector of the digital probe.
4. The digital probe cable is keyed so you can connect it only one way. You do not need to power-off the oscilloscope.
3. Connect a fly line to one of the digital probe ground pins, connect a grabber to the fly line, and then connect the grabber to a ground trace/pin from the device -under -test. The ground lead improves signal fidelity to the oscilloscope, ensuring accurate measurements,
4. Connect a fly line to one of the digital probe digital channel pins; connect a grabber to the fly line, and then connect the grabber to a node in the circuit you want to test.
5. Repeat step 4 until you have connected all points of interest.
There are two indicators on the side of the SLA1016, one is red (Power), another is green (Ready)

- The red indicator: If SLA1016's power is normal, this indicator turns on, or else it blinks or turns off.
- The green indicator: When the SLA1016 is connect to the oscilloscope, this indicator turns on for seconds then turns off, and then blinks, and finally keeps the light on. When data is transferred between the SLA1016 and the oscilloscope, the indicator blinks.

## Acquire Digital Waveform (Digital button, sample, logic threshold) [4-channel only]

Press the Digital button on the front panel to open the digital channels and start acquiring digital channel waveforms.

For digital channels, each time the oscilloscope takes a sample it compares the input voltage to the logic threshold. If the voltage is above the threshold, the oscilloscope stores a 1 in the sample memory; otherwise, it stores a 0.

## Digital Channels Height (Low, Middle, High, spread out, compress) [4-channel only]

1. Press the Digital button on the front panel to open the DIGITAL function menu.
2. Press the Channel High softkey to select Low, Middle, High display type.

The display type control lets you spread out or compress the digital traces vertically on the display for more convenient viewing.

## Digital Channels Position (Control, Active, Position, reposition) [4-channel only]

1. Press the Digital button on the front panel to open the DIGITAL function menu and display the digital channel waveforms.
2. Press the Control softkey select the Active then turn the Universal Knob to select the channel that you wish to reposition. The selected waveform is highlighted in red.
3. Press the Control softkey select the Position then turn the Universal Knob to move the selected channel to any position.

## Single Digital Channel (Channel Control, Dx) [4-channel only]

1. Press the Digital button on the front panel to open the DIGITAL function menu.
2. Press the Channel Control softkey, then turn the Universal Knob to select the desired channel such as Dx and push down the knob to confirm.
3. Press the Dx softkey to select On or Off to switch the selected channel on or off.

## All Digital Channels (Channel Group, all channels) [4-channel only]

1. Press the Digital button on the front panel to open the DIGITAL function menu.
2. Press the Channel Group softkey to select On or Off to switch all digital channels which in this group on or off.

Also, under the DIGITAL function menu, press the Digital button on the front panel to switch all digital channels off.

## Logic Threshold (TTL, CMOS, LVCMOS3.3, LVCMOS2.5, Custom, threshold voltage) [4-channel only]

1. Press the Digital button on the front panel to open the DIGITAL function menu.
2. Press the Threshold softkey to enter the THRESHOLDS menu.
3. Press the D0~D7or D8~D15softkey, then turn the Universal Knob to select a logic family preset or select Custom to define your own threshold.

| Logic Family y | Threshold Voltage |
|-------------------|----------------------------|
| TTL | 1.5V |
| CMOS | 1.65V |
| LVCMOS3.3 | 1.65V |
| LVCMOS2.5 | 1.25V |
| Custom | Variable from - 3V to +3V |

- The threshold you set applies to all channels.
- Values greater than the set threshold are high (1) and values less than the set threshold are low (0).
- If the D0~D7or D8~D15 softkey is set to Custom, press the Custom softkey, then turn the Universal Knob to select the desired value and push down the knob to confirm.

## Digital Bus (bus, hex, binary, Bus1, Bus2, channel group) [4-channel only]

Digital channels may be grouped and displayed as a bus, with each value displayed at the bottom of the display in hex or binary. You can create up two buses.

To configure and display each bus, do the following steps:

1. Press the Digital button on the front panel to open the DIGITAL function menu and display the digital channel waveforms.
2. Press the Digital Bus softkey to enter the DIGITALBUS function menu.
3. Press the Bus Select softkey to select Bus1 or Bus 2.
4. Press the Display softkey to select On to display the bus at the bottom of the display.
5. Under the DIGITAL function menu, press the Cannel Control softkey, turn the Universal Knob to select such as DX, and then press the Dx softkey to select On or Off to set the channel to be included or excluded in the bus.
6. Under the DIGITAL function menu, press the Channel Group softkey to select On or Off to include or exclude all digital channels in this group.
7. Under the DIGITAL function menu, a status indicator is displayed in the status line at the bottom of the display. Light blue shows the digital channel is included in the bus while black shows it is excluded in the bus.
8. Under the DIGITAL function menu, press the System Display softkey to select Binary or Hex to display the bus values.
The Sampling rate of digital channels is displayed at the right of the display.

## Deskew (deskew, digital channels) [4-channel only]

1. Press the Digital button on the front panel to open the DIGITAL function menu and display the digital channel waveforms.
2. Press the Deskew softkey, and then turn the Universal Knob to select to change deskew.

## System Status (software version, hardware version, serial number) [4-channel only]

Press Digital→ NextPage2/2 → System,then select the System Status option to view the digital system information, including software version, hardware version, and serial number. After finished, press the return soft key to quit the interface of system information.

## Software Update (ads, firmware, U-disk, update) [4-channel only]

The software version file of the Digital can be updated directly via U-disk. Follow the steps below:
1. Insert U-disk with firmware update file (*.ads) to USB host interface on the front panel of the oscilloscope. Then a message "USB Flash Drive detected!" will be displayed.
2. Press Digital→NextPage2/2→System →Update
3. Expand the U disk directory, Select the firmware file (*.ads), then press the Press to update, an upgrade progress bar will be display on the interface.
4. After the updating is finished, the Digital device will automatically disconnected and display a message "Update completed, please reconnect Digital device!"
Note： Don't cut off the power during the Digital device is being updated！

## Remove Device (Digital device removed, disconnect) [4-channel only]

Press Digital→ NextPage2/2 →Remove Device and the oscilloscope interface display "Digital device removed!", the device can be pulled.

## System Setting (system status, language, sound, self-cal, update, remote interface) [2+4-channel]

This function module supports the oscilloscope's system-related function, such as system status, language, sound and some other advanced setting, such as do self-cal, update and remote interface configure.

## View System Status (Utility, System Status, Startup Times, Software Version, FPGA Version, Hardware Version, Product Type, Serial No.) [2+4-channel]

Do the following steps to view the system status:

1. Press the Utility button on the front to enter the UTILITY function menu.
2. Press the System Status softkey to view the system status of the oscilloscope. The system status includes the information below:
3. Startup Times: record the boot-strap times of the oscilloscope.
4. Software Version: list the current software version of the oscilloscope.
5. Uboot -OS Version: list the current Uboot and OS version of the oscilloscope
6. FPGA Version: list the current fpga version of the oscilloscope.
7. Hardware Version: list the current hardware version of the oscilloscope.
8. Product Type: display the product type of the oscilloscope.
9. Serial No.: list the serial number of the oscilloscope.
10. Scope ID: display the scope identification of the oscilloscope.
3. Press the Single button on the front panel to exit.

## Do Self Cal (self-calibration, warm up, disconnect input channels) [2+4-channel]

The self-calibration program can quickly make the oscilloscope reach the best working state to get the most precise measurement values. You can perform self-calibration at any time especially when the change of the environment
temperature is up to or more than 5 ℃. Make sure that the oscilloscope has been warmed up or operated for more than 30 minutes before the self-calibration.
Do the following steps to do self-calibration:
1. Disconnect all the input channels.
2. Press the Utility button on the front panel ， and then press the Do Self Cal softkey, and the oscilloscope will pop-out the message box shown as below:
3. Press the Single button on the front panel to perform the self-calibration program. During the calibration, most of the keys are disabled.
4. When the self-calibration program is finished, it will pop-out the message "Press Run/Stop key to exit". Press the Run/Stop button on the front panel to exit the calibration interface.

## Quick-Cal (quick calibration, temperature, measurement deviation) [2+4-channel]

Quick calibration can correct the measurement deviation caused by temperature, so that you can get more accurate measurements.
If the ambient temperature of your current operating oscilloscope is unstable, press Utility → Quick-Cal softkey to select On to enable quick calibration.

## Set Sound (beeper, function key, menu softkey, prompt message) [2+4-channel]

When the sound is enabled, you can hear the sound of the beeper when you press a function key or a menu softkey or when the prompt message pops up.
Press the Utility button on the front panel to enter the UTILITY function menu; then press Sound softkey to select or to turn on or off the sound.

## Set Language (Simplified Chinese, English, French, German, Spanish, Russian, Italian, Portuguese) [2+4-channel]

The oscilloscope supports multiple language menu, Chinese/English help and prompt messages.

1. Press the Utility button on the front panel to enter the UTILITY Function menu.
2. Press the Language softkey; and then turn the Universal Knob to select the desired language. Then push down the knob to select the language.
The languages that currently available are Simplified Chinese, Traditional Chinese, English, French, German, Spanish, Russian, Italian, and Portuguese.

## Pass/Fail Test (mask, compliance, test results, TRIG OUT, beeper) [2+4-channel]

One way to verify a waveform's compliance to a particular set of parameters is to use pass/fail testing. A pass/fail defines a region of the oscilloscope's display in which the waveform must remain in order to comply with chosen parameters. Compliance to the mask is verified point- bypoint across the display.

The test results can be displayed on the screen as well as be declared through the system sound or the pulse signal output from the [TRIG OUT] connector at the rear panel. Pass/Fail test operates on displayed analog channels; it does not operate on channels that are not displayed.

## Set and Perform Pass/Fail Test (Enable Test, Source, Mask Setting, X Mask, Y Mask, Create Mask, Stop On Fail, Output) [2+4-channel]

Do the following steps to set and perform pass/fail test:

1. Press the Utility button on the front panel to enter the UTILITY function menu.
2. Press the Next Page softkey to go to the second page of the UTILITY function menu.
3. Press the Pass/Fail softkey to enter the PASS/FAIL function menu.
4. Press the Enable Test softkey to select On to enable the pass/ fail test.
5. Press the Source softkey to select the desired channel.
6. Press the Mask Setting softkey to enter the MASK function menu.
7. Press the X Mask or Y Mask softkey; and then turn the Universal Knob to select the desired value. The range is from 0.02div to 4div.
8. Press the Create Mask button to create the mask. Whenever the Create Mask softkey is pressed the old mask is erased and a new mask is created.
9. Press the UP softkey to return to the PASS/FAIL function menu.
10. Press the Msg Display to select On or Off to turn on or off the message display. When On is selected, the test result will be displayed in the upper-right message box of the screen.
6. F: the frame number of the channel waveform that fails to match the mask.
7. P: the frame number of the channel waveform that matches the mask.
8. T: the frame number of the channel waveform that have been acquired. It is the total of Pass and Fail.
11. Press the Next Page softkey to go to the second page of the PASS/FAIL function menu.
12. Press the Stop On Fail softkey to select On or Off to turn on or off the function.
11. On: when failed waveforms are detected, the oscilloscope will stop the test and enter the STOP state. At this point, the results of the test remain the same on the screen (if display is turned on) and only one pulse is output from the [TRIG OUT] connector (if enabled) at the rear panel.
12. Off: the oscilloscope will continue with the test even though failed waveforms are detected. The test results on the screen will update continuously and a pulse will be output from the [Trigger Out] connector at the rear panel each time a failed waveform is detected.
13. Press the Output softkey to select turn on or off the sound.
14. : When the failed waveforms are detected, the beeper sounds.
15. : The beeper will not sound even if the failed waveforms are detected,
14. Press the Next Page softkey to return to the first page of the PASS/FAIL function menu.
15. Press the Operate softkey to perform the test.
18. : Current state is stop; press the softkey to start the pass/fail test.
19. : Current state is running; press the softkey to stop the pass/fail test.

## Save and Recall Test Mask (msk, internal Flash, external USB) [2+4-channel]

Users can save the current test mask to the internal Flash memory or external USB flash device. The file format of the test mask file is "*.msk".

## Save Test Mask to Internal Memory (Location, Internal, Save, Pass/Fail_mask_data.msk) [2+4-channel]

1. Press the Utility button on the front panel to enter the UTILITY function menu.
2. Press the Next Page softkey to go to the second page of the UTILITY function menu.
3. Press the Pass/Fail softkey to enter the PASS/FAIL function menu.
4. Press the Enable Test softkey to select On to enable the pass/ fail test.
5. Press the Source softkey to select the desired channel.
6. Press the Mask Setting softkey to enter the MASK function menu.
7. Press the X Mask or Y Mask softkey; and then turn the Universal Knob to select the desired value.
8. Press the Location softkey to select Internal
9. Press the Save softkey to save the mask to internal memory.
10. A few second later, it will pop-out the message "Save to file Pass/Fail\_mask\_data.msk!"
Note: the internal memory can only save one test mask; save a new test mask will cover the old one.

## Recall Test Mask from Internal Memory (Location, Internal, Load) [2+4-channel]

1. Press the Utility button on the front panel to enter the UTILITY function menu.
2. Press the Next Page softkey to go to the second page of the UTILITY function menu.
3. Press the Pass/Fail softkey to enter the PASS/FAIL function menu.
4. Press the Enable Test softkey to select On to enable the pass/ fail test.
5. Press the Mask Setting softkey to enter the MASK function menu.
6. Press the Location softkey to select Internal.
7. Press the Load softkey to recall the saved interval memory.
8. A few second later, it will pop-out the message "Recalled the Successfully!" and the saved mask will be displayed on the screen.

## Save Test Mask to External Memory (Location, External, Save, file system) [2+4-channel]

Do the following steps to save the test mask to external memory:

1. Press the Utility button on the front panel to enter the UTILITY function menu.
2. Press the Next Page softkey to go to the second page of the UTILITY function menu.
3. Press the Pass/Fail softkey to enter the PASS/FAIL function menu.
4. Press the Enable Test softkey to select On to enable the pass/ fail test.
5. Press the Source softkey to select the desired channel.
6. Press the Mask Setting softkey to enter the MASK function menu.
7. Press the X Mask or Y Mask softkey; and then turn the Universal Knob to select the desired value.
8. Press the Location softkey to select External
9. Press the Save softkey to enter the file SAVE/RECALL system.
10. Save the test mask file refer to the "Save to file XXX.msk" chapter.

## Recall Test Mask from External Memory (Location, External, Load, RGU postfix) [2+4-channel]

Do the following steps to save the test mask f external memory:

1. Press the Utility button on the front panel to enter the UTILITY function menu.
2. Press the Next Page softkey to go to the second page of the UTILITY function menu.
3. Press the Pass/Fail softkey to enter the PASS/FAIL function menu.
4. Press the Enable Test softkey to select On to enable the pass/ fail test.
5. Press the Mask Setting softkey to enter the MASK function menu.
6. Press the Location softkey to select External.
7. Press the Load softkey to enter the file SAVE/RECALL system.
8. Select the desired test mask file with a RGU postfix using the Universal Knob; and then press the Load softkey.

## Arbitrary Waveform Generator (Option) (AWG, standard waveform, Arb, EasyWave) [4-channel only]

SDS1000X-E (4-channel) support an external Arbitrary Waveform Generator (AWG), which can easily and quickly provide multiple input signals to users.

The AWG provides two kinds of waveforms: the standard waveform and the Arb. The Arb single consists of two types: the system's built -in waveforms and the stored waveforms.
Built-in waveforms are stored in the internal non-volatile memory. It is includes: Common, Math, Engine, Window, and Trigo. Users may also edit the arbitrary waveform by PC which has installed the EasyWave, or import the waveform by U disk that had stored edited waveform.

## Waveform Output (USB cable, AWG device connection, Output, frequency, amplitude) [4-channel only]

Connect AWG with USB cable, and the oscilloscope interface indicates "AWG device connection success", Press the Utility → Next Page4/4→ AWG, to enter the function menu interface of the AWG system as shown below, including: Output, Wave, Setting, System, and Remove Device.
Press Output softkey to open or close the AWG output.When the output is on, the upper right corner of the oscilloscope interface will displays the corresponding waveform frequency and amplitude information of AWG output wave.

## Set Wave type (Sine, Square, Ramp, Pulse, Noise, DC, Arb) [4-channel only]

## To set standard waveform (Sine, Square, Ramp, Pulse, Noise, DC, frequency, amplitude, offset) [4-channel only]

Press the Utility→ Next Page4/4→AWG → Wave Type, Rotate the Universal Knob to the Sine wave. Then press the knob to select the interface shown as below:
The following table shows the waveform type and its corresponding characteristics.
According to the selected waveform, to set the waveform parameters through Universal Knob and the corresponding function software under the menu.

| Wave Type | Parameters | Frequency y Range | Amplitude (High-Z) | Offset (High-Z) |
|--------------|------------------------------------------------------------------------------------|-----------------------|-----------------------|--------------------|
| Sine | Frequency/Period/Amplitude/Hi gh-Level/Offset/Low-Level value. | 1uHz~25MHz | 4mV~6V | ± 3.0V |
| Square | Frequency/Period/Amplitude/Hi gh-Level/Offset/Low-Level/Duty value. | 1uHz~10MHz | 4mV~6V | ± 3.0V |
| Ramp | Frequency/Period/Amplitude/Hi gh-Level/Offset/Low-Level/Sym metry value. | 1uHz~300KH z | 4mV~6V | ± 3.0V |
| pulse | Frequency/Period/Amplitude/Hi gh-Level/Offset/Low-Level/ Width/ Width Fine value. | 1uHz~10MHz | 4mV~6V | ± 3.0V |
| Noise | Stdev/ Mean value. |  |  |  |
| DC | Offset value. |  |  | ± 3.0V |
| Arb | Frequency//Period/Amplitude/H igh-Level/Offset/Low-Level value |  |  |  |

## To set Arb waveform (Stored Arb, Built-in Arb, EasyWave, U disk) [4-channel only]

Press the Utility→Next Page4/4→AWG→Wave Type, then select the Arb, and it has two types:

## Stored Arb (EasyWave, remote interface, internal storage, external storage) [4-channel only]

Users can edit the Arb through the PC which has installed the EasyWave software. Send the edited Arb to the instrument through remote interface, and the Arb will be stored in the instrument. Or read from the U disk which has stored the Arb. Choose Wave Type→ Arb→ Arb Type→ Stored, enter the Stored Arb interface and invoke the waveform in the internal storage and external storage device.

## Built-in Arb (Common, Math, Engine, Window, Trigo) [4-channel only]

Choose Wave Type→ Arb →Arb Type→ Built-in to enter the following interface, Rotate the knob to move the cursor, press the knob to select to the desired waveform, and then return back to Built-in waveform interface.

## Output Load (High-Z, 50Ω) [4-channel only]

Press Utility→ NextPage4/4→ AWG → Setting→ Output Load to set High-Z or 50Ω.

## Sync Output (Aux In/Out, CMOS signal, same frequency) [4-channel only]

Press Utility→ NextPage4/4→ AWG→ Setting→ Sync Output, the AWG provides Sync output through the [Aux In/Out] connector on the rear panel. When the Sync Output is on, the port can output a CMOS signal with the same frequency as basic waveforms (except the Noise and DC), arbitrary waveforms, and modulated waveforms (except external modulation).

## OVP (Over Voltage Protection) (overvoltage protection, output disabled) [4-channel only]

Press Utility→NextPage4/4→AWG→ Setting→ OVP to turn on or off the function. If the state is set to ON, overvoltage protection of AWG output port take effect once the condition is meeting (the absolute value of input voltage is higher than 4V±0.5V). When overvoltage protection occurs, a message will be displayed and the output is disabled.

## Default button (Sine, 1.000 KHz, 4.000Vpp, 0.0mVdc, High-Z) [4-channel only]

Press Utility →NextPage4/4→ AWG→ Setting→ Default to recover the default values of AWG (Sine, 1.000 KHz, 4.000Vpp, 0.0mVdc, High-Z, Sync output off, OVP On).

## Zero Adjust (Auto mode, Manual mode, calibrate) [4-channel only]

Press Utility→ NextPage4/4→ AWG→ Setting→ Zero Adjust. The AWG can be calibrated by using Auto mode or Manual mode. The adoption standard of AWG calibrated is: when AWG outputs 0V DC signal, the corresponding channel at 1mv/div gear' mean value of oscilloscope is rang in ±1mv.

- Auto mode: This mode can only be performed with the channel1 of oscilloscope. Connect the output of AWG to the oscilloscope ' channel1, press the Auto soft key, then the AWG starts to automatic calibrate, and displays "Zero Adjust Success!".
- Manual mode: The AWG can be manually calibrated through any channel on the oscilloscope.

Take channel 2 as an example:

- a. Connect the output of AWG to the oscilloscope' channel 2, open the channel 2, and set DC coupling, open bandwidth limit, Probe is 1X.
- b. Adjust the voltage of channel 2 channel to 1mv/div, and make the waveform visible in the oscilloscope interface, press the Measure and measure the mean value of channel 2.
- c. Press the Manual and rotate the knob to adjust the waveform, so that the mean value of the observed CH2 will be in the range of ±1mv, and then press the Save, the oscilloscope displays "Zero Adjust Success!".

## System Status (software version, hardware version, serial number) [4-channel only]

Press Utility→NextPage4/4→AWG→System, then select the System Status option to view the AWG's system information, including software version, hardware version,
and serial number. After finished, press the return softkey to exit the system information page.

## Software Update (ads, firmware, U-disk, update) [4-channel only]

The software version file of the AWG can be updated directly via U-disk. Follow the steps below:

1. Insert U -disk with firmware update file (*.ads) to USB host interface on the front panel of the oscilloscope. Than a message "USB Flash Drive detected!" will be displayed.
2. Press Utility →NextPage4/4→ AWG →System →Update.
3. Expand the U disk directory, Select the firmware file (*.ads), then press the Press to update, an upgrade progress bar will be display on the interface.
4. After the updating is finished, the AWG will automatically disconnected and display a message "Update completed, please reconnect AWG device!"
Note： Don't cut off the power during the AWG is being updated！

## Remove Device (AWG device removed, disconnect) [4-channel only]

Press Utility→NextPage4/4→AWG→Remove Device, and the oscilloscope interface display "AWG device removed!", the device can be pulled.

## IO Set (USB Device, LAN, WLAN, Aux Output) [2+4-channel]

The oscilloscope provides abundant IO interfaces, including: USB Device, LAN and Aux Output.

## USB Device (USBTMC, NI Vista, EasyScopeX, USB ID) [2+4-channel]

Do the following steps to set the oscilloscope to communicate with PC via USB:

1. Install the USBTMC device driver on PC. Suggest you install NI Vista.
2. Connect the oscilloscope with PC using a standard USB cable
3. Press the Utility button on the front panel to enter the UTILITY function menu.
4. Press the IO Set softkey to enter the I/O SET function menu.
5. Press the USB Device softkey to view the USB ID.
6. Use EasyScopeX or NI Vista to communicate with the oscilloscope.

## USB Device Printer (print screen image, USB cable, Printer mode) [2+4-channel]

Do the following steps to set the oscilloscope to print the screen image:

1. Connect the oscilloscope with printer using a standard USB cable.
2. Press the Utility button on the front panel to enter the UTILITY function menu.
3. Press the IO Set softkey to enter the I/O SET function menu.
4. Press the USB Device softkey to select Printer.
5. Press the Print button on the front panel to print the screen image.

## LAN Setup (network cable, IP address, DHCP, subnet mask, gateway) [2+4-channel]

Do the following steps to set the oscilloscope to communicate with PC via LAN:

1. Connect the oscilloscope to your local area network using the network cable.
2. Press the Utility button on the front panel to enter the UTILITY function menu.
3. Press the IO Set softkey to enter the I/O SET function menu.
4. Press the Net Interface softkey; then; select LAN.
5. Press the IP Set softkey to enter the IP setting interface, see the picture below:
6. Press the DHCP softkey to turn on or turn off the DHCP.
7. On: the DHCP server in the current network will assign the network parameters (such as the IP address) for the oscilloscope.
8. Off: you can set the IP address, subnet mask, gate way manually.
9. Turn the Universal Knob to select the desired value.
10. Push the Universal Knob to change item horizontally.
11. Press the Save softkey to save the current setting.
7. Use EasyScopeX or NI Vista to communicate with the oscilloscope.

## WLAN (4-channel only) (wireless network adapter, SSID, PSK, WiFi)

SDS1000X-E (4-channel) supports this function. Do the following steps to set the oscilloscope to communicate with PC via WLAN:

1. Connect the oscilloscope USB Host to your wireless network adapter, and make sure your local wireless network is normal.
2. Press the Utility button on the front panel to enter the UTILITY function menu.
3. Press the IO Set softkey to enter the I/O SET function menu.
4. Press the Net Interface softkey; then; select WLAN.
5. Press the WiFi Set softkey to enter the Wi-Fi set interface.
6. Press the Wi -Fi Operation softkey to turn on or turn off the WIFI set menu.
Off: the WIFI set menu off
On: you can set the SSID and PSK manually.

- Manual Scan: press this softkey, the oscilloscope will search the network automatically. Turn the Universal Knob to select a network; then; press Universal Knob to confirm.
- SSID: press this softkey, a dialogue box will pop up, enter your SSID then press Confirm.
- PSK: press this softkey, a dialogue box will pop up, enter your SSID then press Confirm.
- Connect: press this softkey to connect the wireless network.
7. Press Connect softkey when your SSID and PSK configuration finished.
8. Return to the I/O SET menu. Press the IP Set softkey to finish the IP configuration(see "To Set the LAN")
9. Use EasyScopeX or NI Vista to communicate with the oscilloscope.

## Aux Output (Trig Out, Pass/Fail, capture rate, 100k wfs/s) [2+4-channel]

The default Aux output type is Trig Out. If Pass/Fail is enabled, it changes to Pass/Fail automatically.

- Trig Out: the oscilloscope outputs a signal that can reflect the current capture rate of the oscilloscope at each trigger. The maximal capture rate is 100k wfs/s.
- Pass/Fail: the oscilloscope will output a pulse signal when failed waveforms are detected. This signal can be connected to other control systems to conveniently view the test results.

## Web Server (4-Channel only) (web browser, IP address, web interface)

SDS1000X-E (4-channel) provide the web server function; you can access and control the oscilloscope using a web browser. Connect the oscilloscope to your LAN (or WLAN), then type the oscilloscope's IP address in the web browser. The oscilloscope's web interface is displayed. The default user name is "admin", and there is no password.

## Set Password (4-Channel only) (Password, Reset, Save)

1. Press the Utility button on the front panel to enter the UTILITY function menu.
2. Press the WebServer softkey on the fourth page of utility function menu to enter the WEBSERVER menu.
3. Password: press this softkey to set a new password,
4. Reset: press this softkey to reset the password.
5. Save: After setting a new password, press this softkey to make the password effective.

## Web Browser (4-channel only) (IP address, instrument control, screenshot, firmware upgrade)

- 1 Input the IP address of the instrument
- 2 Information of the instrument
- 3 Click here to enter the instrument control interface.
- 1 Display area of the instrument. The display in this area is a copy from the instrument display.
- 2 Click here to show the instrument control area.
- 3 Control area of the instrument. Using the mouse to operate in the area is equivalent to directly operating the instrument through the buttons
- 4 Click here to perform a screen shot
- 5 Click here to save the waveform data as a bin file and download it to the local computer
- 6 Click here to download the mini tool for converting bin file to csv file
- 7 Click here to perform a firmware upgrade

## Counter, Frequency, Period and Totalizer (counter, frequency, period, totalizer, statistics) [4-channel only]

SDS1000X-E (4-channel) supports counter function, which is used to measure the frequency and period of a signal or count the events happening within it. The counter is asynchronous to the acquisition system of the oscilloscope. It can work well even if the acquisition of the oscilloscope is stopped (indicated by a red colored Run/Stop button)

- 1 Press Utility → NextPage2/4 → Counter → On to turn on Counter function menu.
- 2 Press the Mode softkey to select Frequency, Period and Totailzer.
- 3 Press the Source softkey to select the source of the counter. The analog channel can be used as the source.
- 4 Press the Statistics softkey to turn on or off statistics.
- 5 Press the Reset Statistics softkey to clear and restart the statistics.
- 6 Press Next Page1/2 → Level, turn the Universal Knob to set the level of the counter.

When the mode is selected as totalizer, the edge of the counting source needs to be set. When the counting gate is turned on, the counter can count only when the gate source meets the specified conditions.

- 1 Press Gate Setting → On to enter the Counter-Gate function menu.
- 2 Press the Type softkey to select the gate type, Level or After Edge.
- 3 Gate source display area. C1 and C2 are gate sources of each other, C3 and C4 are gate sources of each other.
- 4 When the gate type is level, set the polarity (Positive or Negative) of the gate source. When the gate type is edge, set the slope (Rising or Falling edge) of the gate source.
- 5 Press the Level softkey and turn the Universal Knob to set the gate level.

When statistics are enabled, the counter will increment the data and display the statistics results on the screen.

- Value: The latest count
- Mean: The average of all historical counts
- Min: The minimum of all historical counts
- Max: The maximum of all historical counts
- Stdev: The standard deviation of all historical counts, used to judge the distribution of historical count parameters
- Count: Number of counts obtained
Press the Clear Sweeps button or Reset Statistics softkey to clear and restart statistics.

## Data Logger (Sample logger, Measure logger, waveform data, measurement value) [4-channel only]

SDS1000X-E (4-channel) supports Sample logger and Measure logger, which can record waveform data and measurement value.

## Sample Logger (original points, real time, low-speed signals, replay) [4-channel only]

The Sample logger can record the original points of waveform in real time at equal intervals to realize the long-time observation of low-speed signals. The recorded data can be stored in the internal or external storage device in real time. After stopping recording, users can replay the waveform on the oscilloscope, also can export the recorded data and then analyze on the PC.

Press the Sample Logger softkey to enter the sample logger interface. At this time, all the buttons on the front panel will not respond (except for the menu softkey, Print and Universal Knob). Press the Exit softkey to exit the sample logger.

| No. | Description |
|-------|---------------------------------------------|
| 1 | Recorded waveform |
| 2 | Record status（Run/Stop） |
| 3 | Horizontal scale |
| 4 | Start time |
| 5 | Recorded time |
| 6 | Remaining recordable time |
| 7 | Sample rate and recorded points of waveform |
| 8 | Storage location |

## Record Waveform (Record, Setting, Rate, Internal, External, Start, Stop) [4-channel only]

- 1 Press the Record softkey to enter the RECORD function menu.
- 2 Press the Setting softkey to enter the SETTINGS function menu. Press the Rate softkey to set the sampling rate of the waveform. Press the Record to softkey to set the storage location of the recorded data:
- Internal: Record the data to internal, the last recorded internal data will be overwritten. Please confirm the operation when start to record.
- External: Record the data to external storage device, and set the external storage path.
- 3 Press the Return softkey to return to the RECORD function menu.
- 4 Press the Start softkey to start to record, and the record status in the top information bar is displayed as "Run".
- 5 Press the Stop softkey to stop recording, and the record status in the top information bar is displayed as "Stop", the data is automatically stored in the storage location.
- 6 Press the Recall softkey to look back and analyze the waveform.

Note: When recording to external, the waveform data will be stored to the external in real time. Please do not pull out the U disk during the recording process!

## Recall Recorded Waveform (Recall, Recall from, storage path) [4-channel only]

- 1 Press the Recall softkey to enter the RECALL function menu.
- 2 Press the Recall from softkey to select the storage path.
- 3 Press the Press to Recall softkey to recall the recorded waveform data and

enter the CONTROL menu automatically.

## Display Control (Horizontal Ref, Horizontal Scale, Horizontal Position, View all, Cursors) [4-channel only]

- 1 Press the Horizontal Ref softkey to set the horizontal reference position.
- 2 Rotate the Horizontal Scale knob to zoom the waveform with the horizontal reference as the center. Rotate the Horizontal Position knob to move the waveform.
- 3 Press the View all softkey to return to the initial configuration to view all waveforms.
- 4 After recalling the waveform, press the Cursors button to turn on the cursor function, which can measure and analyze the waveform on the screen. Please refer to the chapter "Cursors" for operation.

## Manage Internal Record (Export Internal Data, Delete Internal Data, slg, fileconverter) [4-channel only]

- 1 Press the Manage softkey to enter the MANAGE function menu.
- 2 Press the Export Internal Data softkey to export the internal record to the external storage device. See the chapter "Save and Recall" for operation. The file format (*.slg) is described in detail in the document "How to Extract Data from the Binary File.docx". Please download from SIGLENT website. The oscilloscope provides a tool named fileconverter to convert the waveform file (*.slg) to CSV format. You can download it from the Save/Recall menu or the webserver.
- 3 Press the Delete Internal Data softkey to delete the internal record.

## Measure Logger (measured value, long-time measurement, trend, 4 traces) [4-channel only]

The Measure logger can record the measured value of waveform in real time to realize the long-time measurement trend observation of low-speed signal. The measurement data is recorded in the internal, and can be stored to the internal or external storage device after stopping recording. It can support up to 4 traces of data at the same time.

Turn on the measure function and add measurement items, then press Utility → NextPage2/4 → Data Logger → Measured Logger to turn on the measure logger; Press the Exit softkey to exit the measure logger.

| No. | Description |
|-------|------------------------------------------------------------------------------------------|
| 1 | Record trace |
| 2 | Record status（Run/Stop） |
| 3 | [Auto/Manual] Horizontal scale |
| 4 | [Auto/Manual] Time value of the first point (centered on horizontal reference position) |
| 5 | Horizontal reference position |
| 6 | Recording interval |
| 7 | Start time |
| 8 | Number of recorded points, Recorded time, Used memory |
| 9 | Remaining recordable time |
| 10 | The current value of measurement items |
| 11 | Upper and lower scale of measurement items |

## Start/Stop Recording (Setting, record interval, record trace, Start, Stop) [4-channel only]

- 1 Press the Setting softkey to enter the SETTINGS function menu. Set record interval, record trace and the corresponding measurement item.
- 2 After setting, press the Return softkey to return to the previous menu.
- 3 Press the Start softkey to start to record, the record status in the top information bar is displayed as "Run". During the recording process, the measure logger automatically adjusts the horizontal scale to show the trace. Users also can turn the horizontal scale/position knob to enter the manual mode to zoom and move the recording trace.
- 4 Press the Stop softkey to stop recording, the record status in the top information bar is displayed as "Stop".

## Display Control (All, single trace, Horizontal Ref, Cursors) [4-channel only]

- 1 Press the Display softkey to select All, all traces are displayed in the waveform area. When a trace is selected, only the selected trace is displayed in the waveform area. Press the channel button corresponding to the trace to switch all/individual display.

## Single Trace Display (Select, Strategy, Fixed Position, Fixed Time, Track Mode) [4-channel only]

- 2 Press the Horizontal Ref softkey to set the horizontal reference position.
- 3 Press the Cursors button to turn on the cursors function. Move the cursor to obtain the measured value of each point.
- a. Press the Select softkey to select the cursor T1, T2 or T1 -T2.
- b. Press the Strategy softkey to choose the behavior of cursors when horizontal scale or position is changed.
- Fixed Position: cursors remain fixed to the grid position on the display
- Fixed Time: the value of cursors remain fixed.
- c. Press the Track Mode softkey to select the track mode of T-Cursors.
- Normal: Track the data at the time of T -Cursors
- Maximum: Track the maximum value of the data within a pixel where T -Cursors are located.
- Average: Track the average value of the data within a pixel where T -Cursors are located.
- Minimum: Track the minimum value of the data within a pixel where T -Cursors are located.
- Peak: Track the data with the maximum deviation from the overall average value in a pixel where T-Cursors are located. When two cursors are at the same position, T1 will track the maximum value and T2 will track the minimum value.

## Storage Measurement Record (Save/Recall, Save to, Internal, External, mlg, CSV, MATLAB) [4-channel only]

- 1 Press the Save/Recall softkey to enter the SAVE/RECALL function menu.
- 2 Press the Save softkey to enter the SAVE menu.
- 3 Press the Save to softkey to select where to store.
- Internal: The measurement data will be saved in binary data format, and the last data stored internally will be overwritten.
- External: The measurement data can be saved as binary data(*.mlg), CSV data or MATLAB data
- 4 Press the Press to save softkey to save.

## Recall Measurement Record (Recall from, Internal, External, binary, MATLAB) [4-channel only]

- 1 Press Save/Recall → Recall to enter the RECALL function menu.
- 2 Press the Recall from softkey to select where to recall. Only binary files can be recalled from internal; while binary files or MATLAB files can be recalled from external. If the current data is not saved, it will be covered by the recalled the data.
- 3 Press the Press to Recall softkey to recall.

## Manage Internal Record (Export, Delete, Sample Logger) [4-channel only]

Export or delete the internal record, it is similar to "Manage Internal Record" of Sample Logger.

## Update Firmware and Configuration (firmware, configuration, USB flash, ADS, CFG) [2+4-channel]

The firmware and configuration can be updated directly via USB flash driver.
Do the following steps to update the firmware:

1. Insert the USB flash driver which with the firmware and the configure files inside into the USB host interface on the front panel of the oscilloscope.
2. Press the Utility button on the front panel to enter the UTILITY function menu.
3. Press the Next Page softkey to go to the third page of the UTILITY function menu.
4. Press the Update softkey to enter the UPDATE function menu.
5. Press the Firmware softkey to open the file manager.
6. Turn the Universal Knob to select the update file which should be with an ADS postfix; and then press the Press to Update softkey to start update the firmware. The process needs about 7 minutes. And during the update, do not remove power to the oscilloscope, otherwise the oscilloscope may be permanently damaged and may not restart again.
7. After finish the update, the screen will pop-out the message "Firmware decompressed. Please restart and wait …".
8. Restart the oscilloscope to finish the firmware update.

Do the following steps to update the configuration:

1. Insert the USB flash driver which with the firmware and the configure files inside into the USB host interface on the front panel of the oscilloscope.
2. Press the Utility button on the front panel to enter the UTILITY function menu.
3. Press the Next Page softkey to go to the third page of the UTILITY function menu.
4. Press the Update softkey to enter the UPDATE function menu.
5. Press the Configure softkey to open the file manager.
6. Turn the Universal Knob to select the update file (*.CFG file extension) and then press the Press to Update softkey to start update the firmware. The process needs about 30 seconds.
7. After finish the update, the screen will pop-out the message "Firmware decompressed. Please restart and wait…"
8. Restart the oscilloscope to finish the configuration update.

## Do Self-Test (screen test, keyboard test, LED test) [2+4-channel]

Self-tests include screen test, keyboard test, and LED test. Self-tests used to test the screen, buttons, knobs and LED lights whether works well.

## Screen Test (pure red, green, blue, chromatic aberration, stain, scratch) [2+4-channel]

1. Press the Utility button on the front panel to enter the UTILITY function menu.
2. Press the Next Page softkey to go to the third page of the UTILITY function menu.
3. Press the Do Self Test softkey to enter the SELFTEST function menu.
4. Press the Screen Test softkey to enter the screen test interface, as the picture shown below, the screen display pure red.
Press 'Single' key to continue,press 'Run/Stop' key to exit
5. Press the Single button on the front panel continually as it says in the picture above. The screen displays green, blue and red again. It is easy to check chromatic aberration, stain and scratch of the screen under the condition.
6. Press the Run/Stop button on the front panel to exit the screen test program.

## Keyboard Test (knobs test, keys test, Run/Stop) [2+4-channel]

Keyboard test is used to test that if the keys or the knobs work well.

Do the following steps to do keyboard test:

1. Press the Utility button on the front panel to enter the UTILITY function menu.
2. Press the Next Page softkey to go to the third page of the UTILITY function menu.
3. Press the Do Self Test softkey to enter the SELFTEST function menu.
4. Press the Keyboard Test softkey to enter the keyboard test interface, as the picture shown below.
5. To perform the knobs and the buttons test.
6. Knobs test: the default value is 0. Turn left to increase the value while turn right to decrease; push the knob to set the value to 0. Test every knob randomly.
7. Keys test: the first time to press the key to light it up, and a second press to die out. Test every button randomly.
8. Press the Run/Stop button 3 times to exit the keyboard test program.

## LED Test (button lights, Run/Stop, red, green) [2+4-channel]

LED test is used to test that if the button lights work well.

1. Press the Utility button on the front panel to enter the UTILITY function menu.
2. Press the Next Page softkey to go to the third page of the UTILITY function menu.
3. Press the Do Self Test softkey to enter the SELFTEST function menu.
4. Press the LED Test softkey to enter the keyboard test interface, as the picture shown below.
5. According to the prompting information displaying on the screen, press the Single button continually to light the button lights one by one. The first time to press the Single button, the Run/Stop button displays red, and the second press the Run/Stop button displays green. Then the other button lights will be lighted one by one. At last all the lights will be lighted at the same time.
6. Press the Run/Stop button to exit the LED test program.

## Screen Saver (idle state) [2+4-channel]

When the oscilloscope enters the idle state and holds for a certain period of time, the screen saver program will be enabled.

Do the following steps to set the screen saver time:

1. Press the Utility button on the front panel to enter the UTILITY function menu.
2. Press the Next Page softkey to go to the third page of the UTILITY function menu.
3. Press the Screen Saver softkey; and then turn the Universal Knob to select the desired screen saver time. The screen saver time can be set to 1min, 5min, 10min, 30min, and 1hour. Also you can select Off to turn off the screen saver function
4. Press the any button on the front to exit the screen saver program.

## Date/Time (date, time, Display, NTP, time zone) [4-channel only]

SDS1000X-E (4-channel) supports setting date and time. After restarting the oscilloscope, you need to reset the system time.

- 1 Press Utility → NextPage3/4 → Date/Time to enter the DATA/TIME function menu.
- 2 Press the Display softkey to select On to display the date and time.

## Set Date/Time (Date, Time, year, month, day) [4-channel only]

Press the Date/Time softkey to enter the Data/Time setting menu. Press the Date softkey and press the Universal Knob to select year, month or day, then rotate the Universal Knob to change value. Modifying the time is similar to the date.

## Set Time Zone (Time Zone, Confirm) [4-channel only]

- 1 Press the Time Zone softkey to enter the Time Zone function menu, and pop up time zone page.
- 2 Rotate the Universal Knob to select the time zone.
- 3 Press the Confirm softkey to confirm the selection.

## Set NTP (Server IP, Sync, Power On Sync, Periodic Sync, Interval) [4-channel only]

- 1 Press the NTP softkey to enter the NTP function menu,
- 2 Press the Server IP softkey to set the server IP address according to the prompt and press the Sync softkey to synchronize the time.
- 3 Press the Power On Sync softkey to select On or Off. When set to On, the oscilloscope will automatically synchronize the time after the power on.
- 4 Press the Periodic Sync softkey to select On; press the Interval softkey and rotate Universal Knob to set the value.

## Reference Position (Fixed Offset, Fixed Position, Fixed Delay, vertical, horizontal) softkeys [2+4-channel]

The reference position setting determines the physical point that the oscilloscope uses during vertical and horizontal scale changes. In some situations, it is more convenient to use a fixed position on the display.

Press the Utility button on the front panel and then press the Reference Pos. softkey to enter the Reference POS menu.

Press the Vertical softkey to select Fixed Offset or Fixed Position.

Fixed Position: when the vertical gain is changed, the oscilloscope will keep the vertical offset level indicator stationary.

Fixed offset: when the vertical gain is changed, the oscilloscope will have the vertical offset level indicator move with the actual voltage level.

Press the Horizontal softkey to select Fixed Delay or Fixed Position.

Fixed Position: when the timebase is changed, the oscilloscope will keep the horizontal offset indicator stationary.

Fixed Delay: when the timebase is changed, the oscilloscope will have the horizontal offset indicator move with the trigger point.

## Power On Line (Enable, Disable, auto start) [2+4-channel]

Press the Utility button on the front panel; then; press Power On Line softkey to select Enable or Disable.

- Enable: when the oscilloscope is energized, the oscilloscope will start automatically by itself.
- Disable: when the oscilloscope is energized; then; press the power key at the lower -left corner of the front panel to start the oscilloscope.

## Option Management - Install License (license, option, install, Type, module) [2+4-channel]

The SDS1000X-E and SDS1000X-U provide multiple options to fulfill your measurement requirements. Please contact your SIGLENT sales representative or SIGLENT technical support to order the corresponding options. You can view the options currently installed on the oscilloscope or activate the newly purchased option license codes through this menu.

Do the following steps to install the option on the oscilloscope:

1. Press the Utility button on the front panel to enter the UTILITY function menu.
2. Press the Next Page softkey to go to the third page of the UTILITY function menu.
3. Press the Options softkey to enter the OPTION function menu.
4. Press the Type softkey; then turn the Universal Knob to select the module to be installed and push down the knob to confirm.
5. Press the Install softkey to enter the LABEL function menu to input the license.
6. Turn the Universal Knob to select character
7. Push down the Universal Knob to confirm the characters
8. Press the Press To Install when license key input done,
- Press the Clean softkey or the Backspace softkey to delete the incorrect character.
6. Press the Information softkey to view the option information.

## Bode Plot II (4-channel only) (gain, phase, sweep, DUT, arbitrary waveform generator)

The bode plot application for the SDS1000X-E (4-channel only) control an external arbitrary waveform generator(only Siglent's arbitrary waveform generator can be supported) to sweep a sine wave across a range of frequencies while measuring the input to and output from a device under test (DUT). At each frequency point, gain and phase are measured and displayed on the Bode plot.

## Perform Bode Plot (4-channel only) (Config, Run, sweep, parameters)

The following steps briefly describe how to perform the Bode Plot:
1. Press the Utility button on the front panel to enter the UTILITY function menu, and then press the Next Page softkey to enter the second page.
2. Press Bode Plot II softkey to enter the BODE PLOT II menu. At this time, only the Default and Auto Setup button which on the front panel are available.
3. Configure the parameters (see the section "Setting" for details).
4. Press the Run softkey to perform the test.

## Example Simple Sweep Operation (Source, Sweep Mode, Simple, Set Sweep, Set Stimulus, Set Channel) [4-channel only]

1. Press Utility button on the front panel to enter the UTILITY function menu, and then press the Next Page soft key to enter the second page. Press Bode Plot Ⅱ to enter the BODE PLOT function menu. Press Config to enter Configure menu.
2. Press Source to enter Source menu to select the waveform generator. In this example, press Interface to select "USB", and then press Connection Test to verify setting. Then return to the Configure menu.
3. Press Sweep Mode to select "Simple".
4. Press Set Sweep to enter Set Sweep menu. In this example, press Mode to select "Decade" to sweep frequency logarithmically. Press Start and use the Universal Knob to set the start frequency to 100 Hz. Then set stop frequency to 1 MHz. Press Points/dec and use the Universal Knob to set the frequency point to 20 points per decade. Then return to the Configure menu.
5. Press Set Stimulus to enter Set Stimulus menu. Press Amplitude and use the Universal Knob to set the signal amplitude to 2 V. All the other options remain
their default setting. Then return to the Configure menu.
6. Press Set Channel to enter Set Channel menu. In this example, set DUT Input to "CH1", and DUT Output 1 to "CH2". Other DUT Output remains "None". Since we want to maximize measurement dynamic range, set Channel Gain to "Auto". Then return to the Configure menu.
7. Configuration was done. Return to root menu and press Run, and wait for the sweep to complete.

## Example Vari-level Sweep Operation (Vari-level, profile, joints, spreadsheet, linear interpolation) [4-channel only]

1. Press Utility button on the front panel to enter the UTILITY function menu, and then press the Next Page soft key to enter the second page. Press Bode Plot Ⅱ to enter the BODE PLOT function menu. Press Config to enter Configure menu.
2. Press Source to enter Source menu to select the waveform generator. In this example, press Interface to select "USB", and then press Connection Test to verify setting. Then return to the Configure menu.
3. Press Sweep Mode to select "Vari -level".
4. Press Set Vari -level to enter Vari -level editor. On the left side of the editor is a spreadsheet which is used to specify the relationship between frequency and amplitude. On the right side is an automatically generated stimulus voltage vs. frequency plot.
5. The operation principle of Vari-level is simple. User specifies a series of joint, which is defined by a given frequency and corresponding amplitude. In between two adjacent joints, the frequency points and their corresponding amplitude are calculated automatically by linear interpolation. The frequency of the joints is sequential, so the frequency of the posterior joint is always higher than the frequency of the anterior joint. And always, the first and the last joint defines the start and stop frequency.
6. Press Profile and use the Universal Knob to select "Profile A". As you can see, up to 4 profiles can be saved.
7. In this example, I will demonstrate how to specify a Vari-level profile widely used in testing power supply loop response. The profile is a 4-jointpolyline with large stimulus amplitude in low frequency and small amplitude in high frequency, and gradual amplitude in intermediate frequency.
8. Press Joints and use the Universal Knob to set the number of joint to 4.
9. Press Edit Table to activate the spreadsheet editor. When the spreadsheet editor is activated, press Edit Table will cycle the cursor between frequency, amplitude and the entire column. Then use the Universal Knob to adjust the frequency, the amplitude, or to select the column to be edited. Press the Universal Knob will activate the visual keypad for more precise input.
10. The Set Sweep and Set Stimulus in Vari-level editor are similar to that in the Simple sweep mode, but they are independently configured and do not affect each other. These options in Vari-level mode do not have frequency and amplitude input because they are specified in the spreadsheet. Press Set Sweep and then set Mode to "Decade", and set Points/dec to 20. The Set Stimulus remains default setting.
11. Return to Configure menu and press Set Channel. Set DUT Input to "CH1" and DUT Output 1 to "CH2", and Channel Gain to "Auto".
12. Configuration was done. Return to the root menu and press Run and wait for the sweep to complete.

## Bode Plot Configure (AWG, AWG I/O, Sweep, Channel, DUT Input, DUT Output) [4-channel only]

Press Configure softkey to enter the Configure menu. All the parameters in this menu are used to configure the external AWG.

1. Press AWG softkey to enter AWG menu.
- Press Amplitude softkey (Offset softkey); then turn the Universal Knob to select the desired value or press the Universal Knob then enter the value by the pop keyboard.
- Press Unit softkey; then turn the Universal Knob to select the desired unit. There are six types: Vpp, Vrms, dBV, dBu, dBm, Arbitrary dB. The dBu is only available when the load impedance is specified as 600 Ω.
- Press Load softkey; then turn the Universal Knob to select the desired value or press the Universal Knob then enter the value by the pop keyboard.
2. Press AWG I/O softkey to enter AWG I/O menu.
- Press Type softkey; then turn the Universal Knob to select the desired type.
- USB: connect the oscilloscope USB Host to the external AWG's USB Device via a USB cable.
- LAN: connect the oscilloscope and the external AWG to your local area network.
- If LAN is selected, press IP softkey, a dialog box named "IP" will pop up; then turn the universal knob to enter the value. The IP is the external AWG's IP.
- Press Test Connection softkey to check the connection.
3. Press Sweep softkey to enter Sweep menu.
- Linear mode provides the parameters center frequency and span frequency.
- Logarithmic mode provides the parameters start frequency and stop frequency.
- Press Resolution softkey; then turn the universal knob to select the type. There are three resolution levels: Low, Medium, and High.
4. Press Channel softkey to enter Channel menu. Press DUT Input softkey to choose the oscilloscope's channel which connects to the DUT input (the AWG's output). Press DUT Output1 softkey to choose the oscilloscope's channel which connects to the DUT output (up to 3 channels).

## Bode Plot Display (Amplitude, Phase, Cursors, Ref Level, Auto Set, Vout/Vin, deg, rad) [4-channel only]

Press Display softkey to enter the Display menu. All the parameters in this menu are used to configure the bode chart.

1. Press Amplitude softkey to enter Amplitude menu.
- Press Scale softkey; then turn the Universal Knob to select the desired value.
- Press Ref Level softkey; then turn the Universal Knob to select the desired value or press the Universal Knob then enter the value by the pop keyboard.
- Press Auto Set softkey to set the appropriate parameters for the frequency response gain curve automatically.
- Press Mode softkey to set the mode of the frequency response gain curve. Vout/Vin means that the measured gain value of each frequency point is the ratio of DUT input signal amplitude to DUT output signal amplitude. Vout means that the measured gain value of each frequency point is the DUT output signal amplitude. When Vout/Vin mode is enabled, the Y-Axis can be set to linear or logarithmic by pressing Axis Type softkey. When Vout mode is enabled, six unit types can be chosen by pressing Unit softkey.
2. Press Phase softkey to enter the Phase menu.
- Press Scale softkey; then turn the Universal Knob to select the desired value.
- Press Ref Level softkey; then turn the Universal Knob to select the desired value or press the Universal Knob then enter the value by the pop keyboard.
- Press Unit softkey to set the unit to deg or rad.
- Press Auto Set softkey to set the appropriate parameters for the frequency response phase curve automatically.
3. Press Cursors softkey to enter the Cursors menu. Press Status softkey in this menu to enable or disable the cursors function. The details of cursors see the Cursors chapter.

## Bode Plot Data (List, Source, Save, Recall) [4-channel only]

Press Data softkey to enter the Data menu. All the parameters in this menu are used to configure the bode chart.

1. Press List softkey to select On or Off to turn on or turn off the list table. When the list is on, press Scroll softkey; then turn the Universal Knob to select the frequency point or press the Universal Knob then enter the number of the frequency point by the pop keyboard.
2. Press Source softkey to choose the output DUT channel that you desire.
3. Press Save softkey (Recall softkey) to enable the bode plot save (recall) function. The details of save (recall) see the Save and Recall chapter.

## Search (search events, white triangle, YT mode, Roll mode, zoom) [4-channel only]

SDS1000X-E (4-channel）and SDS1000X-U provide search function. This function can search for the events that users specify in the acquired data, the results are displayed with white triangle symbol. In the YT mode or the Roll mode with the acquisition in stop, the maximum search events number is 700.In the Roll mode with acquisition in run, the maximum search events number is unlimited. The waveform can be zoomed when search function is enabled.

## Setting (Edge, Slope, Pulse, Interval, Runt, Copy Setting, Thresholds) [4-channel only]

1. Press the Search button on the front panel to enter the SEARCH function menu.
2. Press the Mode softkey and then use the Universal Knob to select the desired search type. SDS1000X-E and SDS1000X-U provide five search types: Edge, Slope, Pulse, Interval and Runt.
3. Press the Setting softkey to enter the SETTING function menu. The setting menu is different according to every search type. The details show as the following table.

| Search Mode | Setting Menu Description |
|---------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Edge | Slope includes Rising, Falling, Either. |
| Slope | Slope includes Rising, Falling Limit Range includes four types: <=, >=, [--, -- ] and --] [--, Users can select the desired type and then input the time value. |
| Pulse | Polarity includes Positive and Negative Limit Range includes four types: <=, >=, [--, -- ] and --] [--, Users can select the desired type and then input the time value. |
| Interval | Slope includes Rising, Falling Limit Range includes four types: <=, >=, [--, -- ] and --] [--, Users can select the desired type and then input the time value. |
| Runt | Polarity includes Positive and Negative Limit Range includes four types: <=, >=, [--, -- ] and --][--, Users can select the desired type and then input the time value |

4. Press the Copy Setting softkey to enter COPY function menu.
2. Copy from Trig: copy the trigger setup for the selected search type to the search setup.
3. Copy to Trig: copy the setup for the selected search type to the same trigger type.
4. Cancel Copy: undo a copy.
5. Press the Thresholds softkey to enter THRESHOLDS function menu, then, to set channel search thresholds.

## Results (EVENT NUM, total events, current event) [4-channel only]

When the acquisition is started, “EVENT NUM: 7” means total events number.
When the acquisition is stop, "EVENT NUM: 4/7" means current event number/total events number, the current event is the closest event to the middle of the screen.

## Navigate (Search Event, Time, History Frame) [4-channel only]

SDS1000X-E(4-channel） and SDS1000X-U provide three navigate type: Search Event, Time, History Frame.

## Time Navigate (Time, navigation keys, play backward, stop, play forward) [4-channel only]

1. Press the Navigate on the front panel to enter the NAVIGATE function menu.
2. Press the Type softkey In the NAVIGATE function menu, then select Time.
3. There are two ways to navigate time.
- a. Press the Time softkey, then, turn the Universal Knob to select the desired value or press the Universal Knob then enter the value by the pop keyboard.
- b. Press the navigation keys ◀■▶ on the front panel to play backward, stop, or play forward in time. You can press the ◀ or ▶ keys multiple times to speed up the playback. There are three speed levels: Low Speed, Medium Speed, and High Speed.

## History Frame Navigate (History, Frame Num, navigation keys) [4-channel only]

When the History function is enabled, you can use the navigation controls to play through the acquired frames.

1. Press the Navigate on the front panel to enter the NAVIGATE function menu.
2. Press the Type softkey in the Navigate Menu, then select History Frame.
3. Press the Frame Num softkey, then there are two ways to navigate history frames.
- a. Turn the Universal Knob to select the desired number or press the Universal Knob then enter the number by the pop keyboard.
- b. Press the navigation keys ◀■▶ on the front panel to play backward, stop, or play forward.

## Search Event Navigate (Search, Event Num, navigation keys) [4-channel only]

When the Search function is enabled and acquisitions are stopped, you can use the navigation controls to go to found search events

1. Press the Navigate on the front panel to enter the NAVIGATE function menu.
2. Press the Type softkey in the NAVIGATE function menu, then select Search Event.
3. There are two ways to navigate search events.
- a. Press the Event Num softkey, then, turn the Universal Knob to select the desired value or press the Universal Knob then enter the value by the pop keyboard.
- b. Press the Navigate keys ◀ ▶ on the front panel to go to the previous or next search event.

## History (record waveforms, Run/Stop, YT, frame, timestamp, replay) [2+4-channel]

The history function can record the waveforms of the input channels before press the Run/Stop button. In run state, the oscilloscope records input waveform continually; when fill up the memory (reach the maximal frame), the new frames will cover the old frames and keep the latest frames.

To use the History function, the HORIZONTAL Format must be set to YT.

Do the following steps to record and replay waveform:
1. Press the History button on the front panel to enable the History function.
2. When in run state, the waveform will enter the stop state.
3. When in stop state, and then enable the History function, the oscilloscope will keep the stop state.
4. Press the History button again or press the Stop button to turn off History function.
2. Press the List softkey to turn on or off the list display. The list records the timestamp of every frame. It is accurate to microseconds.
3. Press the Frame No. softkey; then turn the Universal Knob to select the frame to display.
7. The format of the Frame is A/B; A is the frames number that displaying on the screen and B is the maximal frame number you can set.
8. The maximal frame number is determined by the current sampling point

(Curr value) and sampling rate.

- When press the Run/Stop button or enable the history function, you may not get the maximal frames, because the memory is not filled. So if you want to get the maximal frames, please wait for enough time for acquisition.
4. Press the softkey to replay the waveform from the current frame to 1.
5. Press the softkey to stop replay.
6. Press the softkey to replay the waveform from the current frame to the last frame.

## History Max Frames (sample rate, Curr points, 80000 frames, 1GSa/s, 500MSa/s, 250MSa/s) [2+4-channel]

The table shows the maximal frame according to the sampling rate and current sampling point's number.

| Sample Rate | Curr (pts) | Max. Frame |
|-------------|------------|------------|
| 1GSa/s | ≤280 | 80000 |
| 1GSa/s | 700 | 57227 |
| 1GSa/s | 1.4K | 33528 |
| 1GSa/s | 2.8K | 18338 |
| 1GSa/s | 7K | 7773 |
| 1GSa/s | 14K | 3982 |
| 1GSa/s | 28K | 1993 |
| 1GSa/s | 70K | 798 |
| 1GSa/s | 140K | 398 |
| 1GSa/s | 280K | 198 |
| 1GSa/s | 700K | 78 |
| 1GSa/s | 1.4M | 38 |
| 1GSa/s | 2.8M | 18 |
| 1GSa/s | 7M | 7 |
| 1GSa/s | 14M | 3 |
| 500MSa/s | ≤35 | 80000 |
| 500MSa/s | 70 | 77026 |
| 500MSa/s | 140 | 65667 |
| 500MSa/s | 350 | 45526 |
| 500MSa/s | 700 | 29140 |
| 500MSa/s | 1.4K | 16945 |
| 500MSa/s | 3.5K | 7510 |
| 500MSa/s | 7K | 3912 |
| 500MSa/s | 14K | 1958 |
| 500MSa/s | 35K | 783 |
| 500MSa/s | 70K | 391 |
| 500MSa/s | 140K | 195 |
| 500MSa/s | 350K | 77 |
| 500MSa/s | 700K | 38 |
| 500MSa/s | 1.4M | 18 |
| 500MSa/s | 3.5M | 6 |
| 500MSa/s | 7M | 3 |
| 500MSa/s | 14M | 1 |
| ≤250MSa/s | 3.5K | 3779 |
| ≤250MSa/s | 7K | 1891 |
| ≤250MSa/s | 14K | 945 |
| ≤250MSa/s | 17.5K | 757 |
| ≤250MSa/s | 35K | 378 |
| ≤250MSa/s | 70K | 188 |
| ≤250MSa/s | 140K | 93 |
| ≤250MSa/s | 175K | 74 |
| ≤250MSa/s | 700K | 17 |
| ≤250MSa/s | 1.4M | 8 |
| ≤250MSa/s | 1.8M | 6 |
| ≤250MSa/s | 3.5M | 3 |
| ≤250MSa/s | 7M | 1 |
| ≤250MSa/s | 14M | 1 |

## Factory Setup (Factory Setup, Default button, Save/Recall) [2+4-channel]

Press Save/Recall function key, then press Save menu select To Default Key set the type to Factory Setup. Then press the Default button on the front to set the oscilloscope to the leave factory setup. Another way is press Save/Recall function key, then press Recall menu select Factory Default to recall.

## Factory Default Settings - Horizontal and Vertical (T/div, Delay, Zoom, Format, Channel, V/div, Offset, Coupling, BW Limit, Probe, Impedance, Invert) [2+4-channel]

| Horizontal | Default |
|------------|---------|
| T/div | 1μS/div |
| Delay | 0S |
| Zoom | Off |
| Format | Y-T |

| Vertical | Default |
|----------|---------|
| Channel on/off | CH1 |
| V/div | 1 V/div |
| Offset | 0V |
| Coupling | DC |
| BW Limit | Full |
| Adjust | Coarse |
| Probe | 1X |
| Impedance | 1 MΩ |
| Unit | V |
| Invert | Off |

## Factory Default Settings - Acquire, Trigger, Display, Cursor (Acquisition, Sinx/x, Mem Depth, Edge, Holdoff, Vectors, Persist, Intensity, Graticule, Transparence) [2+4-channel]

| Acquire | Default |
|---------|---------|
| Acquisition | Normal |
| Sinx/x | Sinx |
| Mem Depth | 14 Mpts |

| Trigger | Default |
|---------|---------|
| Type | Edge |
| Source | CH1 |
| Slope | Rising |
| Holdoff | Off |
| Coupling | DC |
| Noise Reject | Off |
| Mode | Auto |

| Display | Default |
|---------|---------|
| Type | Vectors |
| Color | Off |
| Persist | Off |
| Grid |  |
| Intensity | 50% |
| Graticule | 20% |
| Transparence | 80% |

| Cursor | Default |
|--------|---------|
| Mode | Off |
| Type | X1 |
| Source | CH1 |
| X1 | -3.5μs |
| X2 | 3.5μs |

## Factory Default Settings - Save/Recall, Utility, Pass/Fail (Setups, Internal, USBTMC, Trig Out, Sound, Enable Test, X Mask, Y Mask, Quick-Cal, Screen Saver) [2+4-channel]

| Save/Recall | Default |
|-------------|---------|
| Type | Setups |
| Save To | Internal |
| Setup | NO.1 |

| Utility | Default |
|---------|---------|
| IO Set - USB Device | USBTMC |
| IO Set - Aux Output | Trig Out |
| Sound - Sound | On |
| System Setup - Quick-Cal | Off |
| System Setup - Screen Saver | 30min |

| Pass/Fail | Default |
|-----------|---------|
| Enable Test | Off |
| Source | CH1 |
| Operate | Off |
| Mes Display | Off |
| X Mask | 0.2 |
| Y Mask | 0.2 |
| Location | Internal |
| Fail To Stop | Off |
| Output |  |

## Factory Default Settings - Math and REF (Addition, Subtraction, Multiplication, Division, FFT, d/dt, Integral, Square Root, REFA) [2+4-channel]

| Math | Default |
|------|---------|
| Operate | Off |
| + Source A / Source B | CH1 |
| + Invert | Off |
| + V/div | 1.00 V/div |
| + offset | 0V |
| - Source A / Source B | CH1 |
| - Invert | Off |
| - V/div | 1.00 V/div |
| - offset | 0V |
| * Source A / Source B | CH1 |
| * Invert | Off |
| * V/div | 1.00 V^2/div |
| * offset | 0 V^2 |
| / Source A / Source B | CH1 |
| / Invert | Off |
| / V/div | 1.0/div |
| / offset | 0 |
| FFT Source | CH1 |
| FFT Window | Hanning |
| FFT Horizontal | 1X |
| FFT Vertical Scale | 20 dBVrms |
| FFT Display | Split |
| FFT Horizontal Scale | 100MHz |
| d/dt Source | CH1 |
| d/dt Vertical Scale | 1.00 (MV/S)/div |
| d/dt Vertical Offset | 0 |
| d/dt dx | 0.2 div |
| ∫dt Source | CH1 |
| ∫dt Offset | 0 |
| ∫dt Vertical Scale | 1.00 μVS/div |
| ∫dt Vertical Offset | 0 |
| √ Source | CH1 |
| √ Vertical Scale | 1.00 V1/2/div |
| √ Vertical Offset | 0 |

| REF | Default |
|-----|---------|
| Source | CH1 |
| Location | REF A |
| Display | Off |

## Performance Test Setup (warm-up 30 minutes, Fluke 9500B, GPIB, USB, BNC, 50 Ω) [2+4-channel]

Allow the test equipment and the oscilloscope to warm up for 30 minutes before testing. Required equipment: Fluke 9500B high-performance oscilloscope calibrator with active heads, GPIB card/cable, USB cable, BNC(m)-BNC(m) cables, BNC T connectors, 50 Ω feedthrough terminations and a PC. Set the 9500B output impedance to 50 Ω and use 50 Ω feedthrough terminators where specified. Perform Self Calibration after a temperature change of 5 °C or more.

## DC Gain Accuracy (2 mV/div to 10 V/div, ±3%, ±4% at 2 mV/div, LINEST) [2+4-channel]

Connect all channels to the 9500B, set 2 mV/div and display the Mean measurement. For each vertical range apply five DC levels (positive, half-positive, zero, half-negative, negative), record Vmean and calculate Verror = VSetting - Vmean. Perform a linear regression over the five points; the slope must be within the specified accuracy. DC gain accuracy is also calculated as (|Vmea1|+|Vmea2|-(|Vset1|+|Vset2|))/(|Vset1|+|Vset2|)×100%.

| Volt/Div | DC voltage output levels | Accuracy |
|----------|--------------------------|----------|
| 10 V/div | 30 V, 15 V, 0, -15 V, -30 V | ±3% |
| 5 V/div | 15 V, 7.5 V, 0, -7.5 V, -15 V | ±3% |
| 2 V/div | 6 V, 3 V, 0, -3 V, -6 V | ±3% |
| 1 V/div | 3 V, 1.5 V, 0, -1.5 V, -3 V | ±3% |
| 500 mV/div | 1.5 V, 0.75 V, 0, -0.75 V, -1.5 V | ±3% |
| 200 mV/div | 600 mV, 300 mV, 0, -300 mV, -600 mV | ±3% |
| 100 mV/div | 300 mV, 150 mV, 0, -150 mV, -300 mV | ±3% |
| 50 mV/div | 150 mV, 75 mV, 0, -75 mV, -150 mV | ±3% |
| 20 mV/div | 60 mV, 30 mV, 0, -30 mV, -60 mV | ±3% |
| 10 mV/div | 30 mV, 15 mV, 0, -15 mV, -30 mV | ±3% |
| 5 mV/div | 15 mV, 7.5 mV, 0, -7.5 mV, -15 mV | ±3% |
| 2 mV/div | 6 mV, 3 mV, 0, -3 mV, -6 mV | ±4% |

At 500 mV/div, test at 1 GSa/s (one channel active) and 250 MSa/s (1.4 Mpts, two channels active) with 1.5 V and -1.5 V; accuracy ±3%.

## Offset Accuracy (2 mV/div to 10 V/div, slope ±1.5%, zero input limits) [2+4-channel]

For each vertical range set the channel offset to -Offset and the 9500B output to the same value, record Vmean and calculate Offseterror = Vmean - Offset. Perform a linear regression; the slope error must be within ±1.5%. With offset 0, turn the 9500B output off and check that |Vzero| is within the zero-input limit.

| Volt/Div | Offset levels | Slope error | Zero input |
|----------|---------------|-------------|------------|
| 10 V/div | 35 V, 30 V, 0, -30 V, -35 V | ±1.5% | ±1.202 V |
| 5 V/div | 30 V, 25 V, 0, -25 V, -30 V | ±1.5% | ±0.602 V |
| 2 V/div | 20 V, 10 V, 0, -10 V, -20 V | ±1.5% | ±0.242 V |
| 1 V/div | 10 V, 5 V, 0, -5 V, -10 V | ±1.5% | ±0.122 V |
| 500 mV/div | 5 V, 2.5 V, 0, -2.5 V, -5 V | ±1.5% | ±0.062 V |
| 200 mV/div | 2 V, 1 V, 0, -1 V, -2 V | ±1.5% | ±0.026 V |
| 100 mV/div | 1 V, 0.5 V, 0, -0.5 V, -1 V | ±1.5% | ±0.014 V |
| 50 mV/div | 500 mV, 250 mV, 0, -250 mV, -500 mV | ±1.5% | ±0.008 V |
| 20 mV/div | 200 mV, 100 mV, 0, -100 mV, -200 mV | ±1.5% | ±0.0044 V |
| 10 mV/div | 100 mV, 50 mV, 0, -50 mV, -100 mV | ±1.5% | ±0.0032 V |
| 5 mV/div | 50 mV, 25 mV, 0, -25 mV, -50 mV | ±1.5% | ±0.0026 V |
| 2 mV/div | 20 mV, 10 mV, 0, -10 mV, -20 mV | ±1.5% | ±0.00224 V |

## Time Base Accuracy (50 ms/div, 14 Mpts, 20 MSa/s, frequency error < 500 Hz) [2+4-channel]

Connect the 9500B to the selected channel and set both impedances to 1 MΩ. Set 100 mV/div, 50 ms/div, Memory Depth 14 Mpts (20 MSa/s) and disable Roll mode. Apply a 600 mV sine at 20 MHz and display the Frequency measurement. The frequency error must be less than 500 Hz.

## Trigger Delay (50 MHz, 800 mV sine, 2 ns/div, abs(T@L) ≤ 100 ps) [2+4-channel]

Connect the 9500B to the channel and set both impedances to 1 MΩ. Set 50 MHz, 800 mV sine, 100 mV/div and 2 ns/div. Display the Time@Level measurement; the absolute value must be ≤100 ps. Repeat for each analog channel.

## Ext Trigger Delay (EXT, 1 kHz, 0.6 V, 2 ns/div, abs(Delay) ≤ 1 ns) [2-channel only]

Use the 9500B with 50 Ω impedance and 50 Ω feedthrough terminators. Select the Zero Skew function on the 9500B. Set 1 kHz, 0.6 V, 100 mV/div, 2 ns/div, trigger source EXT, rising slope and trigger level 0. Display the Delay measurement; the absolute value must be ≤1 ns. Repeat for the other analog channel.

## Ext Trigger Level (EXT 200 mV/div, EXT/5 1 V/div, limited ranges) [2-channel only]

Connect CH1 and EXT to the 9500B with a BNC T connector; use 1 MΩ, 1 kHz, 800 mV sine and 500 µs/div. For EXT at 200 mV/div, the trigger level range is 300-500 mV (positive) or -500 to -300 mV (negative). For EXT/5 at 1 V/div with 4 V amplitude, the range is 1.5-2.5 V or -2.5 to -1.5 V.

## Noise Floor - 2-Channel (Stdev limits, 500 µV/div to 10 V/div) [2-channel only]

Do not connect any signal. Set 1 ms/div and display the Stdev measurement. The Stdev must be within the following limits:

| Volt/Div | Stdev limit | Volt/Div | Stdev limit |
|----------|-------------|----------|-------------|
| 500 µV | ≤250 µV | 100 mV | ≤10 mV |
| 1 mV | ≤0.2 mV | 200 mV | ≤20 mV |
| 2 mV | ≤0.2 mV | 500 mV | ≤50 mV |
| 5 mV | ≤0.5 mV | 1 V | ≤100 mV |
| 10 mV | ≤1 mV | 2 V | ≤200 mV |
| 20 mV | ≤2 mV | 5 V | ≤500 mV |
| 50 mV | ≤5 mV | 10 V | ≤1 V |

## Noise Floor - 4-Channel (pkpk/stdev, SNR limits, 500 µV/div to 10 V/div) [4-channel only]

Do not connect any signal. Set 1 ms/div and display Stdev and Peak-Peak. The pkpk/stdev ratio must be in [0,12]; the SNR must be within the following limits:

| Volt/Div | SNR limit | Volt/Div | SNR limit |
|----------|-----------|----------|-----------|
| 500 µV | [19,55] | 100 mV | [36,55] |
| 1 mV | [25,55] | 200 mV | [36,55] |
| 2 mV | [27,55] | 500 mV | [36,55] |
| 5 mV | [31,55] | 1 V | [36,55] |
| 10 mV | [35,55] | 2 V | [36,55] |
| 20 mV | [36,55] | 5 V | [36,55] |
| 50 mV | [36,55] | 10 V | [36,55] |

## Bandwidth (2 V/div, 200 mV/div, 100 mV/div, frequency points, dB limits) [2+4-channel]

Use 50 Ω impedance and a 50 Ω feedthrough termination. Test at 2 V/div, 200 mV/div and 100 mV/div. Frequency points: 100k, 500k, 1M, 5M, 10M, 50M, 100M, 140M, 180M, 200M, 220M and 250 MHz. Amplitudes: 5.5 V at 2 V/div, 1.2 V at 200 mV/div and 600 mV at 100 mV/div. Limits for SDS1204X-E/SDS1202X-E:

| Frequency | Limit |
|-----------|-------|
| ≤20 MHz | (-1,1) dB |
| ≤100 MHz | (-2,2) dB |
| 100-200 MHz | (-3,2) dB |
| >200 MHz | (-4,2) dB |
| 250 MHz | (-6,2) dB |

## Bandwidth Limit (20 MHz, 12-28 MHz, (-3,2) dB) [2+4-channel]

Enable BW Limit (20 MHz) and repeat the bandwidth test at 2 V/div, 200 mV/div and 100 mV/div. Sweep 100k to 29 MHz. The bandwidth limit passes if at least one frequency in 12-28 MHz has a dB value in (-3,2).

## Trigger Sensitivity (10 MHz and bandwidth, ±1%, 100 mV/div) [2+4-channel]

Set 100 mV/div, 50 ns/div, AC coupling, 50 Ω and 60 mV amplitude at 10 MHz. Adjust the trigger level within the waveform for a stable trigger. The measured frequency must be 9.9-10.1 MHz. Repeat at the bandwidth frequency (±1%); use 2 ns/div for SDS1204X-E/SDS1202X-E. For EXT sensitivity (2-channel only), use 200 mV at 10 MHz and 300 mV at bandwidth; for EXT/5 use 1 V at 10 MHz and 1.5 V at bandwidth.

## Input Impedance (1 MΩ, 0.98-1.02 MΩ DC, 1.176-1.224 MΩ AC at 0.1 V/div, EXT 1 MΩ) [2+4-channel]

Use the 9500B load resistance measurement at 100 mV/div, 200 mV/div and 2 V/div in AC and DC coupling. DC/1 MΩ: 980,000-1,020,000 Ω. AC/1 MΩ at 0.1 V/div: 1,176,000-1,224,000 Ω; at 0.2 V/div and 2 V/div: 980,000-1,020,000 Ω. The EXT input must be 980,000-1,020,000 Ω.

## Disassembly Safety and Tools (power off, ESD, screwdriver, antistatic gloves, hex nut tool) [2+4-channel]

Only qualified personnel should perform disassembly. Disconnect the power before removing or replacing parts. Hazardous voltages exist on the power supply module and LCD module; wait at least three minutes after disconnecting the power cord for the capacitors to discharge. Use ESD precautions. Required tools: multifunction screwdriver, antistatic gloves and a custom screw hexagonal nut tool or long-nose pliers. Reassemble in reverse order.

## 2-Channel Disassembly (knobs, rear cover, metal shield, power supply, front cover, main board, LCD) [2-channel only]

1. Pull off the front-panel knobs.
2. Rear cover: place the oscilloscope face down; remove 2× PM3*10 screws on the rear panel and 2× KM3*6 screws under the tilt legs; lift off the rear cover.
3. Metal shield: remove 2× KM3*6 screws on the side of the rear metal shield; remove the rear shield; remove 2× KM3*6 screws on the top shield; remove the top shield.
4. Power supply/fan: remove 2× M4*8 screws on the power cord connector; disconnect the power and earth cables; remove 4× PWM3*8 screws; remove the power supply module; remove 2× PM3*6 screws on the insulating mat; disconnect the fan; optionally remove 4× KM3*32 screws/nuts and the fan.
5. Front cover: place the oscilloscope back-side down; disconnect the keyboard and LCD cables; remove 6× PC3*8 screws; remove the front cover.
6. Main board: remove 3 BNC nuts/gaskets and 5× PM3*6 screws; remove the main board.
7. LCD/keyboard: disconnect the master/slave keyboard cable; remove 7× PC3*8 screws and the master keyboard; remove 6× PC3*8 screws and the slave keyboard; remove 4 screws/gaskets and the LCD panel with antiglare glass.

## 4-Channel Disassembly (knobs, rear cover, rear metal shield, power supply, front cover, main board, LCD) [4-channel only]

1. Pull off the front-panel knobs.
2. Rear cover: place the oscilloscope face down; remove 4× PM3*6 screws on the rear panel and 2× PM3*6 screws under the tilt legs; lift off the rear cover.
3. Rear metal shield: remove the BNC nut/gasket; remove 7× PM3*6 screws on the side; optionally remove 2× KM3*6 screws on the power connector; lift the shield and disconnect the power and fan cables; remove the shield.
4. Power supply/fan: disconnect the main power cable; optionally remove the PWM3*8 earth cable screw; remove 6× PC3*6 screws on the power supply shield; remove the shield; disconnect the power cable; remove 4× PC3*6 screws; remove the power supply module; optionally remove 4× PM3*32 screws/nuts and the fan.
5. Front cover: disconnect the keyboard and LCD cables; remove 6× PC3*6 screws; remove the front cover.
6. Main board: remove 4 BNC nuts/gaskets and 12× PM3*6 screws; remove the main board.
7. LCD/keyboard: disconnect the master/slave keyboard cable; remove 8× PC3*8 screws and the master keyboard; remove 5× PC3*8 screws and the slave keyboard; remove 4 screws/gaskets and the LCD panel with antiglare glass.

## Service Problem - No Display (power button light, power cord, fuse, power source) [2+4-channel]

If the power button light is not glowing, check that the power cord is secured in the power receptacle, the fuse in the power receptacle is not blown, and the power source is alive. If the light is glowing, go to the service troubleshooting chapter and check the power supply module and main board.

## Service Problem - Display Stuck at Logo (USB flash drive, power cycle, firmware upgrade, SIGLENT) [2+4-channel]

Remove all USB flash drives, power-cycle the oscilloscope and try again. Wait ten minutes to see if it boots successfully; if it does, upgrade to the newest firmware. If it still sticks at the logo, contact SIGLENT.

## Service Problem - No Trace Display (acquisition, trigger status, time/div, default setup, Auto Setup) [2+4-channel]

Check that acquisition is running and the trigger status is Trig'd or Auto. Check that the horizontal time/division is reasonable and the acquisition time is short enough. Disconnect the channel input, recall the default setup, turn the channel on again and press Auto Setup. If there is still no trace, contact SIGLENT.

## Service Problem - Baseline Trace Drift (fan, vertical position, self-calibration) [2+4-channel]

Check that the fan is running and the vertical position setting works. Perform Self Calibration. If the drift persists, contact SIGLENT.

## Service Problem - Unexpected Trace Without Input (power cycle, firmware upgrade) [2+4-channel]

Power-cycle the oscilloscope and upgrade to the newest firmware. If the unexpected trace persists, contact SIGLENT.

## Service Troubleshooting Equipment (digital multimeter, ±0.05%, 1 mV, 200 MHz oscilloscope) [2+4-channel]

Required equipment: a digital multimeter with ±0.05% accuracy and 1 mV resolution (e.g. SIGLENT SDM3065X or Agilent 34401A) and a 200 MHz oscilloscope with 1 MΩ input impedance (e.g. SIGLENT SDS1204X-E).

## Service Troubleshooting Flowchart (power supply, main board, LCD) [2+4-channel]

Test the power supply module first; if it is good, test the main board; if the main board is good, test the LCD. Replace the power supply module, main board or LCD respectively when a test fails.

## 2-Channel Power Supply Voltages (pin 1-12, +6.5V, +3.4V, +15V, -10V, AC line 2Vpp) [2-channel only]

Measure the power cable plug with a multimeter:

| Definition | Pin | Tolerance |
|------------|-----|-----------|
| GND | Pin 1, 5, 8, 12 | - |
| Primary Power | Pin 3, 4 | +6.5 VDC ±10% |
| Positive Auxiliary Power 1 | Pin 6, 7 | +3.4 VDC ±100 mV |
| Positive Auxiliary Power 2 | Pin 2 | +15 VDC ±10% |
| Negative Auxiliary Power | Pin 9 | -10 VDC ±10% |
| AC Line Trigger | Pin 10 | 2 Vpp ±20% |
| Reserved | Pin 11 | not used |

## 2-Channel Processor Voltages and Clocks (DVCC rails, 33.333 MHz, 24 MHz, 25 MHz) [2-channel only]

Processor power supplies:

| Net | Test Point | Tolerance |
|-----|------------|-----------|
| DVCC1V0_ZYNQ | C18/C23 | +1.0 VDC ±50 mV |
| DVCC1V8_ZYNQ | TP46 | +1.8 VDC ±50 mV |
| DVCC1V5_ZYNQ | TP47 | +1.5 VDC ±50 mV |
| DVCC3V3_ZYNQ | TP78 | +3.3 VDC ±100 mV |
| DVCC2V5_ZYNQ | TP79 | +2.5 VDC ±100 mV |

Clocks (LVCMOS33): R334 33.333333 MHz ±50 ppm (processor reference); R372 24.000000 MHz ±50 ppm (USB Host); R371 24.000000 MHz ±50 ppm (USB Device); R205 25.000000 MHz ±50 ppm (Ethernet); R229 25.000000 MHz ±25 ppm (acquisition system); R89 25.000000 MHz ±25 ppm (PLL reference).

## 2-Channel Acquisition Voltages and Clocks (AVCC1V9, AVCC3V3, AVCC5V0, AVEE-5V0, 25 MHz) [2-channel only]

| Net | Test Point | Tolerance |
|-----|------------|-----------|
| AVCC1V9_ADC | TP70 | +1.9 VDC ±50 mV |
| AVCC3V3 | TP76 | +3.3 VDC ±100 mV |
| AVCC5V0_VGA | TP80 | +5.0 VDC ±100 mV |
| AVCC5V0 | TP75 | +5.0 VDC ±100 mV |
| AVEE-5V0 | TP72 | -5.0 VDC ±200 mV |

Clocks (LVCMOS33): R229 25.000000 MHz ±25 ppm (acquisition system); R89 25.000000 MHz ±25 ppm (PLL reference).

## 2-Channel Other Power Supplies (VCC5V0, VCC6V5, FAN_PWR, VCC15V0, AVEE-10V0) [2-channel only]

| Net | Test Point | Tolerance | Comment |
|-----|------------|-----------|---------|
| VCC5V0 | TP77 | +5 VDC ±100 mV | Standby and USB host VBUS |
| VCC6V5 | L63 | +6.5 VDC ±10% | Main power |
| FAN_PWR | J12 | -10 VDC ±10% | Fan supply |
| VCC15V0 | Q33 | +15 VDC ±10% | TDC circuits |
| AVEE-10V0 | Q34 | -10 VDC ±10% | Analog circuits |

## 2-Channel LCD Power and Signals (VCC10V4, VCC16V, VEE-6V8, VLEDP, DCLK 27.5 MHz, VSYNC 50 Hz, HSYNC 26 kHz) [2-channel only]

| Net | Test Point | Tolerance |
|-----|------------|-----------|
| VCC10V4_LCD | C134 | +10.4 VDC ±10% |
| VCC16V_LCD | D12 | +16 VDC ±10% |
| VEE-6V8_LCD | D13 | -6.8 VDC ±10% |
| VLEDP_LCD | ZC16 | +6.5 V to +20 V |

LCD signals (LVCMOS33): R420 LCD_DCLK 27.5 MHz ±1%; R422 LCD_VSYNC 50 Hz ±1%; R423 LCD_HSYNC 26 kHz ±1%. If the power is abnormal, replace the main board; if the signal is good but the display is not, replace the LCD panel.

## 4-Channel Power Supply Voltages (pin 1-8, +6.5V, +15V, -9.5V, AC line 2Vpp) [4-channel only]

| Definition | Pin | Cable Color | Tolerance |
|------------|-----|-------------|-----------|
| GND | Pin 4, 5, 6 | Black | - |
| Primary Power | Pin 1, 2 | Red | +6.5 VDC ±10% |
| Positive Auxiliary Power | Pin 8 | Blue | +15 VDC ±10% |
| AC Line Trigger | Pin 7 | Brown | 2 Vpp ±20% |
| Negative Auxiliary Power | Pin 3 | Orange | -9.5 VDC ±10% |

## 4-Channel Processor Voltages and Clocks (DVCC rails, 33.333 MHz, 24 MHz, 25 MHz) [4-channel only]

| Net | Test Point | Tolerance |
|-----|------------|-----------|
| DVCC1V0_ZYNQ | TP4 | +1.0 VDC ±50 mV |
| DVCC1V8_ZYNQ | TP5 | +1.8 VDC ±50 mV |
| DVCC1V5_ZYNQ | TP6 | +1.5 VDC ±50 mV |
| DVCC3V3_ZYNQ | TP7 | +3.3 VDC ±100 mV |
| DVCC2V5_ZYNQ | TP23 | +2.5 VDC ±100 mV |

Clocks (LVCMOS33): R203 33.333333 MHz ±50 ppm; R204 24.000000 MHz ±50 ppm (USB Host); R205 24.000000 MHz ±50 ppm (USB Device); R206 24.000000 MHz ±50 ppm (USB Hub); R207 25.000000 MHz ±50 ppm (Ethernet); R208 25.000000 MHz ±25 ppm (acquisition); R209 25.000000 MHz ±25 ppm (PLL).

## 4-Channel Acquisition Voltages and Clocks (VCC1V8_ADC0/1, AVCC3V3, AVCC5V0, AVEE-5V0, 25 MHz) [4-channel only]

| Net | Test Point | Tolerance |
|-----|------------|-----------|
| VCC1V8_ADC0 | TP18 | +1.8 VDC ±50 mV |
| VCC1V8_ADC1 | TP19 | +1.8 VDC ±50 mV |
| AVCC3V3 | TP15 | +3.3 VDC ±100 mV |
| AVCC5V0_VGA | TP13 | +5.0 VDC ±100 mV |
| AVCC5V0 | TP12 | +5.0 VDC ±100 mV |
| AVEE-5V0 | TP17 | -5.0 VDC ±200 mV |

Clocks (LVCMOS33): R208 25.000000 MHz ±25 ppm (acquisition); R209 25.000000 MHz ±25 ppm (PLL).

## 4-Channel Other Power Supplies (VCC3V3_PWR, VCC6V5, FAN_PWR, VEE-6V5, DVCC5V0_USB, VCC6V5_MSO) [4-channel only]

| Net | Test Point | Tolerance | Comment |
|-----|------------|-----------|---------|
| VCC3V3_PWR | TP22 | +3.3 VDC ±100 mV | Standby |
| VCC6V5 | TP25 | +6.5 VDC ±10% | Main power |
| FAN_PWR | J18 | +12 VDC ±1 V | Fan |
| VEE-6V5 | TP21 | -6.5 VDC ±10% | Analog circuits |
| DVCC5V0_USB | TP12 | +5.0 VDC ±100 mV | USB host VBUS |
| VCC6V5_MSO | TP14 | +6.5 VDC ±10% | SBUS, near 0 V without device |

## 4-Channel LCD Power and Signals (VCC10V4, VCC16V, VEE-6V8, VLEDP, DCLK 27.5 MHz, VSYNC 50 Hz, HSYNC 26 kHz) [4-channel only]

| Net | Test Point | Tolerance |
|-----|------------|-----------|
| VCC10V4_LCD | TP11 | +10.4 VDC ±10% |
| VCC16V_LCD | TP10 | +16 VDC ±10% |
| VEE-6V8_LCD | TP8 | -6.8 VDC ±10% |
| VLEDP_LCD | TP9 | +6.5 V to +20 V |

LCD signals (LVCMOS33): R420 LCD_DCLK 27.5 MHz ±1%; R422 LCD_VSYNC 50 Hz ±1%; R423 LCD_HSYNC 26 kHz ±1%. If the power is abnormal, replace the main board; if the signal is good but the display is not, replace the LCD panel.

## 1. The screen is still dark (no display) after power on (power connection, fuse, power switch) [2+4-channel]

- 1) Check whether the power is correctly connected.
- 2) Check whether the power switch is really on.
- 3) Check whether the fuse is burned out. If the fuse needs to be changed, please use the specified fuse.
- 4) Restart the instrument after finishing the above inspections.
- 5) If it still does not work correctly, please contact SIGLENT.

## 2. The signal is sampled but no waveform is displayed (probe, BNC connector, signal source, resample) [2+4-channel]

- 1) Check whether the probe is correctly connected to the signal connecting wire.
- 2) Check whether the signal connecting wire is correctly connected to the BNC (namely channel connector).
- 3) Check whether the probe is correctly connected to the item to be tested.
- 4) Check whether there are signals generated from the item to be tested (you can connect the probe compensation signal to the problematic channel to determine which has problem, the channel or the item to be tested).
- 5) Resample the signal.

## 3. The tested voltage amplitude is greater or lower than the actual value (probe attenuation, attenuation ratio) [2+4-channel]

Check whether the attenuation coefficient of the channel complies with the attenuation ratio of the probe.

## 4. There is waveform display but not stable (trigger source, trigger type, holdoff) [2+4-channel]

- 1) Check the trigger signal source: check whether the Source item at the trigger panel complies with the signal channel actually used.
- 2) Check the trigger type: general signals should use "Edge" trigger and video signal should use "Video" trigger. Only when the proper trigger type is used, can the waveform be displayed stably.
- 3) Change the trigger holdoff setting.

## 5. No display after pressing Run/Stop (trigger mode Normal, Single, trigger level) [2+4-channel]

Check whether the mode at the trigger panel (TRIGGER) is on “Normal” or
"Single" and whether the trigger level exceeds the waveform range. If yes, set the trigger level to the middle or set the mode to "Auto".
Note: using AUTO could automatically finish the above setting.

## 6. The display of waveform is ladder-like (horizontal time base, Vectors, Dots) [2+4-channel]

- 1) The horizontal time base might be too low. Increase the horizontal time base to increase the horizontal resolution and improve the display.
- 2) If the display Type is "Vectors", the lines between the sample points may cause ladder -like display. Set Type to "Dots" to solve the problem.

## 7. Fail to connect PC through USB (IO Setting, USB Device) [2+4-channel]

Check the IO Setting in Utility to make sure whether the setting in USB Device matches the device currently connected. If needed, restart the oscilloscope.

## 8. The USB storage device cannot be recognized (flash storage, USB interface) [2+4-channel]

- 1) Check whether the USB storage device can work normally.
- 2) Make sure whether the USB interface can work normally.
- 3) Make sure that the USB storage device being used is flash storage type. This oscilloscope does not support hardware storage type.
- 4) Restart the instrument and then insert the USB storage device to check it.
- 5) If the USB storage device still cannot be used normally, please contact SIGLENT.

## Digital Oscilloscopes Series (SDS1000CML, SDS1000DL, SDS1000CNL, SDS1000X, SDS2000, SPO) [2+4-channel]

| Applicable to the following models |
|------------------------------------------|
| SDS1000CML/CML+ |
| SDS1000DL/DL+ |
| SDS1000CNL/CNL+ |
| SDS1000/1000X/1000X - S/1000X+/1000X - E |
| SDS2000/SDS2000X |

Certain commands are only applicable to SPO oscilloscopes models and are described accordingly.

SPO oscilloscopes models are in the table below.

| SPO models |
|------------------------------|
| SDS1000X/1000X+/SDS1000X-E |
| SDS2000/2000X |

## What is an SPO model? (Super Phosphor Oscilloscope, high capture rate, intensity grading, color temperature, deep memory) [2+4-channel]

SPO model uses Siglent-innovated waveform acquisition and graphics processing engine which supports high capture rate, multilevel intensity grading and color temperature display, with deep memory storage and the use of new digital trigger technology supports rich trigger types and precise trigger. All of these technologies are collectively known as SPO (Super Phosphor Oscilloscope) technology.

## SCPI Command Syntax (colon, braces, square brackets, ellipsis, placeholder) [2+4-channel]

- : = A colon followed by an equals sign separates a placeholder from the description of the type and range of values that may be used in a command instead of the placeholder.
- {} Braces enclose a list of choices, one of which one must be made.
- [ ] Square brackets enclose optional items.
- … An ellipsis indicates that the items both to its left and right may be repeated a number of times.

As an example, consider the syntax notation for the command to set the vertical input sensitivity:

```
<channel>:VOLT_DIV <v_gain> <channel> : = {C1, C2, C3, C4} <v_gain>: = 2 mV to 10 V
```

The first line shows the formal appearance of the command, with &lt;channel&gt; denoting the placeholder for the header path and &lt;v\_gain&gt; the placeholder for the data parameter specifying the desired vertical gain value. The second line indicates that one of four channels must be chosen for the header path. And the third explains that the actual vertical gain can be set to any value between 2 mV and 10 V.

Always use the command short form, e.g. for a query ‚ C1:WFV,DAT2 ' instead of ‚ C1:WAVEFORM '. For Channel 1 and Channel 2 always use C1 and C2.

## SCPI Commands & Queries (short form, long form, subsystem, ACQW, ALST, ARM, ATTN, BWL, CPL, TDIV, TRSE, WF) [2+4-channel]

| Short Form | Long Form | Subsystem | What the Command or Query Does |
|--------------|-----------------|---------------|-------------------------------------------------------------|
| ACQW | ACQUIRE_WAY | ACQUISITION | Specifies the acquisition mode. |
| ALST? | ALL_STATUS? | STATUS | Reads and clears the contents of all status registers. |
| ARM | ARM_ACQUISITION | ACQUISITION | Changes acquisition state from ―stopped‖ to ―single‖. |
| ATTN | ATTENUATION | ACQUISITION | Selects the vertical attenuation factor of the probe |
| ACAL | AUTO_CALIBRATE | MISCELLANEOUS | Enables or disables automatic calibration. |
| ASET | AUTO_SETUP | ACQUISITION | Adjusts vertical, time base and trigger parameters. |
| AUTTS | AUTO_TYPESET | ACQUISITION | Selects the display type of automatic setup. |
| AVGA | AVERAGE_ACQUIRE | ACQUISITION | Selects the average times of average acquisition. |
| BWL | BANDWIDTH_LIMIT | ACQUISITION | Enables/disables the bandwidth-limiting lowpass filter. |
| BUZZ | BUZZER | MISCELLANEOUS | Controls the built-in piezo electric buzzer. |
| *CAL? | *CAL? | MISCELLANEOUS | Performs complete internal calibration of the instrument. |
| CHDR | COMM_HEADER | COMMUNICATION | Controls formatting of query responses. |
| *CLS | *CLS | STATUS | Clears all status data registers. |
| CMR? | CMR? | STATUS | Reads and clears the Command error Register (CMR). |
| CONET | COMM_NET | COMMUNICATION | Specifies network addresses of scope and printers. |
| CPL | COUPLING | ACQUISITION | Selects the specified input channel‘s coupling mode. |
| CRMS | CURSOR_MEASURE | CURSOR | Specifies the type of cursor/parameter measurement. |
| CRST | CURSOR_SET? | CURSOR | Allows positioning of any one of eight cursors. |
| CRVA? | CURSOR_VALUE? | CURSOR | Returns trace values measured by specified cursors. |
| CSVS | CSV_SAVE | SAVE/RECALL | Saves specified waveform data of CSV format to USB device. |
| CYMT | CYMOMETER | FUNCTION | Returns the current cymometer value which displaying on the screen. |
| DATE | DATE | MISCELLANEOUS | Changes the date/time of the internal real-time clock. |
| DDR? | DDR? | STATUS | Clears the Device Dependent Register (DDR). |
| DEF | DEFINE? | FUNCTION | Specifies math expression for function evaluation. |
| DELF | DELETE_FILE | MASS STORAGE | Deletes files from mass storage. |
| DIR | DIRECTORY | MASS STORAGE | Creates and deletes file directories. |
| DTJN | DOT_JOIN | DISPLAY | Controls the interpolation lines between data points. |
| *ESE | *ESE | STATUS | Sets the Standard Event Status Enable register (ESE). |
| *ESR? | *ESR? | STATUS | Reads, clears the Event Status Register (ESR). |
| EXR? | EXR? | STATUS | Reads, clears the Execution error Register (EXR). |
| FLNM | FILENAME | MASS STORAGE | Changes default filenames. |
| FPAR | FRAME_PARAM | HISTORY | Get frame param. |
| FRAM | FRAME_SET | HISTORY | History Frame No. set. |
| FRTR | FORCE_TRIGGER | ACQUISITION | Forces the instrument to make one acquisition. |
| FTIM | FRAME_TIME | HISTORY | Get frame Acq. Time. |
| FVDISK | FORMAT_VDISK | MASS STORAGE | Reads the capability of the USB device. |
| FILT | FILTER | FUNCTION | Enables or disables the filter of specified source. |
| FILTS | FILT_SET | FUNCTION | Selects the type of filter, and sets the limit value of filter. |
| FFTW | FFT_WINDOW | FUNCTION | Selects the window of FFT. |
| FFTZ | FFT_ZOOM | FUNCTION | Selects the zoom in/out times of FFT trace. |
| FFTS | FFT_SCALE | FUNCTION | Selects the vertical scale of FFT trace. |
| FFTF | FFT_FULLSCREEN | FUNCTION | Enables or disables to display the FFT trace full screen. |
| GRDS | GRID_DISPLAY | DISPLAY | Selects the type of grid |
| GCSV | GET_CSV | WAVEFORMTRANS | Specifies waveform data of format to controller. |
| HMAG | HOR_MAGNIFY | DISPLAY | Horizontally expands the selected expansion trace. |
| HPOS | HOR_POSITION | DISPLAY | Horizontally positions intensified zone‘s center. |
| HCSU | HARDCOPY_SETUP | HARD COPY | Configures the hard-copy driver. |
| *IDN? | *IDN? | MISCELLANEOUS | For identification purposes. |
| ILVD | INTERLEAVED | ACQUISITION | Reads, clears INternal state change Register (INR). |
| INTS | INTENSITY | DISPLAY | Sets the grid or trace/text intensity level. |
| INR? | INR? | STATUS | Reads, clears INternal state change Register (INR). |
| INVS | INVERT_SET | DISPLAY | Invert the trace or the math waveform of specified source. |
| LOCK | LOCK | MISCELLANEOUS | Lock keyboard |
| MTVP | MATH_VERT_POS | ACQUISITION | Controls the vertical position of math waveform of specified source. |
| MTVD | MATH_VERT_DIV | ACQUISITION | Controls the vertical sensitivity of math waveform of specified source. |
| MEAD | MEASURE_DELY | ACQUISITION | Controls the vertical sensitivity of math waveform of specified source. |
| MENU | MENU | DISPLAY | Enables or disables to display the current menu. |
| MSIZ | MEMORY_SIZE | FUNCTION | Returns the maximal memory size |
| OFST | OFFSET | ACQUISITION | Allows output channel vertical offset adjustment. |
| *OPC | *OPC | STATUS | Sets the OPC bit in the Event Status Register (ESR). |
| *OPT? | *OPT? | MISCELLANEOUS | Identifies oscilloscope options. |
| PACL | PARAMETER_CLR | CURSOR | Clears all current parameters in Custom, Pass/Fail. |
| PACU | PARAMETER_CUSTO M | CURSOR | Controls parameters with customizable qualifiers. |
| PAVA? | PARAMETER_VALU E? | CURSOR | Returns current parameter, mask test values. |
| PDET | PEAK_DETECT | ACQUISITION | Switches the peak detector ON and OFF. |
| PERS | PERSIST | DISPLAY | Enables or disables the persistence display mode. |
| PESU | PERSIST_SETUP | DISPLAY | Selects display persistence duration. |
| PNSU | PANEL_SETUP | SAVE/RECALL | Complements the *SAV/*RST commands. |
| PFDS | PF_DISPLAY | FUNCTION | Enables or disables to display the test and the message options of pass/fail. |
| PFST | PF_SET | FUNCTION | Sets the X mask and the Y mask. |
| PFSL | PF_SAVELOAD | SAVE/RECALL | Saves or recalls the created mask setting. |
| PFCT | PF_CONTROL | FUNCTION | Selects the ―operate‖, ―output‖ and the ―stop on output‖ which are the options of pass/fail. |
| PFCM | PF_CREATEM | FUNCTION | Creates the mask of the pass/fail. |
| PFDD | PF_DATEDIS | FUNCTION | Return the number of the pass/fail monitor which can be displayed on the screen. |
| *RCL | *RCL | SAVE/RECALL | Recalls one of five nonvolatile panel setups. |
| RCPN | RECALL_PANEL | SAVE/RECALL | Recalls a front-panel setup from mass storage. |
| REC | RECALL | SAVE/RECALL | Recalls a waveform file from mass storage. |
| *RST | *RST | SAVE/RECALL | The *RST command initiates a device reset. |
| REFS | REF_SET | FUNCTION | Sets the reference waveform and its options. |
| *SAV | *SAV | SAVE/RECALL | Stores current state in nonvolatile internal memory. |
| SCDP | SCREEN_DUMP | HARD COPY | Causes a screen dump to controller. |
| SCSV | SCREEN_SAVE | DISPLAY | Controls the automatic screen saver. |
| *SRE | *SRE | STATUS | Sets the Service Request Enable register (SRE). |
| *STB? | *STB? | STATUS | Reads the contents of IEEE 488. |
| STOP | STOP | ACQUISITION | Immediately stops signal acquisition. |
| STO | STORE | WAVEFORM TRANSFER | Stores a trace in internal memory or mass storage. |
| STPN | STORE_PANEL | SAVE/RECALL | Stores front-panel setup to mass storage. |
| STST | STORE_SETUP | WAVEFORM TRANSFER | Controls the way in which traces are stored. |
| SAST | SAMPLE_STATUS | ACQUISITION | Return the acquisition status of the scope |
| SARA | SAMPLE_RATE | ACQUISITION | Return the sample rate of the scope |
| SANU | SAMPLE_NUM | ACQUISITION | Return the number of sampled points available from last acquisition and the trigger position |
| SET50 | SETTO%50 | FUNCTION | Sets the trigger level of the trigger source to the centre of the signal amplitude. |
| SKEW | SKEW | ACQUISITION | Sets the skew of specified trace. |
| SXSA | SINXX_SAMPLE | ACQUISITION | Sets the type of the interpolation. |
| TDIV | TIME_DIV | ACQUISITION | Modifies the time base setting. |
| TMPL | TEMPLATE | WAVEFORM | Produces a complete |
|  |  | TRANSFER | waveform template copy. |
| TRA | TRACE | DISPLAY | Enables or disables the display of a trace. |
| *TRG | *TRG | ACQUISITION | Executes an ARM command. |
| TRCP | TRIG_COUPLING | ACQUISITION | Sets the coupling mode of the specified trigger source. |
| TRDL | TRIG_DELAY | ACQUISITION | Sets the time at which the trigger is to occur. |
| TRLV | TRIG_LEVEL | ACQUISITION | Adjusts the trigger level of the specified trigger source. |
| TRLV2 | TRIG_LEVEL2 | ACQUISITION | Adjusts the second trigger level of the specified trigger source. |
| TRMD | TRIG_MODE | ACQUISITION | The trigger mode. |
| TRSE | TRIG_SELECT | ACQUISITION | Selects the condition that will trigger acquisition. |
| TRSL | TRIG_SLOPE | ACQUISITION | Sets the trigger slope of the specified trigger source. |
| TRWI | TRIG_WINDOW | ACQUISITION | Return relative height of the trigger window |
| TRPA | TRIG_PATTERN | ACQUISITION | Sets the condition of the pattern trigger |
| UNIT | UNIT | ACQUISITION | Sets the unit of specified trace. |
| VPOS | VERT_POSITION | DISPLAY | Adjusts the vertical position of the FFT trace. |
| VDIV | VOLT_DIV | ACQUISITION | Sets the vertical sensitivity. |
| VTCL | VERTICAL | ACQUISITION | Controls the vertical position of the slope trigger line. |
| WF | WAVEFORM | WAVEFORMTRANS | Gets the waveform from the instrument. |

## SCPI Command Reference (introduction, command syntax, alphabetical command list) [2+4-channel]

This section contains detailed descriptions of all SCPI remote control commands supported by SIGLENT SDS1000X-E series digital oscilloscopes.

The commands are listed alphabetically by their short form. Each entry includes the command syntax, query syntax (where applicable), and a description of the command's function.

## ACAL, AUTO_CALIBRATE, Auto Calibrate, Quick Calibration, Self-Calibration [2+4-channel]

The AUTO_CALIBRATE command is used to enable or disable the quick calibration of the instrument. The quick calibration can be disabled by sending the command "ACAL OFF". The *CAL? query can be used to fully calibrate the oscilloscope. The AUTO_CALIBRATE? query returns whether quick-calibration is enabled.

Command Syntax: `ACAL <state> <state>:={ON, OFF}`

Query Syntax: `ACAL?`

## ACQ:CSW, ACQuire:CSWeep, Acquire, Clear Sweeps, Reset Acquisition [4-channel only]

The ACQuire:CSWeep command resets the acquisition, which is equivalent to the Clear Sweeps button on the front panel.

Command Syntax: `ACQ:CSW`

## ACQW, ACQUIRE_WAY, Acquisition Mode, Sampling, Peak Detect, Average, High Res [2+4-channel]

The ACQUIRE_WAY command specifies the acquisition mode. The ACQUIRE_WAY? query returns the current acquisition mode.

Command Syntax: `ACQW <mode>[,<time>] <mode>:= {SAMPLING,PEAK_DETECT,AVERAGE,HIGH_RES} <time>:= {4,16,32,64,128,256,512,…}`

Query Syntax: `ACQW?`

Response Format: `ACQW <mode>[,<time>]`

## ALST?, ALL_STATUS?, Status Registers, STB, ESR, INR, DDR, CMR, EXR, URR, All Status [2+4-channel]

The ALL_STATUS? Query reads and clears the contents of all status registers: STB, ESR, INR, DDR, CMR, EXR and URR except for the MAV bit (bit 6) of the STB register. For an interpretation of the contents of each register, refer to the appropriate status register. The ALL_STATUS? Query is useful in a complete overview of the state of the instrument.

Query Syntax: `ALST?`

## ARM, ARM_ACQUISITION, Arm Acquisition, Single Trigger, Trigger Mode [2+4-channel]

The ARM_ACQUISITION command starts a new signal acquisition.

Command Syntax: `ARM`

## ARWV, ARbWaVe, Waveform Generator, Arbitrary Wave, Index Name [4-channel only]

This command sets or gets the basic wave parameters.

Command Syntax: `<channel>:ARWV INDEX,<index> <channel>:ARbWaVe NAME,<name> <channel>:={C1}, SAG1021I only supports one output channel.`

Query Syntax: `<channel>:ARWV? <channel>:= {C1}`

Response Format: `<channel>:ARWV INDEX,<index>,NAME,<name>`

## ASET, AUTO_SETUP, Auto Setup, Automatic Adjustment, Waveform Detection [2+4-channel]

The AUTO_SETUP command attempts to identify the waveform type and automatically adjusts controls to produce a usable display of the input signal.

Command Syntax: `ASET`

## ATTN, ATTENUATION, Probe Attenuation, Vertical Scale, Attenuation Factor [2+4-channel]

The ATTENUATION command specifies the probe attenuation factor for the selected channel. The probe attenuation factor may be 0.1 to 10000.This command does not change the actual input sensitivity of the oscilloscope. It changes the reference constants for scaling the display factors, for making automatic measurements, and for setting trigger levels. The ATTENUATION? query returns the current probe attenuation factor for the selected channel.

Command Syntax: `<channel>:ATTN <attenuation> <channel>:= {C1,C2,C3,C4} <attenuation>:= {0.1,0.2,0.5,1,2,5,10,20,50,100,200,500,1000,2000,5000, 10000}`

Query Syntax: `<channel>:ATTN?`

Response Format: `<channel>:ATTN <attenuation>`

## AUTTS, AUTO_TYPESET, Auto Typeset, Display Type, SP, MP, RS, DRP, RC [2+4-channel]

The AUTO_TYPESET command selects the specified type of automatically adjusting which is used to display.

Command Syntax: `AUTTS <type> <type>:={SP,MP,RS,DRP,RC}`

Query Syntax: `AUTTS?`

Response Format: `AUTTS <type>`

## AVGA, AVERAGE_ACQUIRE, Average Acquire, Acquisition Average, Number of Averages [2+4-channel]

The AVERAGE_ACQUIRE command selects the average times of average acquisition. The AVERAGE_ACQUIRE? query returns the currently selected count value for average mode.

Command Syntax: `AVGA <time> <time>:= {4,16,32,64,128,256,…}`

Query Syntax: `AVGA?`

Response Format: `AVGA <time>`

## B<n>:DCCN, Decode, CAN Decode, ID Data, CRC ACK [2+4-channel]

The B<n>:DCCN command is used to set the parameters of CAN decode bus.

Command Syntax: `B<n>:DCCN <param>,<value>[,<param>,<value>[..]]`

## B<n>:DCIC, Decode, I2C Decode, SCL SDA, Address Data [2+4-channel]

The B<n>:DCIC command is used to set the parameters of IIC decode bus.

Command Syntax: `B<n>:DCIC <param>,<value>[,<param>,<value>[,..]]`

## B<n>:DCLN, Decode, LIN Decode, Break ID, Checksum [2+4-channel]

The B<n>:DCLN command is used to set the parameters of LIN decode bus.

Command Syntax: `B<n>:DCLN <param>,<value>[,<param>,<value>[,..]]`

## B<n>:DCSP, Decode, SPI Decode, CLK MISO MOSI CS [2+4-channel]

The B<n>:DCSP command is used to set the parameters of SPI decode bus.

Command Syntax: `B<n>:DCSP <param>,<value>[,<param>,<value>[,..]]`

## B<n>:DCUT, Decode, UART Decode, RX TX, Baud Parity [2+4-channel]

The B<n>:DCUT command is used to set the parameters of UART decode bus.

Command Syntax: `B<n>:DCUT <param>,<value>[,<param>,<value>[,..]]`

## BSWV, BaSic_WaVe, Waveform Generator, Basic Wave, Frequency Amplitude [4-channel only]

This command sets or gets the basic wave parameters.

Command Syntax: `<channel>:BSWV <parameter>,<value> <channel>:={C1}, SAG1021I only support one output channel.`

Query Syntax: `<channel>:BSWV? <channel>:= {C1}`

Response Format: `<channel>:BSWV <parameter>`

## BUZZ, BUZZER, Buzzer, Sound, Keypress Feedback, Audio [2+4-channel]

The BUZZER command enables or disables the buzzer. The BUZZER? query returns the switch state of the buzzer.

Command Syntax: `BUZZ <state> <state>:= {ON,OFF}`

Query Syntax: `BUZZ?`

Response Format: `BUZZ <state>`

## BWL, BANDWIDTH_LIMIT, Bandwidth Limit, 20 MHz Filter, Low-Pass Filter [2+4-channel]

BANDWIDTH_LIMIT enables or disables the bandwidth- limiting low-pass filter. If the bandwidth filters are on, it will limit the bandwidth to reduce display noise. When you turn Bandwidth Limit ON, the Bandwidth Limit value is set to 20 MHz. It also filters the signal to reduce noise and other unwanted high frequency components. The BANDWIDTH_LIMIT? query returns whether the bandwidth filters are on.

Command Syntax: `BWL <channel>,<mode>[,<channel>,<mode>[,<channel>,<mode>[, <channel>,<mode>]]] <channel>:={C1,C2,C3,C4} <mode>:={ON,OFF}`

Query Syntax: `BWL?`

Response Format: `BWL <channel>,<mode>[,<channel>,<mode>[,<channel>,<mode>[,<channel>,<mode>]]]`

## *CAL?, *CAL?, Self Calibration, Internal Calibration, Diagnostics [2+4-channel]

The *CAL? query causes the oscilloscope to perform an internal self-calibration and generates a response.

Query Syntax: `*CAL? Digital Oscilloscopes Series`

## CHDR, COMM_HEADER, Command Header, Response Format, LONG, SHORT, OFF [2+4-channel]

The COMM_HEADER command controls the way the oscilloscope formats response to queries. This command does not affect the interpretation of messages sent to the oscilloscope. Headers can be sent in their long or short form regardless of the CHDR setting. Examples of the three response formats to “C1:VDIV?”: CHDR RESPONSE LONG C1:VOLT_DIV 1.00E+01V SHORT C1:VDIV 1.00E+01V OFF 1.00E+01

Command Syntax: `CHDR <mode> <mode>:= {SHORT,LONG,OFF}`

Query Syntax: `CHDR?`

Response Format: `CHDR <mode>`

## *CLS, *CLS, Clear Status, Status Registers, Reset Status [2+4-channel]

The *CLS command clears all the status data registers.

Command Syntax: `*CLS`

## CMR?, CMR?, Command Error Register, Syntax Error, CMR [2+4-channel]

The CMR? Query reads and clears the contents of the Command error Register (CMR) see table next page---which specifies the last syntax error type detected by the instrument.

## CONET, COMM_NET, Network Configuration, IP Address, TCP/IP [2+4-channel]

The COMM_NET command sets the IP address of the oscilloscope’s internal network interface. When using this command, DHCP should be off. The COMM_NET? query returns the IP address of the oscilloscope’s internal network interface.

Command Syntax: `CONET <ip_add0>,<ip_add1>,<ip_add2>,<ip_add3> <ip_add0>:= 1 to 223(except 127). <ip_add1>:= 0 to 255. <ip_add2>:= 0 to 255. <ip_add3>:= 0 to 255.`

Query Syntax: `CONET?`

Response Format: `CONET <ip_add0>,<ip_add1>,<ip_add2>,<ip_add3>`

## COUNTER, COUNTER, Cymometer, Frequency Counter, Counter Display [4-channel only]

The COUNTER command enables or disables the cymometer display on the screen of instrument. The response to the COUNTER? query indicates whether the cymometer is displayed on the screen of instrument.

Command Syntax: `COUNTER <state> < state > : = {ON, OFF}`

Query Syntax: `COUNTER?`

## CPL, COUPLING, Coupling, AC, DC, GND, Channel Input, A1M, A50, D1M, D50 [2+4-channel]

The COUPLING command selects the coupling mode of the specified input channel. The COUPLING? query returns the coupling mode of the specified channel.

Command Syntax: `<channel>:CPL <coupling> <channel>:= {C1,C2,C3,C4} <coupling>:= {A1M,A50,D1M,D50,GND}`

Query Syntax: `<channel>:CPL?`

Response Format: `<channel>:CPL <coupling>`

## CRAU, CURSOR_AUTO, Cursor Auto, Auto Cursor Mode, Automatic Cursors [2+4-channel]

The CURSOR_AUTO command sets the cursor mode to Auto.

Command Syntax: `CRAU`

## CRMS, CURSOR_MEASURE, Cursor Measure, Parameter Measurement, HREL, VREL, AUTO [2+4-channel]

The CURSOR_MEASURE command specifies the type of cursor or parameter measurement to be displayed The CURSOR_MEASURE? query returns which cursors or parameter measurements are currently displayed.

Command Syntax: `CRMS <mode> Format 1: <mode>:={OFF,ON}`

Query Syntax: `CRMS?`

Response Format: `CRMS <mode>`

## CRST, CURSOR_SET?, Cursor Set, Cursor Position, VREF, VDIF, TREF, TDIF [2+4-channel]

The CURSOR_SET command allows the user to position any one of the four independent cursors at a given screen location. The positions of the cursors can be modified or queried even if the required cursor is not currently displayed on the screen. When setting a cursor position, a trace must be specified, relative to which the cursor will be positioned. The CURSOR_SET? query returns the current position of the cursor(s). The values returned depend on the grid type selected.

Command Syntax: `<trace>:CRST <cursor>,<position>[,<cursor>,<position>[,<cursor>,< position>[,<cursor>,<position>]]] <trace>:={C1,C2,C3,C4} <cursor>:={VREF,VDIF,TREF,TDIF,HRDF,HDIF}`

Query Syntax: `<trace>:CRST? <cursor>[,<cursor>[,<cursor>[,<cursor>]]] <cursor>:= {VREF,VDIF,TREF,TDIF,HREF,HDIF}`

Response Format: `<trace>:CRST <cursor>,<position>[,<cursor>,<position>[,<cursor>,< position>[,<cursor>,<position>]]]`

## CRTY, CURSOR_TYPE, Cursor, Cursor Type, X Cursors, Y Cursors [2+4-channel]

The CURSOR_TYPE command specifies the type of cursor to be displayed when the cursor mode is manual. The CURSOR_TYPE query returns the current type of cursor.

Command Syntax: `CRTY <type> <mode>:={X,Y,X-Y}`

Query Syntax: `CRTY?`

Response Format: `CRTY <type>`

## CRVA?, CURSOR_VALUE?, Cursor Value, Trace Values, Cursor Measurement [2+4-channel]

The CURSOR_VALUE? query returns the values measured by the specified cursors for a given trace.

Query Syntax: `<trace>:CRVA? <mode> <trace>:= {C1,C2,C3,C4} <mode>:= {HREL,VREL}`

Response Format: `<trace>:CRVA HREL,<delta>,<1/delta>,<value1>,<value2> <trace>:CURSOR_VALUE VREL,<delta>,<value1>,<value2>`

## CSVS, CSV_SAVE, CSV Save, Waveform Data, USB Storage, CSV Format [2+4-channel]

The CSV_SAVE command selects the specified option of storing CSV format waveform. The CSV_SAVE? query returns the option of storing waveform data of CSV format.

Command Syntax: `Format1: CSV_SAVE SAVE,<state> The option SAVE is that if the waveform data is stored with parameter. <save>：= {OFF, ON} Format2: CSV_SAVE DD,<DD>,SAVE,<state> Digital Oscilloscopes Series The option DD is the data depth which is saved as. The option SAVE is that if the waveform data is stored with parameter. <DD>：={MAX，DIS} the meaning of MAX is saved as the maximum data depth. The meaning of DIS is saved as the date depth which is displayed on the screen <save>：= {OFF, ON} Note: This command varies with models, so there are two formats. If your oscilloscope can set the data depth of CSV file which will be saved, you should use Format2, such as non-SPO models, otherwise you should use Format1.`

Query Syntax: `CSV_SAVE?`

## CUS, CUSTOM, Digital, Custom Threshold, Digital Threshold [4-channel only]

The CUSTOM command sets the threshold value by customer for the specified group of channels. The threshold is used for triggering purposes and for displaying the digital data as high (above the threshold) or low (below the threshold). The CUSTOM? query returns the threshold value set by customer for the specified group of channels.

Command Syntax: `<group>:CUS <value> <group>:={H8,L8}`

Query Syntax: `<group>:CUS?`

Response Format: `<group>:CUS <value>`

## CYMT, CYMOMETER, Cymometer, Frequency Measurement, Cymometer Value [4-channel only]

The CYMOMETER? query measures and returns the frequency counter of the specified source. The counter measurement counts the trigger level crossings at the selected trigger slope and displays the results in E- notation with SI unit. Using CYMT_HW? to get the full precision value. In the following picture, the content of the red box is the measured value of the cymometer.

Query Syntax: `CYMT?`

Response Format: `CYMT <freq> Model Format of <freq> SDS1000X-E/ Numerical value in E-notation with SI SDS2000X-E/ unit, such as 1.00E+03Hz. SDS1000X-U Others Numerical value with measurement unit and physical unit, such as 1.00001 kHz.`

## DATE, DATE, Date, Time, Real-Time Clock, RTC [4-channel only]

The DATE command changes the date/time of the oscilloscope's internal real-time clock. The command is only used in the CFL series instrument.

Command Syntax: `DATE <day>, <month>, <year>, <hour>, <minute>, <second> <day> : = 1 to 31 <month> : = {JAN, FEB, MAR, APR, MAY, JUN, JUL, AUG, SEP,OCT, NOV, DEC} <year> : = 1990 to 2089 <hour> : = 0 to 23 <minute> : = 0 to 59 <second> : = 0 to 59`

Query Syntax: `DATE?`

## DCPA, Decode, Decode Common Parameters, Bus, List Format [2+4-channel]

The DCPA command is used to set the common parameters of serial decode bus.

Command Syntax: `DCPA <param>,<value>[,<param>,<value>[,..]]`

## DCST, Decode, Decode State, Serial Decode, On Off [2+4-channel]

The DCST command is used to set the state of decode. The DCST? query returns the state of decode.

Command Syntax: `DCST <state> <state>:={OFF,ON}`

Query Syntax: `DCST?`

Response Format: `DCST <state>`

## DDR?, DDR?, Device Dependent Register, Hardware Error, DDR [2+4-channel]

The DDR? Query reads and clears the contents of the Device Dependent or device specific error Register (DDR). In the case of a hardware failure, the DDR register specifies the origin of the failure.

Query Syntax: `DDR?`

## DEF, DEFINE?, Define, Math Expression, Equation, Function, Waveform Math [2+4-channel]

The DEFINE command sets the desired waveform math operation. The DEFINE? query returns the current operation for the selected function.

Command Syntax: `DEF EQN,’<equation>’`

Query Syntax: `DEF?`

Response Format: `DEF EQN,’<equation>’`

## DELF, DELETE_FILE, Delete File, Mass Storage, USB, File Management [2+4-channel]

The DELETE_FILE command deletes files from the currently selected directory on mass storage.

Command Syntax: `DELF DISK, <device>, FILE, ‗<filename>‘ <device>：={UDSK} <filename>：= a file of specified directory and the specified file should up to eight characters.`

## DIR, DIRECTORY, Directory, Create, Delete, Mass Storage, USB [2+4-channel]

The DIRECTORY command is used to manage the creation and deletion of file directories on mass storage devices. It also allows selection of the current working directory and listing of files in the directory. The query response consists of a double-quoted string containing a DOS-like listing of the directory.

Command Syntax: `DIR DISK, <device>, ACTION, <action>, ‗<directory>‘`

Query Syntax: `DIR? DISK, <device> [, ‗<directory>‘] <device>：={UDSK} <action>：={CREATE, DELETE} <directory>：= A legal DOS path or filename. (This can include the ‗/‘ character to define the directory.) root`

## DI:SW, DI:SWITCH, Digital, Digital Switch, Digital On Off [4-channel only]

The SWITCH command is used to set the state of digital. The SWITCH? query returns the state of digital.

Command Syntax: `DI:SW <state> <state>:={OFF,ON}`

Query Syntax: `DI:SW?`

Response Format: `DI:SW <state>`

## DTJN, DOT_JOIN, Dot Join, Interpolation, Vectors, Dots Display [2+4-channel]

The DOT_JOIN command sets the interpolation lines between data points.

Command Syntax: `DTJN <state> <state>:={ON,OFF}`

Query Syntax: `DTJN?`

Response Format: `DTJN <state>`

## EMOD, EduMode, System, Education Mode, Lock Autoset Measure Cursors [2+4-channel]

The command sets the education mode (locks of autosetup, measure and cursors) of the oscilloscope. The query returns the education mode of the oscilloscope.

Command Syntax: `EMOD <func>,<lock> <func>:={AutoSetup, Measure, Cursors} <lock>:={ON, OFF}`

Query Syntax: `EMOD? <func> <func>:={AutoSetup, Measure, Cursors}`

Response Format: `Query with the parameter “AutoSetup”: EMOD AutoSetup,ON; Query with no parameters: EduMode AutoSetup,<lock>;Measure,<lock>;Cursors,<lock>;`

## *ESE, *ESE, Event Status Enable, ESE Register, Status Byte [2+4-channel]

The *ESE command sets the Standard Event Status Enable register (ESE). This command allows one or more events in the ESR register to be reflected in the ESB summary message bit (bit 5) of the STB register.

Command Syntax: `*ESE <value> <value> : = 0 to 255`

Query Syntax: `*ESE?`

## *ESR?, *ESR?, Event Status Register, ESR, Standard Event [2+4-channel]

The *ESR? query reads and clears the contents of the Event Status Register (ESR). The response represents the sum of the binary values of the register bits 0 to 7.

Query Syntax: `*ESR?`

## EXR?, EXR?, Execution Error Register, EXR, Error Handling [2+4-channel]

The EXR? query reads and clears the contents of the Execution error Register (EXR). The EXR register specifies the type of the last error detected during execution.

Query Syntax: `EXR?`

## FFTC, FFT_CENTER, Math, FFT Center, Center Frequency [2+4-channel]

The FFT_CENTER command sets the center frequency when FFT (Fast Fourier Transform) is selected. The FFT_CENTER? query returns the current center frequency of FFT waveform.

Command Syntax: `FFTC <center> <center>:= frequency value with unit (MHz/ kHz/ Hz).`

Query Syntax: `FFTC?`

Response Format: `FFTC <center>`

## FFTF, FFT_FULLSCREEN, FFT Fullscreen, Full Screen Display, Frequency Domain [2+4-channel]

The FFT_FULLSCREEN command sets the display mode of FFT waveform. The FFT_FULLSCREEN? query returns whether the FFT waveform is full screen displayed.

Command Syntax: `FFTF <state> <state>:= {OFF,ON,EXCLU} OFF — Split Screen. ON — Full Screen. EXCLU — Exclusive.`

Query Syntax: `FFTF?`

Response Format: `FFTF <state>`

## FFTP, FFT_POSITION, Math, FFT Position, Horizontal Position [2+4-channel]

The FFT_POSITION command sets the vertical offset of FFT waveform. The unit is related to the vertical scale type of the current FFT and the unit of the channel. The FFT_POSITION? query returns the current vertical offset of the FFT waveform.

Command Syntax: `FFTP <offset> <offset>:= -24.4*DIV to 15.6*DIV.`

Query Syntax: `FFTP?`

Response Format: `FFTP <offset> <offset>:= Numerical value in E-notation with SI unit.`

## FFTS, FFT_SCALE, FFT Scale, Vertical Scale, dBVrms, Vrms [2+4-channel]

The FFT_SCALE command sets the vertical scale of FFT waveform. The unit is related to the vertical scale type of the current FFT and the unit of the channel. The FFT_SCALE? query returns the current vertical scale of FFT waveform.

Command Syntax: `FFTS <scale> <scale>:= {0.1,0.2,0.5,1,2,5,10,20} when scale type is dBVrms or dBm. <scale>:= {0.001,0.002,0.005,0.01,0.02,0.05,0.1,0.2,0.5,1,2,5,10,20} when scale type is Vrms.`

Query Syntax: `FFTS?`

Response Format: `FFTS <scale> <scale>:= Numerical value in E-notation with SI unit.`

## FFTT, FFT_TDIV, Math, FFT Time Division, FFT T/div [2+4-channel]

The FFT_TDIV? query returns current horizontal scale of FFT waveform.

Query Syntax: `FFTT?`

Response Format: `FFTT <value> <value>:= Numerical value with measurement unit and physical unit.`

## FFTU, FFT_UNIT, Math, FFT Unit, dBVrms, Vrms [2+4-channel]

The FFT_UNIT command sets the vertical scale type of FFT (Fast Fourier Transform algorithm). The FFT_UNIT? query returns the current vertical scale type of FFT waveform.

Command Syntax: `FFTU <unit> <unit>:={VRMS,DBM,DBVRMS}`

Query Syntax: `FFTU?`

Response Format: `FFTU <unit>`

## FFTW, FFT_WINDOW, FFT Window, Rectangle, Blackman, Hanning, Hamming, Flattop [2+4-channel]

The FFT_WINDOW command allows the selection of five different windowing transforms or operations for the FFT (Fast Fourier Transform) function. Each window is useful for certain classes of input signals. The FFT_WINDOW? query returns the current window of FFT.

Command Syntax: `FFTW <window> <window>:={RECT,BLAC,HANN,HAMM,FLATTOP}`

Query Syntax: `FFTW?`

Response Format: `FFTW <window>`

## FFTZ, FFT_ZOOM, FFT Zoom, Zoom Factor, Frequency Domain [2+4-channel]

The FFT_ZOOM command selects the specified zoom of FFT. The FFT_ZOOM? query returns the current zoom in/out of FFT.

Command Syntax: `FFTZ <zoom> <zoom>:={1,2,5,10}`

Query Syntax: `FFTZ?`

Response Format: `FFTZ <zoom>`

## FILT, FILTER, Filter, Digital Filter, Low-Pass, High-Pass, Band-Pass, Band-Reject [2+4-channel]

The FILTER command enables or disables filter of the specified trace. The response to the FILTER? query indicates whether the filter of specified trace is enabled.

Command Syntax: `<channel>:FILT <state> <channel> : = {C1,C2,C3,C4} <state> : = {ON,OFF}`

Query Syntax: `<channel>:FILT?`

## FILTS, FILT_SET, Filter Set, Filter Type, Filter Limit, LP, HP, BP, BR [2+4-channel]

The FILT_SET command selects the specified type of filter, and sets the limit value of filter. The FILT_SET? query returns current parameter of the filter.

Command Syntax: `<channel>:FILTS TYPE,<type>,<limit>,<limit_value> <channel>:={C1,C2,C3,C4} <type>:={LP,HP,BP,BR}`

Query Syntax: `<channel>:FILTS?`

Response Format: `<channel>:FILTS TYPE,<type>,<limit>,<limit_value>`

## FLNM, FILENAME, Filename, Default Name, Mass Storage, File Naming [2+4-channel]

The FILENAME command is used to change the default filename given to any traces, setups and hard copies when they are being stored to a mass storage device.

Command Syntax: `FLNM TYPE, <type>, FILE, ‗<filename>‘ <type>:={ C1,C2,C3, C4, SETUP,TA, TB, TC, TD, HCOPY} <filename> : = an alphanumeric string of up to 8 characters forming a legal DOS filename. Note: The file‘s extension can be specified automatically by the oscilloscope. Digital Oscilloscopes Series`

Query Syntax: `FLNM? TYPE, <type> <type> :={ ALL, C1, C2, C3, C4, SETUP, TA, TB, TC, TD, HCOPY}`

## FORM:DATA, FORMat:DATA, Comm Header, Data Format, Significant Digits, Response Format [2+4-channel]

The FORMat:DATA command controls the number of significant digits of the returned value. Only the value returned by MEASURE Commands are affected by this command.

Command Syntax: `FORM:DATA <mode>[,<digit>] <mode>:= {SINGLE, DOUBLE, CUSTOM}`

Query Syntax: `FORM:DATA?`

Response Format: `FORM:DATA CUSTOM,<digit>`

## FPAR, FRAME_PARAM, Frame Param, History, Descriptor, Frame Information [2+4-channel]

The FRAME_PARAM command is used to get frame param include descriptor name, product name, the total number of frames and so on.

Query Syntax: `FPAR? Note: This command is used with the history function.`

## FRAM, FRAME_SET, Frame Set, History, Frame Number, Sequence [2+4-channel]

The FRAME_SET command is used to set history current frame number. The FRAME_SET? query returns the current frame number.

Command Syntax: `FRAM <frame_num> <frame_num>:= 0 to the max frame number.`

Query Syntax: `FRAM?`

Response Format: `FRAM <frame_num>`

## FRTR, FORCE_TRIGGER, Force Trigger, Single Acquisition, Manual Trigger [2+4-channel]

Causes the instrument to make one acquisition.

Command Syntax: `FRTR`

## FTIM, FRAME_TIME, Frame Time, History, Acquisition Time [2+4-channel]

The FRAME_TIME query returns the acquire timestamp of the current frame.

Query Syntax: `FTIM?`

Response Format: `Format 1: FTIM hour: minute: second. micro-second Format 2: \xFF\x0F\x03\x01&\xD5\x02\x00`

## FVDISK, FORMAT_VDISK, Format USB Disk, USB Capability, Mass Storage [2+4-channel]

The FORMAT_VDISK? query reads the capability of the USB memory device.

Query Syntax: `FVDISK?`

## GCSV, GET_CSV, Get CSV, Waveform Data, CSV Format, Data Transfer [2+4-channel]

The response to the GET_CSV? Query indicates current waveform of CSV format. The GET_CSV? query has options to set. They are the same as the options of CSVS.

Query Syntax: `Format1: GET_CSV? SAVE,<state> The option SAVE sets the CSV save state. <state>：= {OFF,ON} Format2: GET_CSV? DD,<DD>,SAVE,<state> The option DD is the data depth of the CSV format waveform. The option SAVE sets the CSV save state. <DD>：={MAX，DIS} Digital Oscilloscopes Series MAX sets the CSV waveform depth to maximum. DIS sets the CSV waveform depth equal to the displayed on the screen. <state>：= {OFF,ON} Note: This command varies with models, so there are two formats. If you oscilloscope can set the data depth of CSV file which will be saved, you should use Format 2, otherwise you should use Format 1.`

## GRDS, GRID_DISPLAY, Grid Display, FULL, HALF, OFF, Graticule [2+4-channel]

The GRID_DISPLAY command selects the type of the grid which is used to display. The GRID_DISPLAY? query returns the current type of grid.

Command Syntax: `GRDS <type> < type >:={FULL,HALF,OFF}`

Query Syntax: `GRDS?`

Response Format: `GRDS <type>`

## HCSU, HARDCOPY_SETUP, Hardcopy Setup, Print, Screenshot, Save, Page Size [2+4-channel]

The HARDCOPY_SETUP command configures the instrument's hard-copy driver.

Command Syntax: `HCSU PSIZE, <page_size>, ISIZE, <image_size>, FORMAT, <format>, BCKG, <bckg>, PRTKEY, <printkey> <page_size> :={ DEFAULT} <printkey>:={SAVE,PRINT} <format> : = {PORTRAIT, LANDSCAPE} <bckg> : = {BLACK, WHITE} <image_size>:={DEFAULT,A4,LETTER}.`

Query Syntax: `HCSU?`

## HMAG, HOR_MAGNIFY, Horizontal Magnify, Zoom, Expansion, Magnification [2+4-channel]

The HMAG command sets the zoomed (delayed) window horizontal scale (seconds/div). The main sweep scale determines the range for this command. The maximum value is the TDIV value. The HMAG? query returns the current zoomed window scale setting.

Command Syntax: `Format 1: HMAG <value> <value>:={1NS,2NS,5NS,10NS,20NS,50NS,100NS,200NS,500NS,1US,2US,5US,10US,20US,50US,100US,200US,500US,1MS,2MS,5MS,10MS,20MS} The range of value is related to the current time base. It is from 1NS to the current time base. Format 2: HMAG <factor> <factor>:= 1 to 2,000,000. The range of <factor> is related to the current time base and the range of the time base.`

Query Syntax: `HMAG?`

Response Format: `HMAG <value> <value>:= Numerical value in E-notation with SI unit. HMAG <factor>`

## HPOS, HOR_POSITION, Horizontal Position, Delay, Timebase, Position [2+4-channel]

The HPOS command sets the horizontal position in the zoomed (delayed) view of the main sweep. The main sweep range and the main sweep horizontal position determine the range for this command. The value for this command must keep the zoomed view window within the main sweep range. The HPOS? query the current horizontal window position setting in the zoomed view.

Command Syntax: `Format 1: HPOS <position> <position>:= time value with unit.`

Query Syntax: `HPOS?`

Response Format: `HPOS <position> <position>:= Numerical value in E-notation with SI unit. HPOS <factor_div>`

## HSLST, HISTORY_LIST, History, History List, Frame Timestamp [2+4-channel]

The HISTORY_LIST command is used to set the state of history list. The HISTORY_LIST? query returns the current state of history list.

Command Syntax: `HSLST <state> <state>:={ON,OFF}`

Query Syntax: `HSLST?`

Response Format: `HSLST <state>`

## HSMD, HISTORY_MODE, History, History Mode, On Off [2+4-channel]

The HISTORY_MODE command is used to set the state of history mode. The HISTORY_MODE? query returns the current state of history mode.

Command Syntax: `HSMD <state> <state>:={ON,OFF}`

Query Syntax: `HSMD?`

Response Format: `HSMD <state>`

## *IDN?, *IDN?, Identification, Manufacturer, Model, Serial Number, Firmware [2+4-channel]

The *IDN? query is used for identification purposes. The response consists of four different fields providing information on the manufacturer, the scope model, the serial number and the firmware revision level.

Query Syntax: `*IDN?`

## ILVD, INTERLEAVED, Interleaved, RIS, Random Interleaved Sampling [2+4-channel]

The INTERLEAVED command enables or disables random interleaved sampling (RIS) for timebase settings where both single shot and RIS mode are available. The response to the INTERLEAVED? Query indicates whether the oscilloscope is in RIS mode.

Command Syntax: `ILVD <mode> <mode> : = {ON, OFF}`

Query Syntax: `ILVD?`

## INR?, INR?, Internal State Change Register, INR, Status [2+4-channel]

The INR? query reads and clears the contents of the INternal state change Register (INR). The INR register (table below) records the completion of various internal operations and state transitions. Note : 3. This command only supports 0 bit and 13 bit.

Query Syntax: `INR?`

## INTS, INTENSITY, Intensity, Grid Brightness, Trace Brightness, Display [2+4-channel]

The INTENSITY command sets the intensity level of the grid or the trace. The INTENSITY? query returns the grid and trace intensity levels.

Command Syntax: `INTS GRID,<value>,TRACE,<value> <value>:= 0 (or 30) to 100`

Query Syntax: `INTS?`

Response Format: `INTS TRACE,<value>,GRID,<value>`

## INVS, INVERT_SET, Invert, Trace Invert, Math Invert, Waveform Invert [2+4-channel]

The INVERTSET command mathematically inverts the specified traces or the math waveform. The INVERTSET? query returns the current state of the channel inversion.

Command Syntax: `<trace>:INVS <state> <trace>:={C1,C2,C3,C4,MATH} <state>:= {ON,OFF}`

Query Syntax: `<trace>:INVS?`

Response Format: `<trace>:INVS <state>`

## LOCK, LOCK, Lock, Keyboard Lock, Panel Lock, Front Panel [2+4-channel]

The LOCK command enables or disables the panel keyboard of the instrument. When any command or query is executed in either local or remote state, the functions of the panel keys except "FORCE" are not available. When the panel keyboard of the instrument is locked, press the "FORCE" key to enable the manual keyboard functions. The LOCK? query returns the status of the panel keyboard of the instrument.

Command Syntax: `LOCK <state> <state>:= {ON,OFF}`

Query Syntax: `LOCK?`

## MEACL, MEASURE_CLEAR, Measure, Measure Clear, Clear Measurements [2+4-channel]

The MEACL command removes all user specified measurements.

Command Syntax: `MEACL`

## MEAD, Measure Delay, Delay Measurement, Phase, FRR, FRF, FFR, FFF, LRR, LRF, LFF, SKEW [2+4-channel]

The MEASURE_DELAY command places the instrument in the continuous measurement mode and starts a type of delay measurement. The MEASURE_DELAY? query returns the measured value of delay type.

Command Syntax: `MEAD <type>,<sourceA-sourceB> <sourceA-sourceB>:={C1-C2,C1-C3,C1-C4,C2-C3,C2-C4,C3-C4} <type>:={PHA,FRR,FRF,FFR,FFF,LRR,LRF,LFR,LFF,SKEW}`

Query Syntax: `<sourceA-sourceB>:MEASURE_DELAY? <type>`

Response Format: `<sourceA-sourceB>:MEAD <type>,<value> Model Format of <value> SDS1000X-E/ Numerical value in E-notation with SI SDS2000X-E/ unit, such as 1.24E-04S. Except for SDS1000X-U PHA, it returns as “44.65degree”. Others Numerical value in E-notation with SI unit, such as 2.06E+01degree.`

## MEGA, MEASURE_GATEA, Measure, Measure Gate A, Gate Position [2+4-channel]

The MEGA command specifies the position of the measurement gateA.

Command Syntax: `MEGA <value> <value>:= value with unit.`

## MEGB, MEASURE_GATEB, Measure, Measure Gate B, Gate Position [2+4-channel]

The MEGB command specifies the position of the measurement gate B.

Command Syntax: `MEGB <value> <value>:= value with unit.`

## MEGS, MEASURE_GATE_SWITCH, Measure, Measure Gate Switch, Gate Measurement [2+4-channel]

The MEGS command controls the switch of the gate measurement. When the gate is turned on, only the waveform within the threshold will be measured. The MEGS? query return the switch of the gate.

Command Syntax: `MEGS <state> <state>:={OFF, ON}`

## MENU, MENU, Menu Display, ON, OFF, Screen Menu [2+4-channel]

The MENU command enables or disables to display the menu. The MENU? query returns whether the menu is displayed.

Command Syntax: `MENU <state> <state>:={ON,OFF}`

Query Syntax: `MENU?`

Response Format: `MENU <state>`

## MSIZ, MEMORY_SIZE, Memory Size, Max Memory Depth, Acquisition Memory [2+4-channel]

The MEMORY_SIZE command sets the maximum depth of memory. The MEMORY_SIZE? query returns the maximum depth of memory.

Command Syntax: `MSIZ <size> <size>:= {7K,70K,700K,7M} for non-interleaved mode. Non-interleaved means a single channel is active per A/D converter. Most oscilloscopes feature two channels per A/D converter. <size>:= {14K,140K,1.4M,14M} for interleave mode. Interleave mode means multiple active channels per A/D converter.`

Query Syntax: `MSIZ?`

Response Format: `MSIZ <size>`

## MTES:MASK:LOAD, MTESt:MASK:LOAD, Pass/Fail, Pass/Fail Mask Load, Recall Mask [4-channel only]

The MTESt:MASK:LOAD command recalls the mask from internal or external.

Command Syntax: `MTES:MASK:LOAD <path_type>[,<path_string>] <path_type>:= {INTernal, EXTernal} <path_string>:=Double quoted string, when <path_type> is EXTernal. The letters of all strings will be automatically converted to uppercase. Please ensure that the target path string is correct.`

## MTES:MASK:SAVE, MTESt:MASK:SAVE, Pass/Fail, Pass/Fail Mask Save, Store Mask [4-channel only]

The MTESt:MASK:SAVE command saves the mask to internal or external.

Command Syntax: `MTES:MASK:SAVE <path_type>[,<path_string>] <path_type>:= {INTernal, EXTernal} <path_string>:=Double quoted string, when <path_type> is EXTernal. This command will not automatically create a directory, and the letters of all strings will be automatically converted to uppercase. Please ensure that the target path string is correct.`

## MTVD, MATH_VERT_DIV, Math Vertical Division, Math Scale, Math Sensitivity [2+4-channel]

The MATH_VERT_DIV command sets the vertical scale of the selected math operation. This command is only valid in add, subtract, multiply and divide operation. The MATH_VERT_DIV? query returns the current scale value for the selected operation.

Command Syntax: `MTVD <scale> <scale>:={500uV,1mV,2mV,5mV,10mV,20mV,50mV,100 mV,200mV,500mV,1V,2V,5V,10V,20V,50V,100V} (for add, subtract, multiply and divide)`

Query Syntax: `MTVD?`

Response Format: `MTVD <scale> Model Format of <scale> SDS1000X-E/ Numerical value in E-notation with SI SDS2000X-E/ unit, such as 5.00E-01V. SDS1000X-U Others Numerical value with measurement unit and physical unit, such as 500mV.`

## MTVP, MATH_VERT_POS, Math Vertical Position, Math Waveform, Vertical Offset [2+4-channel]

The MATH_VERT_POS command sets the vertical position of the math waveform with specified source. The FFT waveform isn’t included, but we have another command which called FFTP to set vertical position. The MATH_VERT_POS? query returns the vertical position of the math waveform.

Command Syntax: `MTVP <point> <point>:= -255 to 255.`

Query Syntax: `MTVP?`

Response Format: `MTVP <point>`

## OFST, OFFSET, Offset, Vertical Offset, Channel Offset, DC Offset [2+4-channel]

The OFFSET command allows adjustment of the vertical offset of the specified input channel. The maximum ranges depend on the fixed sensitivity setting. The OFFSET? query returns the offset value of the specified channel.

Command Syntax: `<channel>:OFST <offset> <channel>:= {C1,C2,C3,C4} <offset>:= vertical offset value with unit, see the data sheet for details.`

Query Syntax: `<channel>:OFST?`

Response Format: `<channel>:OFST <offset> <offset>:= Numerical value in E-notation with SI unit.`

## *OPC, *OPC, Operation Complete, OPC Bit, Synchronization, Status [2+4-channel]

The *OPC command sets the operation complete bit in the Standard Event Status Register when all pending device operations have finished. The *OPC? query places an ASCII "1" in the output queue when all pending device operations have completed. The interface hangs until this query returns.

Command Syntax: `*OPC`

Query Syntax: `*OPC?`

Response Format: `*OPC 1 COMMON (*) *RST Command`

## *OPT?, *OPT?, Options, Installed Options, Identification [2+4-channel]

The *OPT? query identifies the installed oscilloscope options. The response consists of a series of response fields listing all the installed options.

Query Syntax: `*OPT?`

## OUTP, OUTPut, Waveform Generator, Load [4-channel only]

This command enables or disables the output port(s) at the front panel. The query returns “ON” or “OFF” and “LOAD”, “PLRT”, “RATIO” parameters.

Command Syntax: `<channel>:OUTP <state>,LOAD,<load> <channel>:= {C1}, SAG1021I only support one output channel. <state>:= {ON, OFF} <load>:= {50, HZ}. The unit is ohm.`

Query Syntax: `<channel>:OUTP?`

Response Format: `<channel>:OUTP <state>,LOAD,<load>,PLRT,<polarity> <state>:= {ON, OFF} <load>:= {50, HZ} <polarity>:= {NOR, INVT}, in which NOR refers to normal, and INVT refers to invert. SAG and the built-in waveform generator only support to set to NOR.`

## PACL, PARAMETER_CLR, Parameter Clear, Pass/Fail, Counter Reset [2+4-channel]

The PARAMETER_CLR command resets the P/F test statistics.

Command Syntax: `PACL`

## PACU, PARAMETER_CUSTOM, Parameter Custom, Customizable Qualifiers [2+4-channel]

The PARAMETER_CUSTOM command installs a measurement and starts the specified measurement of the specified source. See the command PAVA? to get the measured value of specified measurement. See the command MEADto install the measurement of delay class.

Command Syntax: `PACU <parameter>,<source> <source>:= {C1,C2,C3,C4} <parameter>:={PKPK,MAX,MIN,AMPL,TOP,BASE,CMEA N,MEAN,STDEV,VSTD,RMS,CRMS,OVSN,FPRE,OVSP,RP RE,LEVELX,DELAY,TIMEL,PER,FREQ,PWID,NWID,RISE,F ALL,WID,DUTY,NDUTY,ALL} Description of Parameter Parameter Description PKPK vertical peak-to-peak MAX maximum vertical value MIN minimum vertical value AMPL vertical amplitude TOP waveform top value BASE waveform base value CMEAN average value in the first cycle MEAN average value STDEV standard deviation of the data VSTD standard deviation of the data in the first cycle RMS RMS value CRMS RMS value in the first cycle OVSN overshoot of a falling edge FPRE preshoot of a falling edge OVSP overshoot of a rising edge RPRE preshoot of a rising edge LEVELX Level measured at trigger position PER period FREQ frequency PWID positive pulse width NWID negative pulse width RISE rise-time FALL fall-time WID Burst width DUTY positive duty cycle NDUTY negative duty cycle DELAY time from the trigger to the first transition at the 50% crossing TIMEL time from the trigger to each rising edge at the 50% crossing ALL All measurements snapshot, equal to turn on the switch of all measure`

## PASTAT, Measure, Parameter Statistics, Measurement Statistics [2+4-channel]

The PASTAT command controls the operation and display of measurement statistics. The PASTAT? query return the state of measurement statistics.

Command Syntax: `PASTAT <state> <state>:={OFF, ON, RESET}`

Query Syntax: `PASTAT?`

Response Format: `PASTAT <state> <state>:={OFF, ON}`

## PAVA?, PARAMETER_VALUE?, Parameter Value, Measurement Values, PKPK, MAX, MIN, AMPL, RMS [2+4-channel]

The PARAMETER_VALUE query measures and returns the specified measurement value present on the selected waveform. The significant digits of the measured value are 7 by default, which can be modified by command “:FORMat:DATA”. There are three uses for this command: Usage Description Usage1 Specify the source and the measurement. See the command “MEAD?” to get the measured value of delay measurement. Usage 2 Use “PAVA? CUST<x>” to get customized. Usage 3 Use “PAVA? STAT<x>” to get statistics.

Response Format: `PAVA STAT<x> <source> <parameter>:cur,<value1>,mean,<value2>,min,<value3>,max,<value4>,std-dev,<value5>,count,<value6>`

## PDET, PEAK_DETECT, Peak Detect, Acquisition Mode, Peak Detection [2+4-channel]

The PEAK_DETECT command switches ON or OFF the peak detector built into the acquisition system. The PEAK_DETECT? query returns the current status of the peak detector.

Command Syntax: `PDET <state> <state> : = {ON, OFF}`

Query Syntax: `PDET?`

## PERS, PERSIST, Persist, Persistence, Display Mode [2+4-channel]

The PERSIST command enables or disables the persistence display mode.

Command Syntax: `PERS <mode> <mode> : = {ON, OFF}`

Query Syntax: `PERS?`

## PESU, PERSIST_SETUP, Persist Setup, Persistence Duration [2+4-channel]

The PERSIST_SETUP command selects the persistence duration of the display, in seconds, in persistence mode. The PERSIST_SETUP? query returns the current status of the persistence.

Command Syntax: `PESU <time> Models <time>:= SDS1000X-E/ {OFF,INFINITE,1,5,10,30} SDS2000X-E/ SDS1000X-U Others {INFINITE,1,5,10,30}`

Query Syntax: `PESU?`

Response Format: `PESU <time>`

## PFBF, PF_BUFFER, Pass/Fail, Pass/Fail Buffer, Output Mode, Buzzer [2+4-channel]

The PF_BUFFER command sets the output mode when the test fails. This is the same as pressing the “Output” button on the menu of PASS/FAIL on the front panel. The PF_BUFFER? query returns the current output mode of the pass/fail.

Command Syntax: `PFBF <state> <state>:={ON,OFF}`

Query Syntax: `PFBF?`

Response Format: `PFBF <state>`

## PFCM, PF_CREATEM, Pass/Fail Create Mask, Create Mask, Mask Generation [2+4-channel]

The PF_CREATEM command creates a Pass/Fail test rule around the current selected channel, using the horizontal adjustment parameters and the vertical adjustment parameters defined by the PFST commands.

Command Syntax: `PFCM`

## PFCT, PF_CONTROL, Pass/Fail Control, Operate, Output, Stop on Output [2+4-channel]

The PF_CONTROL command controls the Pass/Fail controlling options “operate”, “output” and the “stop on output”. See instrument’s Operator Manual for these options. The PF_CONTROL? query returns the controlling options of the pass/fail.

Command Syntax: `PFCT TRACE,<trace>,CONTROL,<control>,OUTPUT,<output >,OUTPUTSTOP,<state> <trace>:={C1,C2,C3,C4} <control>:={START,STOP} <output>:={FAIL,PASS} <state>:={ON,OFF}`

Query Syntax: `PFCT?`

Response Format: `PFCT TRACE,<trace>,CONTROL,<control>,OUTPUT,<output >,OUTPUTSTOP,<state>`

## PFDD, PF_DATEDIS, Pass/Fail Data Display, Fail Count, Pass Count, Total [2+4-channel]

The PF_DATADIS? query returns the number of the failed frames, passed frames and total frames which are shown on screen.

Command Syntax: `PFDD?`

Response Format: `PFDD FAIL,<num>,PASS,<num>,TOTAL,<num>`

## PFDS, PF_DISPLAY, Pass/Fail Display, Test, Message, Mask Test [2+4-channel]

The PF_DISPLAY command displays information in Pass/Fail test features. The PF_DISPLAY? query returns whether the message of Pass/Fail is displayed.

Command Syntax: `PFDS <state> <state>:={ON,OFF}`

Query Syntax: `PFDS?`

Response Format: `PFDS <state> EXAMPL The following steps display the message of Pass/Fail. Step 1: Send command to set the Pass/Fail test enable. Command message: PFEN ON Step 2: Send command to display the message of Pass/Fail. Command message: PFDS ON`

## PFEN, PF_ENABLE, Pass/Fail, Pass/Fail Enable, Mask Test [2+4-channel]

The PF_ENABLE command enables or disables the Pass/Fail test features. The PF_ENABLE? query returns the current state of mask test features.

Command Syntax: `PFEN <state> <state>:= {ON,OFF}`

Query Syntax: `PFEN?`

Response Format: `PFEN <state> EXAMPL The following command enables mask test features. Command message: PFEN ON`

## PFFS, PF_FAIL_STOP, Pass/Fail, Pass/Fail Fail Stop, Stop On Fail [2+4-channel]

The PF_FAIL_STOP command sets the switch of the “stop on fail” function. This is the same as pressing the “Stop on Fail” button on the menu of Pass/Fail on the front panel. The PF_FAIL_STOP? query returns the state of the “stop on fail” function.

Command Syntax: `PFFS <state> <state>:={ON,OFF}`

Query Syntax: `PFFS?`

Response Format: `PFFS <state>`

## PFOP, PF_OPERATION, Pass/Fail, Pass/Fail Operation, Run Stop [2+4-channel]

The PF_OPERATION command controls to run or stop Pass/Fail test. The PF_OPERATION? query returns the operation state of Pass/Fail test.

Command Syntax: `PFOP <state> <state>:={ON,OFF}`

Query Syntax: `PFOP?`

Response Format: `PFOP <state>`

## PFSC, PF_SOURCE, Pass/Fail, Pass/Fail Source, Channel [2+4-channel]

The PF_SOURCE command sets measurement sources for Pass/Fail test. The PF_SOURCE? query returns the measurement source for Pass/Fail test.

Command Syntax: `PFSC <trace> <trace>:={C1,C2,C3,C4}`

Query Syntax: `PFSC?`

Response Format: `PFSC <trace>`

## PFSL, PF_SAVELOAD, Pass/Fail Save Load, Mask, Recall, Save Mask [2+4-channel]

The PF_SAVELOAD command saves or recalls the created pass/fail mask. On SDS1000X-E, use MTES:MASK:SAVE and MTES:MASK:LOAD for mask storage.

## PFST, PF_SET, Pass/Fail Set, X Mask, Y Mask, Mask Configuration [2+4-channel]

The PF_SET command sets the tolerance in the X/Y direction around the selected waveform defined by PFSC for the Pass/Fail feature. The value of the tolerance will be added and subtracted to horizontal/Vertical values of the waveform to determine the boundaries of the mask. The PF_SET? query returns the current setting of the ΔX tolerance and ΔY tolerance for Pass/Fail.

Command Syntax: `PFST XMASK,<div>,YMASK,<div> <div>:= 0.04 to 4.0.`

Query Syntax: `PFST?`

Response Format: `PFST XMASK,<div>,YMASK,<div>`

## PNSU, PANEL_SETUP, Panel Setup, Save, Recall, Archive, Setup Transfer [2+4-channel]

The PANEL_SETUP command use the data get from “PNSU?” to set the panel setup. The PNSU? query return the data of panel setup from scope. There are two types of formats for returned data: binary and xml. See the table below for details. Format Description Binary The returned data is binary, cannot be compatible between versions. Applicable models: SDS1000CFL SDS1000A SDS1000CML+/CNL+/DL+/E+/F+ SDS2000X SDS1000X SDS1000X-E (2ch, 4ch for V6.1.33 and earlier) Xml The returned data is in XML form and compatible between versions. Applicable models: SDS1000X-E (4ch for V6.1.33R2 and later) SDS2000X-E SDS1000X-U

Command Syntax: `PNSU <header><setup data> <header>:= Characters in the format of “#9<9-Digits>” is used to describe the length of <setup data>, which is returned by the query PNSU? <setup data>:= A setup previously returned by the query PNSU?`

Query Syntax: `PNSU?`

Response Format: `PNSU <header><setup data>`

## *RCL, *RCL, Recall, Panel Setup, Nonvolatile Memory, Setup Recall [2+4-channel]

The *RCL command recalls the complete front-panel setup of the instrument from internal memory, using one of the twenty non-volatile panel setups. This command is opposite to the command *SAV. See the command RCPN for recalling the setup from external.

Command Syntax: `*RCL <num> <num>:= 0 to 20.`

## RCPN, RECALL_PANEL, Recall Panel, Front Panel Setup, Mass Storage, USB [2+4-channel]

The RECALL_PANEL command recalls a front-panel setup from the specified-DOS path directory in an external memory device. See the command “*RCL” for recalling from internal.

Command Syntax: `RCPN DISK,<device>,FILE,‘<filename>’ <device>:= {UDSK} <filename>:= A waveform file under a legal DOS path. Models Description SDS1000X-E/ The filename string is up to eight SDS2000X-E/ characters, with the extension “.xml”. SDS1000X-U Others The filename string is up to eight characters, with the extension “.set”.`

## RECALL, RECALL, Recall Waveform, Mass Storage, USB, Waveform File [2+4-channel]

The RECALL command recalls a waveform file from the current directory on mass storage into any or all of the internal memories M1 to M10(or M20 in the CFL series).

Command Syntax: `<memory>: REC DISK, <device>, FILE, ‗<filename>‘ <memory> : = {M1~M10}(or M1~M20 in the CFL series) <device> : = {UDSK} <filename>：= A waveform file under a legal DOS path . A filename-string of up to eight characters, with the extension “ .DAV ” . (This can include the ‘/’ character to define the root directory.)`

## REFCL, REF_CLOSE, Reference, Reference Close, Clear REF [2+4-channel]

The REF_CLOSE command closes the Reference function.

Command Syntax: `REFCL`

## REFDS, REF_DISPLAY, Reference, Reference Display, REF Waveform [2+4-channel]

The REF_DISPLAY command enables or disables the current reference channel shown on the screen. The REF_DISPLAY? query returns whether the current reference channel shows on the screen.

Command Syntax: `REFDS <state> <state>:= {ON,OFF}`

Query Syntax: `REFDS?`

Response Format: `REFDS <state>`

## REFLA, REF_LOCATION, Reference, Reference Location, REFA REFB [2+4-channel]

The REF_LOCATION command selects the current reference channel. The REF_LOCATION? query returns the current reference channel.

Command Syntax: `REFLA <location> <location>:= {REFA,REFB,REFC,REFD}`

Query Syntax: `REFLA?`

Response Format: `REFLA <location>`

## REFPO, REF_POSITION, Reference, Reference Position, Vertical Offset [2+4-channel]

The REF_POSITION command sets the vertical offset of the current reference channel. This command is only used when the current reference channel has been saved, and the display state is on. The REF_POSITION? query returns the vertical offset of the current reference channel.

Command Syntax: `REFPO <offset> <offset>:= vertical offset value with unit.`

Query Syntax: `REFPO?`

Response Format: `REFPO <offset> <offset>:= Numerical value in E-notation with SI unit.`

## REFS, REF_SET, Reference Set, REF Waveform, Display, RA, RB, RC, RD [2+4-channel]

The REF_SET command sets the reference waveform and its options. The response to the REF_ SET? query indicates whether the specified reference waveform is turned on.

Command Syntax: `REF _ SET TRACE,<trace>REF,<ref>,state, <state>,SAVE,DO <trace> : = {C1,C2,C3,C4,MATH} <ref> : = {RA,RB,RC,RD} The Rx(x is A,B,C,D) is that which one can be stored or displayed <state> := {ON,OFF} The state enables or disables to display the specified reference waveform. If the command syntax include ‗SAVE,DO‘, the specified trace will be saved to the specified reference waveform.`

Query Syntax: `REF _ SET? REF,<ref>`

## REFSA, REF_SAVE, Reference, Reference Save, Store REF [2+4-channel]

The REF_SAVE command saves the waveform (screen range) of the specified source as the reference waveform of the current reference channel to the memory and displays it on the screen.

Command Syntax: `REFSA`

## REFSC, REF_SCALE, Reference, Reference Scale, Vertical Scale [2+4-channel]

The REF_SCALE command sets the vertical scale of the current reference channel. This command is only used when the current reference channel has been stored, and the display state is on. The REF_SCALE? query returns the vertical scale of the current reference channel.

Command Syntax: `REFSC <scale> <scale>:= 500uV to 10V.`

Query Syntax: `REFSC?`

Response Format: `REFSC <scale> <scale>:= Numerical value in E-notation with SI unit.`

## REFSR, REF_SOURCE, Reference, Reference Source, Channel Math [2+4-channel]

The REF_SOURCE command sets the reference waveform source. The REF_SOURCE? query returns the source of the current reference channel.

Command Syntax: `REFSR <source> <source>:= {C1,C2,C3,C4,MATH}`

Query Syntax: `REFSR?`

Response Format: `REFSR <source>`

## *RST, *RST, Reset, Device Reset, Default Setup, Factory Reset [2+4-channel]

The *RST command initiates a device reset. This is the same as pressing Default on the front panel.

Command Syntax: `*RST`

## SANU, SAMPLE_NUM, Sample Number, Sample Points, Trigger Position [2+4-channel]

The SANU? query returns the number of data points that the hardware will acquire from the input signal. The number of points acquired is based on the horizontal scale and memory/acquisition depth selections and cannot be directly set.

Query Syntax: `SANU?`

Response Format: `SANU <value> Model Format of <value> SDS1000X-E/ Numerical value in E-notation with SDS2000X-E/ SI unit, such as 7.00E+05pts. SDS1000X-U SDS2000/2000X/ Numerical value with measurement 1000X/1000X+ unit and physical unit, such as 28Mpts. others Numerical value, such as 1600.`

## SARA, SAMPLE_RATE, Sample Rate, Sa/s, Acquisition Sample Rate [2+4-channel]

The SARA? query returns the sample rate of the scope.

Query Syntax: `SARA? DI:SARA?`

Response Format: `SARA <value> DI:SARA <value> Model Format of <value> SDS1000X-E/ Numerical value in E-notation with SDS2000X-E/ SI unit, such as 5.00E+08Sa/s. SDS1000X-U others Numerical value with measurement unit and physical unit, such as 1.00 GSa/s.`

## SAST, SAMPLE_STATUS, Sample Status, Acquisition Status, Trigger Status [2+4-channel]

The SAST? query returns the acquisition status of the scope.

Query Syntax: `SAST?`

Response Format: `SAST <status>`

## *SAV, *SAV, Save, Current State, Nonvolatile Memory, Panel Setup [2+4-channel]

The *SAV command stores the complete front-panel setup of the instrument in internal memory. This instruction does not support storing to external temporarily. See the command STPN for external storage.

Command Syntax: `*SAV <setup_num> <setup_num>:= 1 to 20.`

## SCDP, SCREEN_DUMP, Screen Dump, Screenshot, Hardcopy, Image, BMP [2+4-channel]

The SCREEN_DUMP command captures the screen and returns the data of bmp file.

Query Syntax: `SCDP`

Response Format: `<bmp header><bmp screen data>`

## SCSV, SCREEN_SAVE, Screen Save, Screen Saver, Automatic, Display Save [2+4-channel]

The SCREEN_SAVE command controls the automatic screensaver, which automatically shuts down the internal color monitor after a preset time. The SCREEN_SAVE? query returns whether the automatic screensaver feature is on.

Command Syntax: `SCSV <time> <time>:={OFF,1MIN,5MIN,10MIN,30MIN,60MIN}`

Query Syntax: `SCSV?`

Response Format: `SCSV <time>`

## SET50, SETTO%50, Set to 50%, Trigger Level, Centre, Amplitude [2+4-channel]

The SET50 command automatically sets the trigger levels to center of the trigger source waveform. When High and Low (dual) trigger levels are used (as Runt triggers, for example), this command has no effect.

Command Syntax: `SET50`

## SKEW, SKEW, Skew, Deskew, Channel, Time Delay, Phase Adjustment [2+4-channel]

The SKEW command sets the channel-to-channel skew factor for the specified channel. Each analog channel can be adjusted + or -100 ns for a total of 200 ns difference between channels. You can use the oscilloscope's skew control to remove cable-delay errors between channels. The SKEW? query returns the skew value of the specified trace.

Command Syntax: `<trace>:SKEW <skew> <trace>:= {C1,C2,C3,C4} <skew>:= -100 ns to +100 ns.`

Query Syntax: `<trace>:SKEW?`

Response Format: `<trace>:SKEW <skew> Model Format of <skew> SDS1000X-E / Numerical value in E-notation with SI SDS2000X-E/ unit, such as 9.99E-08S. SDS1000X-U others Numerical value with measurement unit and physical unit, such as 0.00ns.`

## *SRE, *SRE, Service Request Enable, SRE, Status Byte, SRQ [2+4-channel]

The *SRE command sets the Service Request Enable register (SRE). This command allows the user to specify which summary message bit(s) in the STB register will generate a service request. A summary message bit is enabled by writing a ‗1' into the corresponding bit location. Conversely, writing a ‗0' into a given bit location prevents the associated event from generating a service request (SRQ). Clearing the SRE register disables SRQ interrupts. The *SRE? query returns a value that, when converted to a binary number, represents the bit settings of the SRE register. Note: 1. That bit 6 (MSS) cannot be set and its returned value is always zero.

Command Syntax: `*SRE <value> <value> : = 0 to 255`

Query Syntax: `*SRE?`

## *STB?, *STB?, Status Byte, STB, IEEE 488, Status Register [2+4-channel]

The *STB? query reads the contents of the IEEE 488.1 defined status register (STB), and the Master Summary Status (MSS). The response represents the values of bits 0 to 5 and 7 of the Status Byte register and the MSS summary message. The response to a *STB? query is identical to the response of a serial poll except that the MSS summary message appears in bit 6 in place of the RQS message.

Query Syntax: `*STB?`

## STO, STORE, Store, Trace, Internal Memory, Mass Storage, Waveform Save [2+4-channel]

The STORE command stores the contents of the specified trace into the current directory in a USB memory device.

Command Syntax: `STO <trace> <trace>: = {TA, TB, TC, TD, C1, C2, C3, C4,ALL_DISPLAYED} <dest>: = { UDSK} Note: 1. If the STORE command is sent without any argument, and the current trace isn‘t enabled, the current trace will be enabled and stored in the Store Setup. This setup can be modified using the STORE_SETUP command. 2. The <dest> parameter is vary with oscilloscope‘s models. If your oscilloscope is non-SPO models , this parameter‘s options are {M1~M10(or M20 in the CFL series)}, UDSK}. If your oscilloscope is SPO model, this parameter‘s option is {UDSK}.`

## STOP, STOP, Stop, Acquisition Stop, Signal Acquisition, HALT [2+4-channel]

The STOP command stops the acquisition. This is the same as pressing the Stop key on the front panel.

Command Syntax: `STOP`

## STPN, STORE_PANEL, Store Panel, Front Panel Setup, Mass Storage, USB [2+4-channel]

The STORE_PANEL command stores the complete front-panel setup of the instrument into a file on the specified-DOS path directory in a USB memory device. See the command “*SAV” for internal storage.

Command Syntax: `STPN DISK,<device>,FILE,‘<filename>’ <device>:= {UDSK} <filename>:= A waveform file under a legal DOS path. Models Description SDS1000X-E/ The filename string is up to eight SDS2000X-E/ characters, with the extension SDS1000X-U “.xml”. Others The filename string is up to eight characters, with the extension “.set”.`

## STST, STORE_SETUP, Store Setup, Trace Storage, Configuration [2+4-channel]

The STORE_SETUP command controls the way in which traces will be stored. A single trace or all displayed traces may be enabled for storage.

Command Syntax: `STST [<trace>, <dest>] <trace>:= {C1,C2,C3,C4,ALL_DISPLAYED } <dest>: ={UDSK} Note: The <dest> parameter is vary with oscilloscope‘s models. If your oscilloscope is not an SPO model, it‘s options are {M1~M10(or M20 in the CFL series)}, UDSK}. If your oscilloscope is an SPO model, its option is {UDSK}.`

Query Syntax: `STST?`

## SXSA, SINXX_SAMPLE, Sinx/x Sample, Interpolation, Sine, Linear [2+4-channel]

The SINXX_SAMPLE command sets the way of interpolation. The SINXX_SAMPLE? query returns the way of interpolation.

Command Syntax: `SXSA <state> <state>:= {ON,OFF} ON — sine interpolation. OFF — linear interpolation.`

Query Syntax: `SXSA?`

Response Format: `SXSA <state>`

## SYNC, Waveform Generator, Sync Output [4-channel only]

This command sets or gets the synchronization signal.

Command Syntax: `<channel>:SYNC <state> <channel>:= {C1}, SAG1021I only support one output channel. <state>:= {ON, OFF}`

Query Syntax: `<channel>:SYNC? <channel>:= {C1}`

Response Format: `<channel>:SYNC <state>,TYPE,<TYPE> <channel>:= {C1} <state>:= {ON, OFF} <TYPE>:={CH1}, SAG1021I only support one output channel, so it can only be CH1.`

## TDIV, TIME_DIV, Time Division, Timebase, Horizontal Scale [2+4-channel]

The TIME_DIV command sets the horizontal scale per division for the main window. The TIME_DIV? query returns the current horizontal scale setting in seconds per division for the main window.

Command Syntax: `TDIV <value> <value>:={1NS,2NS,5NS,10NS,20NS,50NS,100NS,200NS, 500NS,1US,2US,5US,10US,20US,50US,100US,200US,500US,1MS,2MS,5MS,10MS,20MS,50MS,100MS,200MS,50 0MS,1S,2S,5S,10S,20S,50S,100S} NS — for nanoseconds. US — for microseconds. MS — for milliseconds. S — for seconds.`

Query Syntax: `TDIV?`

Response Format: `TDIV <value> <value>:= Numerical value in E-notation with SI unit.`

## TIM:DEL, TIMebase:DELay, Timebase, Timebase Delay, Horizontal Delay [2+4-channel]

The TIMebase:DELay command sets the time interval from the horizontal center point on the screen to the trigger event. The maximum position value depends on the time/division settings. The TIMebase:DELay? query returns the current time from the horizontal center to the trigger point in seconds.

Command Syntax: `TIM:DEL <delay> <delay>:= time value with unit.`

Query Syntax: `TIM:DEL?`

Response Format: `<value> Model Format of <skew> SDS1000X-E Numerical value in E-notation with SI unit, such as 1.00E-04 s.`

## TMPL, TEMPLATE, Template, Waveform Template, Descriptor [2+4-channel]

The TEMPLATE? query produces a copy of the template that describes the various logical entities making up a complete waveform. In particular, the template describes in full detail the variables contained in the descriptor part of a waveform.

Query Syntax: `TMPL?`

## TRA, TRACE, Trace, Display, Channel, ON, OFF, Waveform Visibility [2+4-channel]

The TRACE command turns the display of the specified channel on or off. The TRACE? query returns the current display setting for the specified channel.

Command Syntax: `<trace>:TRA <mode> <trace>:={C1,C2,C3,C4} <mode>:={ON,OFF}`

Query Syntax: `<trace>:TRA?`

Response Format: `<trace>:TRA <mode>`

## TRA (Digital), TRACE, Digital Trace, Channel Display, D0-D15 [4-channel only]

The TRACE command turns digital display on or off for the specified channel. The TRACE? query returns the current digital display setting for the specified channel.

Command Syntax: `<digital>:TRA <state> <digital>:={D0,D1,D2,D3,D4,D5,D6,D7,D8,D9,D10,D11, D12,D13,D14,D15} <state>:={OFF,ON}`

Query Syntax: `<digital>:TRA?`

Response Format: `<digital>:TRA <state>`

## TRCAN:BAUD, Serial Trigger, Trigger CAN, ID Data [2+4-channel]

The TRCAN:BAUD command sets the baud rate for CAN trigger. The TRCAN:BAUD? query returns the baud rate for CAN trigger.

Command Syntax: `TRCAN:BAUD <value1>[,<value2>] <value1>:={5k,10k,20k,59k,100k,125k,250,500k,800k,1 M,CUSTOM} <value2>:= 5000 to 1000000 When the value1 is CUSTOM.`

Query Syntax: `TRCAN:BAUD?`

Response Format: `TRCAN:BAUD <value1>[,<value2>]`

## TRCAN:CANH, Serial Trigger, Trigger CAN, ID Data [2+4-channel]

The TRCAN:CANH command sets the source and threshold for source of CAN trigger. The TRCAN:CANH? query returns the source and threshold CANH of CAN trigger.

Command Syntax: `TRCAN:CANH <source>[,<threshold>] <source>:={C1,C2,C3,C4,D0,D1,D2,D3,D4,D5,D6,D7,D8, D9,D10,D11,D12,D13,D14,D15} <threshold>:= value with unit. It is necessary to set when the source is analog channel.`

Query Syntax: `TRCAN:CANH?`

Response Format: `TRCAN:CANH <source>[,<threshold>]`

## TRCAN:CON, Serial Trigger, Trigger CAN, ID Data [2+4-channel]

The TRCAN:CON command sets the trigger condition of CAN trigger. The TRCAN:CON? query returns the trigger condition of CAN trigger.

Command Syntax: `TRCAN:CON <condition> <condition>:= {START,REMOTE,ID,ID_AND_DATA,ERROR}`

Query Syntax: `TRCAN:CON?`

Response Format: `TRCAN:CON <condition>`

## TRCAN:DAT2, Serial Trigger, Trigger CAN, ID Data [2+4-channel]

The TRCAN:DAT2 command sets the data2 value used for CAN trigger when the trigger condition is set to ID_AND_DATA. The TRCAN:DAT2? query returns the data2 value used for CAN trigger when the trigger condition is set to ID_AND_DATA.

Command Syntax: `TRCAN:DAT2 <value> <value>:= 0 to 256`

Query Syntax: `TRCAN:DAT2?`

Response Format: `TRCAN:DAT2 <value>`

## TRCAN:DATA, Serial Trigger, Trigger CAN, ID Data [2+4-channel]

The TRCAN:DATA command sets the data1 value used for CAN trigger when the trigger condition is set to ID_AND_DATA. The TRCAN:DATA? query returns the data1 value for CAN trigger when the trigger condition is set to ID_AND_DATA.

Command Syntax: `TRCAN:DATA <value> <value>:= 0 to 256`

Query Syntax: `TRCAN:DATA?`

Response Format: `TRCAN:DATA <value>`

## TRCAN:ID, Serial Trigger, Trigger CAN, ID Data [2+4-channel]

The TRCAN:ID command sets the ID value for CAN trigger when the trigger condition is set to ID or ID_AND_DATA. The TRCAN:ID? query returns the ID value for CAN trigger when the trigger condition is set to ID or ID_AND_DATA.

Command Syntax: `TRCAN:ID <value> <value>:= 0 to 2^n when n is the ID bits (11 or 29)`

Query Syntax: `TRCAN:ID?`

Response Format: `TRCAN:ID <value>`

## TRCAN:IDL, Serial Trigger, Trigger CAN, ID Data [2+4-channel]

The TRCAN:IDL command sets the ID length for CAN trigger when the trigger condition is set to ID or ID_AND_DATA. The TRCAN:IDL? query returns the ID length for CAN trigger when the trigger condition is set to ID or ID_AND_DATA.

Command Syntax: `TRCAN:IDL <value> <value>:= {11BITS,29BITS}`

Query Syntax: `TRCAN:IDL?`

Response Format: `TRCAN:IDL <value>`

## TRCP, TRIG_COUPLING, Trigger Coupling, AC, DC, LF Reject, HF Reject [2+4-channel]

The TRIG_COUPLING command sets the input coupling for the selected trigger sources. The TRIG_COUPLING? query returns the trigger coupling of the selected source.

Command Syntax: `<trig_source>:TRCP <trig_coupling> <trig_source>:={C1,C2,C3,C4,EX,EX5} <trig_coupling>:={AC,DC,HFREJ,LFREJ}`

Query Syntax: `<trig_source>:TRCP?`

Response Format: `<trig_source>:TRCP <trig_coupling>`

## TRDL, TRIG_DELAY, Trigger Delay, Holdoff, Time, Trigger Timing [2+4-channel]

The TRIG_DELAY command sets the time interval from the trigger event to the horizontal center point on the screen. The maximum position value depends on the time/division settings. Pre-trigger acquisition — Data acquired before the trigger occurs. Negative trigger delays must be given in seconds. Post-trigger acquisition — Data acquired after the trigger has occurred. The TRIG_DELAY? query returns the current time from the trigger to the horizontal center point in seconds.

Command Syntax: `TRDL <delay> <delay>:= time value with unit.`

Query Syntax: `TRDL?`

Response Format: `TRDL <value> Model Format of <skew> SDS1000X-E/ Numerical value in E-notation with SI SDS2000X-E/ unit, such as 1.00E-04 s. SDS1000X-U Others Numerical value with measurement unit and physical unit, such as 3.58 ns.`

## *TRG, *TRG, Trigger, ARM, Acquisition, Manual Trigger [2+4-channel]

The *TRG command triggers the oscilloscope. It is equivalent to pressing the Single button: the oscilloscope arms the trigger circuitry and makes one acquisition.

Command Syntax: `*TRG`

## TRIIC:ADDR, Serial Trigger, Trigger I2C, SCL SDA [2+4-channel]

The TRIIC:ADDR command sets the address value used for the IIC trigger when the trigger condition is set to 7ADDA or 10ADDA. The TRIIC:ADDR? query returns the address value when the trigger condition is set to 7ADDA or 10ADDA.

Command Syntax: `TRIIC:ADDR <value> <value>:= 0 to 2^n when n is the address length(7 or 10)`

Query Syntax: `TRIIC:ADDR?`

Response Format: `TRIIC:ADDR <value>`

## TRIIC:ALEN, Serial Trigger, Trigger I2C, SCL SDA [2+4-channel]

The TRIIC:ALEN command sets the IIC address type when the trigger condition is set to Data Length. The TRIIC:ALEN? query returns the IIC address type when the trigger condition is set to Data Length.

Command Syntax: `TRIIC:ALEN <value> <value>:= {7BIT,10BIT}`

Query Syntax: `TRIIC:ALEN?`

Response Format: `TRIIC:ALEN <value>`

## TRIIC:CON, Serial Trigger, Trigger I2C, SCL SDA [2+4-channel]

The TRIIC:CON command sets the trigger condition of IIC trigger. The TRIIC:CON? query returns the trigger condition of IIC trigger.

Command Syntax: `TRIIC:CON <condition> <condition>:={START,STOP,RESTART,NOACK,EEPROM, 7ADDA,10ADDA,DALENTH}`

Query Syntax: `TRIIC:CON?`

Response Format: `TRIIC:CON <condition>`

## TRIIC:DAT2, Serial Trigger, Trigger I2C, SCL SDA [2+4-channel]

The TRIIC:DAT2 command sets the data2 value used for IIC trigger when the trigger condition is set to 7ADDA or 10ADDA. The TRIIC:DAT2? query returns the data2 value used for IIC trigger when the trigger condition is set to 7ADDA or 10ADDA.

Command Syntax: `TRIIC:DAT2 <value> <value>:= 0 to 256`

Query Syntax: `TRIIC:DAT2?`

Response Format: `TRIIC:DAT2 <value>`

## TRIIC:DATA, Serial Trigger, Trigger I2C, SCL SDA [2+4-channel]

The TRIIC:DATA command sets the data1 value used for IIC trigger when the trigger condition is set to 7ADDA, 10ADDA or EEPROM. The TRIIC:DATA? query returns the data1 value used for IIC trigger when the trigger condition is set to 7ADDA, 10ADDA or EEPROM.

Command Syntax: `TRIIC:DATA <value> <value>:= 0 to 256`

Query Syntax: `TRIIC:DATA?`

Response Format: `TRIIC:DATA <value>`

## TRIIC:DLEN, Serial Trigger, Trigger I2C, SCL SDA [2+4-channel]

The TRIIC:DLEN command sets the length of the data in bytes to be used for IIC trigger if the trigger condition is Data length. The TRIIC:DLEN? query returns the length of the data in bytes.

Command Syntax: `TRIIC:DLEN <value> <value>:= 1 to 12`

Query Syntax: `TRIIC:DLEN?`

Response Format: `TRIIC:DLEN <value>`

## TRIIC:QUAL, Serial Trigger, Trigger I2C, SCL SDA [2+4-channel]

The TRIIC:QUAL command sets the IIC data qualifier when the trigger condition is set to EEPROM. The TRIIC:QUAL? query returns the data qualifier used for the IIC trigger is set to EEPROM.

Command Syntax: `TRIIC:QUAL <value> <value>:= {EQUAL,MORE,LESS}`

Query Syntax: `TRIIC:QUAL?`

Response Format: `TRIIC:QUAL <value>`

## TRIIC:RW, Serial Trigger, Trigger I2C, SCL SDA [2+4-channel]

The TRIIC:RW command sets the IIC trigger type to be valid on a Read, Write, or Either condition. Read or write is indicated by the R/W bit in the IIC protocol. The TRIIC:RW? query returns the condition on the R/W bit used for the IIC trigger.

Command Syntax: `TRIIC:RW <value> <value>:= {READ,WRITE,DONT_CARE}`

Query Syntax: `TRIIC:RW?`

Response Format: `TRIIC:RW <value>`

## TRIIC:SCL, Serial Trigger, Trigger I2C, SCL SDA [2+4-channel]

The TRIIC:SCL command sets the source and threshold for the serial clock (SCL) of IIC trigger. The TRIIC:SCL? query returns the source and threshold for the serial clock (SCL) of IIC trigger.

Command Syntax: `TRIIC:SCL <source>[,<threshold>] <source>:={C1,C2,C3,C4,D0,D1,D2,D3,D4,D5,D6,D7,D8, D9,D10,D11,D12,D13,D14,D15} <threshold>:= value with unit. It is necessary to set when the source is analog channel.`

Query Syntax: `TRIIC:SCL?`

Response Format: `TRIIC:SCL <source>[,<threshold>] <threshold>:= numerical value in E-notation with SI unit.`

## TRIIC:SDA, Serial Trigger, Trigger I2C, SCL SDA [2+4-channel]

The TRIIC:SDA command sets the source and threshold for the serial data input channel (SDA) of IIC trigger. The TRIIC:SDA? query returns the source and threshold for the serial data input channel (SDA) of IIC trigger.

Command Syntax: `TRIIC:SDA <source>[,<threshold>] <source>:={C1,C2,C3,C4,D0,D1,D2,D3,D4,D5,D6,D7,D8, D9,D10,D11,D12,D13,D14,D15} <threshold>:= value with unit. It is necessary to set when the source is analog channel.`

Query Syntax: `TRIIC:SDA?`

Response Format: `TRIIC:SDA <source>[,<threshold>] <threshold>:= numerical value in E-notation with SI unit.`

## TRLIN:BAUD, Serial Trigger, Trigger LIN, Break ID [2+4-channel]

The TRLIN:BAUD command sets the baud rate for LIN trigger. The TRLIN:BAUD? query returns the baud rate value for LIN trigger.

Command Syntax: `TRLIN:BAUD <value1>[,<value2>] <value1>:= {600,1200,2400,4800,9600,19200,CUSTOM} <value2>:= 300 to 20000 When the value1 is CUSTOM.`

Query Syntax: `TRCAN:BAUD?`

Response Format: `TRLIN:BAUD <value1>[,<value2>]`

## TRLIN:CON, Serial Trigger, Trigger LIN, Break ID [2+4-channel]

The TRLIN:CON command sets the trigger condition of LIN trigger. The TRLIN:CON? query returns the trigger condition of LIN trigger.

Command Syntax: `TRLIN:CON <condition> <condition>:= {BREAK,ID,ID_AND_DATA,DATA_ERROR}`

Query Syntax: `TRLIN:CON?`

Response Format: `TRLIN:CON <condition>`

## TRLIN:DAT2, Serial Trigger, Trigger LIN, Break ID [2+4-channel]

The TRLIN:DAT2 command sets the data2 value used for LIN trigger when the trigger condition is set to ID_AND_DATA. The TRLIN:DAT2? query returns the data2 value used for LIN trigger when the trigger condition is set to ID_AND_DATA.

Command Syntax: `TRLIN:DAT2 <value> <value>:= 0 to 256.`

Query Syntax: `TRLIN:DAT2?`

Response Format: `TRLIN:DAT2 <value>`

## TRLIN:DATA, Serial Trigger, Trigger LIN, Break ID [2+4-channel]

The TRLIN:DATA command sets the data1 value used for LIN trigger when the trigger condition is set to ID_AND_DATA. The TRLIN:DATA? query returns the data1 value used for LIN trigger when the trigger condition is set to ID_AND_DATA.

Command Syntax: `TRLIN:DATA <value> <value>:= 0 to 256`

Query Syntax: `TRLIN:DATA?`

Response Format: `TRLIN:DATA <value>`

## TRLIN:ID, Serial Trigger, Trigger LIN, Break ID [2+4-channel]

The TRLIN:ID command sets the ID value for LIN trigger when the trigger condition is set to ID or ID_AND_DATA. The TRLIN:ID? query returns the ID value for LIN trigger when the trigger condition is set to ID or ID_AND_DATA.

Command Syntax: `TRLIN:ID <value>`

Query Syntax: `TRLIN:ID?`

Response Format: `TRLIN:ID <value> <value>:= 0 to 64.`

## TRLIN:SRC, Serial Trigger, Trigger LIN, Break ID [2+4-channel]

The TRLIN:SRC command sets the source and threshold for the source of LIN trigger. The TRLIN:SRC? query returns the source and threshold for the source of LIN trigger.

Command Syntax: `TRLIN:SRC <source>[,<threshold>] <source>:={C1,C2,C3,C4,D0,D1,D2,D3,D4,D5,D6,D7,D8, D9,D10,D11,D12,D13,D14,D15} <threshold>:= value with unit. It is necessary to set when the source is analog channel.`

Query Syntax: `TRLIN:SRC?`

Response Format: `TRLIN:SRC <source>[,<threshold>] <threshold>:= numerical value in E-notation with SI unit.`

## TRLV, TRIG_LEVEL, Trigger Level, Voltage, Threshold, Trigger Threshold [2+4-channel]

The TRIG_LEVEL command sets the trigger level voltage for the active trigger source. When there are two trigger levels to set, this command is used to set the higher trigger level voltage for the specified source. TRLV2 is used to set the lower trigger level voltage. The TRIG_LEVEL? query returns the trigger level of the current trigger source.

Command Syntax: `<trig_source>:TRLV <trig_level> <trig_source>:={C1,C2,C3,C4,EX,EX5} <trig_level>:= -4.5*DIV to 4.5*DIV for internal triggers. <trig_level>:= -3*DIV to 3*DIV for external triggers.`

Query Syntax: `<trig_source>:TRLV?`

Response Format: `<trig_source>:TRLV <trig_level> <trig_level>:=Numerical value in E-notation with SI unit.`

## TRLV2, TRIG_LEVEL2, Trigger Level 2, Second Trigger Level, Dual Level [2+4-channel]

The TRIG_LEVEL2 command sets the lower trigger level voltage for the specified source. Higher and lower trigger levels are used with runt /slope triggers. The TRIG_LEVEL2? query returns the lower trigger level voltage for the specified source.

Command Syntax: `<trig_source>:TRLV2 <trig_level> <trig_source>:= {C1,C2,C3,C4} <trig_level>:= -4.5*DIV to 4.5*DIV.`

Query Syntax: `<trig_source>:TRLV2?`

Response Format: `<trig_source>:TRLV2 <trig_level> <trig_level>:=Numerical value in E-notation with SI unit.`

## TRMD, TRIG_MODE, Trigger Mode, AUTO, NORMAL, SINGLE, STOP [2+4-channel]

The TRIG_MODE command selects the trigger sweep mode. The TRIG_MODE? query returns the current trigger sweep mode.

Command Syntax: `TRMD <mode> <mode>:= {AUTO,NORM,SINGLE}`

Query Syntax: `TRMD?`

Response Format: `TRMD <mode>`

## TRPA, TRIG_PATTERN, Trigger Pattern, Pattern Trigger, Logic, AND, OR, NAND, NOR [2+4-channel]

The TRIG_PATTERN command specifies the channel values to be used in the pattern trigger and sets the condition of the pattern trigger. The TRIG_PATTERN? query returns channel values and the condition of the pattern trigger.

Command Syntax: `TRPA <source>,<status>[,<source>,<status>[,<source>,<status>[,<source>,<status>]]],STATE,<condition> < source >:={C1,C2,C3,C4} <status>:={X,L,H} < condition >:={AND,OR,NAND,OR}`

Query Syntax: `TRPA?`

Response Format: `TRPA <source>,<status>,<source>,<status>,<source>,<status>,<source>,<status>,STATE,<condition>`

## TRSE, TRIG_SELECT, Trigger Select, Edge, Slope, Pulse, Video, Window, Interval, Dropout, Runt, Pattern, Serial [2+4-channel]

The TRIG_SELECT command selects the condition that will trigger the acquisition of waveforms. Depending on the trigger type, additional parameters must be specified. These additional parameters are grouped in pairs. The first in the pair names the variable to be modified, while the second gives the new value to be assigned. Pairs may be given in any order and restricted to those variables to be changed. The TRIG_SELECT? query returns the current trigger condition.

Command Syntax: `TRSE (FOR ALL BUT TV) <trig_type>,SR,<source>,HT,<hold_type>,HV,<hold_value1>[,HV2,<hold_value2>] <trig_type>:={EDGE,SLEW,GLIT,INTV,RUNT,DROP} <source>:={C1,C2,C3,C4,LINE,EX,EX5}`

Query Syntax: `TRSE?`

Response Format: `TRSE <trig_type>,SR,<source>,HT,<hold_type>,HV,<hold_value1>[,HV2,<hold_value2>]`

## TRSL, TRIG_SLOPE, Trigger Slope, Rising Edge, Falling Edge, NEG, POS, WINDOW [2+4-channel]

The TRIG_SLOPE command sets the trigger slope of the specified trigger source. The TRIG_SLOPE? query returns the trigger slope of the selected source.

Command Syntax: `<trig_source>:TRSL <trig_slope> <trig_source>:={C1,C2,C3,C4,EX,EX5} <trig_slope>:={NEG,POS,WINDOW} for edge trigger. <trig_slope>:={NEG,POS} for other trigger.`

Query Syntax: `<trig_source>:TRSL?`

Response Format: `<trig_source>:TRSL <trig_slope>`

## TRSPI:BIT, Serial Trigger, Trigger SPI, CLK MISO MOSI CS [2+4-channel]

The TRSPI:BIT command sets the bit order for SPI trigger. The TRSPI:BIT? query returns the bit order for SPI trigger.

Command Syntax: `TRSPI:BIT <order> <order>:= {MSB,LSB}`

Query Syntax: `TRSPI:BIT?`

Response Format: `TRSPI:BIT <order>`

## TRSPI:CLK, Serial Trigger, Trigger SPI, CLK MISO MOSI CS [2+4-channel]

The TRSPI:CLK command sets the source and threshold for the serial clock of SPI trigger. The TRSPI:CLK? query returns the source and threshold for the serial clock of SPI trigger.

Command Syntax: `TRSPI:CLK <source>[,<threshold>] <source>:={C1,C2,C3,C4,D0,D1,D2,D3,D4,D5,D6,D7,D8, D9,D10,D11,D12,D13,D14,D15} <threshold>:= value with unit. It is necessary to set when the source is analog channel.`

Query Syntax: `TRSPI:CLK?`

Response Format: `TRSPI:CLK <source>[,<threshold>] <threshold>:= numerical value in E-notation with SI unit.`

## TRSPI:CLK:EDGE, Serial Trigger, Trigger SPI, CLK MISO MOSI CS [2+4-channel]

The TRSPI:CLK:EDGE command selects the edge of the clock that data latched on. The TRSPI:CLK:EDGE? query returns the edge of the clock that data latched on.

Command Syntax: `TRSPI:CLK:EDGE <edge> <edge>:= {RISING,FALLING}`

Query Syntax: `TRSPI:CLK:EDGE?`

Response Format: `TRSPI:CLK:EDGE <edge>`

## TRSPI:CLK:TIM, Serial Trigger, Trigger SPI, CLK MISO MOSI CS [2+4-channel]

The TRSPI:CLK:TIM command sets the timeout value for the clock of SPI trigger when the CS type is set to CLK Timeout. The TRSPI:CLK:TIM? query returns the timeout value for the clock of SPI trigger when the CS type is set to CLK Timeout.

Command Syntax: `TRSPI:CLK:TIM <value> <value>:= value with unit, 100ns to 5ms`

Query Syntax: `TRSPI:CLK:TIM?`

Response Format: `TRSPI:CLK:TIM <value> <threshold>:= numerical value in E-notation with SI unit.`

## TRSPI:CS, Serial Trigger, Trigger SPI, CLK MISO MOSI CS [2+4-channel]

The TRSPI:CS command sets the source and threshold for CS signal of SPI trigger when the CS type is CS. The TRSPI:CS? query returns the source and threshold for CS signal of SPI trigger when the CS type is CS.

Command Syntax: `TRSPI:CS <source>[,<threshold>] <source>:={C1,C2,C3,C4,D0,D1,D2,D3,D4,D5,D6,D7,D8, D9,D10,D11,D12,D13,D14,D15} <threshold>:= value with unit. It is necessary to set when the source is analog channel.`

Query Syntax: `TRSPI:CS?`

Response Format: `TRSPI:CS <source>[,<threshold>] <threshold>:= numerical value in E-notation with SI unit.`

## TRSPI:CSTP, Serial Trigger, Trigger SPI, CLK MISO MOSI CS [2+4-channel]

The TRSPI:CSTP command sets the serial chip selection type of SPI trigger. The TRSPI:CSTP? query returns the serial chip selection type of SPI trigger.

Command Syntax: `TRSPI:CSTP <type> <type>:= {CS,NCS,TIMEOUT}`

Query Syntax: `TRSPI:CSTP?`

Response Format: `TRSPI:CSTP <type>`

## TRSPI:DATA, Serial Trigger, Trigger SPI, CLK MISO MOSI CS [2+4-channel]

The TRSPI:DATA command sets the data value of every bit used for SPI trigger.

Command Syntax: `TRSPI:DATA <value1>[,<value2>[,..[,<value>]]] <value>:= {0,1,X}`

## TRSPI:DLEN, Serial Trigger, Trigger SPI, CLK MISO MOSI CS [2+4-channel]

The TRSPI:DLEN command sets the length of data for SPI trigger. The TRSPI:DLEN? query returns the length of data for SPI trigger.

Command Syntax: `TRSPI:DLEN <value> <value>:= 4 to 96`

Query Syntax: `TRSPI:DLEN?`

Response Format: `TRSPI:DLEN <value>`

## TRSPI:MISO, Serial Trigger, Trigger SPI, CLK MISO MOSI CS [2+4-channel]

The TRSPI:MISO command sets the source and threshold for MISO of SPI trigger. The TRSPI:MISO? query returns the source and threshold for MISO of SPI trigger.

Command Syntax: `TRSPI:MISO <source>[,<threshold>] <source>:={C1,C2,C3,C4,D0,D1,D2,D3,D4,D5,D6,D7,D8, D9,D10,D11,D12,D13,D14,D15} <threshold>:= value with unit. It is necessary to set when the source is analog channel.`

Query Syntax: `TRSPI:MISO?`

Response Format: `TRSPI:MISO <source>[,<threshold>] <threshold>:= numerical value in E-notation with SI unit.`

## TRSPI:MOSI, Serial Trigger, Trigger SPI, CLK MISO MOSI CS [2+4-channel]

The TRSPI:MOSI command sets the source and threshold for MOSI of SPI trigger. The TRSPI:MOSI? query returns the source and threshold for MOSI of SPI trigger.

Command Syntax: `TRSPI:MOSI <source>[,<threshold>] <source>:={C1,C2,C3,C4,D0,D1,D2,D3,D4,D5,D6,D7,D8, D9,D10,D11,D12,D13,D14,D15} <threshold>:= value with unit. It is necessary to set when the source is analog channel.`

Query Syntax: `TRSPI:MOSI?`

Response Format: `TRSPI:MOSI <source>[,<threshold>] <threshold>:= numerical value in E-notation with SI unit.`

## TRSPI:NCS, Serial Trigger, Trigger SPI, CLK MISO MOSI CS [2+4-channel]

The TRSPI:NCS command sets the source and threshold for ~CS signal of SPI trigger when the CS type is ~CS. The TRSPI:NCS? query returns the source and threshold for ~CS signal of SPI trigger when the CS type is ~CS.

Command Syntax: `TRSPI:NCS <source>[,<threshold>] <source>:={C1,C2,C3,C4,D0,D1,D2,D3,D4,D5,D6,D7,D8, D9,D10,D11,D12,D13,D14,D15} <threshold>:= value with unit. It is necessary to set when the source is analog channel.`

Query Syntax: `TRSPI:NCS?`

Response Format: `TRSPI:NCS <source>[,<threshold>] <threshold>:= numerical value in E-notation with SI unit.`

## TRSPI:TRTY, Serial Trigger, Trigger SPI, CLK MISO MOSI CS [2+4-channel]

The TRSPI:TRTY command sets the trigger source for SPI trigger. The TRSPI:TRTY? query returns the trigger source for SPI trigger.

Command Syntax: `TRSPI:TRTY <source> <source>:= {MOSI,MISO}`

Query Syntax: `TRSPI:TRTY?`

Response Format: `TRSPI:TRTY <source>`

## TRUART:BAUD, Serial Trigger, Trigger UART, RX TX [2+4-channel]

The TRUART:BAUD command sets the baud rate value used for UART trigger. The TRUART:BAUD? query returns the baud rate value used for UART trigger.

Command Syntax: `TRUART:BAUD <value1>[,<value2>] <value1>:={600,1200,2400,4800,9600,19200,38400,576 00,115200,CUSTOM} <value2>:= 300 to 5000000 When the value1 is CUSTOM.`

Query Syntax: `TRUART:BAUD?`

Response Format: `TRUART:BAUD <value>[,<value2>]`

## TRUART:BIT, Serial Trigger, Trigger UART, RX TX [2+4-channel]

The TRUART:BIT command sets the bit order for UART trigger. The TRUART:BIT? query returns the bit order for UART trigger.

Command Syntax: `TRUART:BIT <value> <value>:= {LSB,MSB}`

Query Syntax: `TRUART:BIT?`

Response Format: `TRUART:BIT <value>`

## TRUART:CON, Serial Trigger, Trigger UART, RX TX [2+4-channel]

The TRUART:CON command sets the trigger condition of UART trigger. The TRUART:CON? query returns the trigger condition of UART trigger.

Command Syntax: `TRUART:CON <condition> <condition>:= {START,STOP,DATA,ERROR}`

Query Syntax: `TRUART:CON?`

Response Format: `TRUART:CON <condition>`

## TRUART:DATA, Serial Trigger, Trigger UART, RX TX [2+4-channel]

The TRUART:DATA command sets the data value used for UART trigger when the trigger condition is set to DATA. The TRUART:DATA? query returns the data1 value used for UART trigger when the trigger condition is set to DATA.

Command Syntax: `TRUART:DATA <value> <value>:= 0 to 256`

Query Syntax: `TRUART:DATA?`

Response Format: `TRUART:DATA <value>`

## TRUART:DLEN, Serial Trigger, Trigger UART, RX TX [2+4-channel]

The TRUART:DLEN command sets the data length value used for UART trigger. The TRUART:DLEN? query returns the data length value used for UART trigger.

Command Syntax: `TRUART:DLEN <value> <value>:= 5 to 8`

Query Syntax: `TRUART:DLEN?`

Response Format: `TRUART:DLEN <value>`

## TRUART:PAR, Serial Trigger, Trigger UART, RX TX [2+4-channel]

The TRUART:PAR command sets the parity check used for UART trigger. The TRUART:PAR? query returns the parity check used for UART trigger.

Command Syntax: `TRUART:PAR <value> <value>:= {NONE,ODD,EVEN}`

Query Syntax: `TRUART:PAR?`

Response Format: `TRUART:PAR <value>`

## TRUART:POL, Serial Trigger, Trigger UART, RX TX [2+4-channel]

The TRUART:POL command sets the idle level used for UART trigger. The TRUART:POL? query returns the idle level used for UART trigger.

Command Syntax: `TRUART:POL <value> <value>:= {LOW,HIGH}`

Query Syntax: `TRUART:POL?`

Response Format: `TRUART:POL <value>`

## TRUART:QUAL, Serial Trigger, Trigger UART, RX TX [2+4-channel]

The TRUART:QUAL command sets the UART data qualifier when the trigger condition is set to DATA. The TRUART:QUAL? query returns the UART data qualifier when the trigger condition is set to DATA.

Command Syntax: `TRUART:QUAL <condition> <condition>:= {EQUAL,MORE,LESS }`

Query Syntax: `TRUART:QUAL?`

Response Format: `TRUART:QUAL <condition>`

## TRUART:RX, Serial Trigger, Trigger UART, RX TX [2+4-channel]

The TRUART:RX command sets the source and threshold for RX of UART trigger. The TRUART:RX? query returns the source and threshold for RX of UART trigger.

Command Syntax: `TRUART:RX <source>[,<threshold>] <source>:={C1,C2,C3,C4,D0,D1,D2,D3,D4,D5,D6,D7,D8, D9,D10,D11,D12,D13,D14,D15} <threshold>:= value with unit. It is necessary to set when the source is analog channel.`

Query Syntax: `TRUART:RX?`

Response Format: `TRUART:RX <source>[,<threshold>] <threshold>:= numerical value in E-notation with SI unit.`

## TRUART:STOP, Serial Trigger, Trigger UART, RX TX [2+4-channel]

The TRUART:STOP command sets the length of stop bit for UART trigger. The TRUART:STOP? query returns the length of stop bit for UART trigger.

Command Syntax: `TRUART:STOP <value> <value>:= {1,1.5,2}`

Query Syntax: `TRUART:STOP?`

Response Format: `TRUART:STOP <value>`

## TRUART:TRTY, Serial Trigger, Trigger UART, RX TX [2+4-channel]

The TRUART:TRTY command sets the trigger source for UART trigger. The TRUART:TRTY? query returns the trigger source for UART trigger.

Command Syntax: `TRUART:TRTY <source> <source>:= {RX,TX}`

Query Syntax: `TRUART:TRTY?`

Response Format: `TRUART:TRTY <source>`

## TRUART:TX, Serial Trigger, Trigger UART, RX TX [2+4-channel]

The TRUART:TX command sets the source and threshold for TX of UART trigger. The TRUART:TX? query returns the source and threshold for TX of UART trigger.

Command Syntax: `TRUART:TX <source>[,<threshold>] <source>:={C1,C2,C3,C4,D0,D1,D2,D3,D4,D5,D6,D7,D8, D9,D10,D11,D12,D13,D14,D15} <threshold>:= value with unit. It is necessary to set when the source is analog channel.`

Query Syntax: `TRUART:TX?`

Response Format: `TRUART:TX <source>[,<threshold>] <threshold>:= numerical value in E-notation with SI unit.`

## TRWI, TRIG_WINDOW, Trigger Window, Window Trigger, Absolute, Relative [2+4-channel]

The TRIG_WINDOW command sets the relative height of the two trigger line of the trigger window type.

Command Syntax: `TRWI <value> <value>:= 0 to 9*DIV when the center level is 0.`

Query Syntax: `TRWI?`

Response Format: `TRWI <value> <value>:= Numerical value in E-notation with SI unit.`

## TSM, THRESHOLD_MODE, Digital, Threshold Mode, Logic Family, TTL CMOS [4-channel only]

The THRESHOLD_MODE command sets the threshold type for the specified group of channels. The threshold is used for triggering purposes and for displaying the digital data as high (above the threshold) or low (below the threshold). The THRESHOLD_MODE? query returns the threshold type for the specified group of channels.

Command Syntax: `<group>:TSM <type> <group>:={H8,L8}`

Query Syntax: `<group>:TSM?`

Response Format: `<group>:TSM <type>`

## UNIT, UNIT, Unit, Channel Unit, V, A, Voltage, Ampere [2+4-channel]

The UNIT command sets the unit of the specified trace. Measurement results, channel sensitivity, and trigger level will reflect the measurement units you select. The UNIT? query returns the unit of the specified trace.

Command Syntax: `<channel>:UNIT <type> <channel>:={C1,C2,C3,C4} <type>:={V,A}`

Query Syntax: `<channel>:UNIT?`

Response Format: `<channel>:UNIT <type>`

## VDIV, VOLT_DIV, Volt Division, Vertical Sensitivity, V/div [2+4-channel]

The VOLT_DIV command sets the vertical sensitivity in Volts/div. If the probe attenuation is changed, the scale value is multiplied by the probe's attenuation factor. The VOLT_DIV? query returns the vertical sensitivity of the specified channel.

Command Syntax: `<channel>:VDIV <v_gain> <channel>:={C1,C2,C3,C4} <v_gain>:= 500uV to 10V.`

Query Syntax: `<channel>:VDIV?`

Response Format: `<channel>:VDIV <v_gain> <v_gain>:= Numerical value in E-notation with SI unit.`

## VERT, VERTICAL, Vertical, Slope Trigger Line, Position [2+4-channel]

The VERTICAL command controls the vertical position of the slope trigger line. It is related to the TRSE command; in TRSE syntax the option is `VERT,<vertical>` with `<vertical>:={UP,DOWN,BOTH}`.

## VOLTPRT, Waveform Generator, Over Voltage Protection, OVP [4-channel only]

This commend sets or gets the state of over-voltage protection.

Command Syntax: `VOLTPRT <state> <state>:= {ON, OFF}`

Query Syntax: `VOLTPRT?`

Response Format: `VOLTPRT <state>`

## VPOS, VERT_POSITION, Vertical Position, FFT, Display Offset [2+4-channel]

The VERT_POSITION command adjusts the vertical position of the specified FFT trace on the screen. It does not affect the original offset value obtained at acquisition time. The VERT_POSITION? query returns the current vertical position of the specified FFT trace.

Command Syntax: `<trace>:VPOS <offset> <trace>:={TA,TB,TC,TD} <offset>:= -20*DIV to 20*DIV.`

Query Syntax: `<trace>:VPOS?`

Response Format: `<trace>:VPOS <offset>`

## WAIT, WAIT, Wait, Synchronization, Acquisition Complete [2+4-channel]

The WAIT command prevents the instrument from analyzing new commands until the oscilloscope has completed the current acquisition.

Command Syntax: `WAIT`

## WF?, WAVEFORM?, Waveform Transfer, Data, Acquisition, DESC, DAT2, ALL [2+4-channel]

The WAVEFORM? query transfers a waveform from the oscilloscope to the controller.

Query Syntax: `<trace>:WF? <section> <trace>:={C1,C2,C3,C4,MATH,D0,D1,D2,D3,D4,D5,D6,D7,D8,D9,D10,D11,D12,D13,D14,D15}`

Response Format: `<trace>:WF <data block>`

## WFSU, WAVEFORM_SETUP, Waveform Setup, Data Points, SP, NP, FP [2+4-channel]

The WAVEFORM_SETUP command specifies the amount of data in a waveform to be transmitted to the controller. The WAVEFORM_SETUP? query returns the transfer parameters currently in use.

Command Syntax: `WFSU SP,<sparsing>,NP,<number>,FP,<point>`

Query Syntax: `WFSU?`

Response Format: `WFSU SP,<sparsing>,NP,<number>,FP,<point>`

## XYDS, XY_DISPLAY, XY Display, XY Format, X-Y Mode, Lissajous [2+4-channel]

The XY_DISPLAY command enables or disables the display of XY mode. XY mode plots the voltage data of both channels with respect to one-another. For example, channel 1 vs. channel 2. This can be used to create lissajous curves. The standard display mode plots voltage data vs. time. The XY_DISPLAY? query returns whether the XY format display is enabled.

Command Syntax: `XYDS <state> <state>:= {ON,OFF}`

Query Syntax: `XYDS?`

Response Format: `XYDS <state>`
