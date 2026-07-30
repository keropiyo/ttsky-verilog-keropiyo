# Keropiyo Tiny AM Radio

## How it works

Keropiyo Tiny AM Radio is an experimental 1-bit software-defined AM radio receiver implemented in Verilog.

The design runs from a 50 MHz clock. An external RF front end receives and amplifies the AM radio signal. A high-speed comparator converts the analog RF signal into a 1-bit digital stream, which is connected to `ui_in[0]`.

Inside the digital design, a 32-bit numerically controlled oscillator (NCO) generates the local tuning frequency. The receiver covers the Japanese medium-wave AM band from 531 kHz to 1602 kHz in 9 kHz steps. After reset, the receiver starts at 810 kHz.

The 1-bit RF input is mixed with quadrature local oscillator signals to produce I and Q baseband signals. A two-stage CIC filter performs low-pass filtering and reduces the sample rate from 50 MHz to approximately 97.7 kHz.

The AM envelope is approximated using:

`abs(I) + abs(Q)`

A slowly varying DC estimate is removed from the envelope to recover the audio signal. The resulting 8-bit audio level is converted into a PWM signal on `uo_out[1]`.

A rotary encoder connected to `ui_in[1]` and `ui_in[2]` changes the selected frequency. The `TUNE_HOME` input returns the receiver to 810 kHz, and the `MUTE` input sets the audio PWM output to a silent 50 percent duty cycle.

This is an educational prototype. The digital design has been synthesized and hardened, but real AM reception will also depend on the external antenna, RF amplifier, comparator circuit, filtering, PCB layout, and signal conditions.

## How to test

The project requires a 50 MHz clock.

After reset, check that the bidirectional output pins show channel number 31, corresponding to 810 kHz:

`(810 kHz - 531 kHz) / 9 kHz = 31`

The main controls are:

* `ui_in[0]`: 1-bit RF comparator input
* `ui_in[1]`: rotary encoder A
* `ui_in[2]`: rotary encoder B
* `ui_in[3]`: mute
* `ui_in[4]`: return tuning to 810 kHz

The main outputs are:

* `uo_out[0]`: comparator feedback output
* `uo_out[1]`: PWM audio output
* `uo_out[2]`: CIC output sample tick
* `uo_out[7:3]`: upper five bits of the recovered audio level
* `uio_out[6:0]`: selected AM channel number

For simulation, run the Cocotb tests in the `test` directory. The basic test checks reset behavior, comparator feedback, CIC sample timing, rotary encoder tuning, the 810 kHz home function, and muted PWM duty cycle.

The AM demodulation test generates a virtual 810 kHz AM signal carrying a 1 kHz audio tone. It converts the simulated RF waveform into a 1-bit comparator stream and checks whether the recovered audio contains a dominant 1 kHz component.

For hardware testing, first use a known AM-modulated signal source rather than an antenna. Apply an 810 kHz carrier modulated by a 1 kHz tone to the external RF amplifier and comparator circuit. Pass `uo_out[1]` through an RC low-pass filter and an audio amplifier, then observe the recovered signal with an oscilloscope or speaker.

## External hardware

The following external hardware is required for real radio reception:

* AM antenna or ferrite-bar antenna
* AM-band input filter or tuning network
* RF amplifier
* High-speed comparator operating at the appropriate I/O voltage
* Comparator feedback RC network
* Rotary encoder
* PWM reconstruction low-pass filter
* Audio amplifier
* Speaker or headphones with a suitable amplifier

The Tiny Tapeout output must not drive a speaker directly.
