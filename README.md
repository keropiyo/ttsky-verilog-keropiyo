![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)


# Keropiyo Tiny AM Radio

[![GDS](https://github.com/keropiyo/ttsky-verilog-keropiyo/actions/workflows/gds.yaml/badge.svg)](https://github.com/keropiyo/ttsky-verilog-keropiyo/actions/workflows/gds.yaml)
[![Tests](https://github.com/keropiyo/ttsky-verilog-keropiyo/actions/workflows/test.yaml/badge.svg)](https://github.com/keropiyo/ttsky-verilog-keropiyo/actions/workflows/test.yaml)
[![Docs](https://github.com/keropiyo/ttsky-verilog-keropiyo/actions/workflows/docs.yaml/badge.svg)](https://github.com/keropiyo/ttsky-verilog-keropiyo/actions/workflows/docs.yaml)

A 1-bit software-defined AM radio receiver implemented in Verilog for Tiny Tapeout.

This project digitally performs AM station tuning, quadrature mixing, filtering, envelope detection, audio recovery, and PWM generation.

> This is an experimental and educational radio design.
> The digital circuit has passed synthesis, GDS generation, Precheck, Viewer generation, RTL tests, and gate-level tests. Real radio reception with an antenna and external analog circuit has not yet been tested.

## Features

* 50 MHz system clock
* Japanese medium-wave AM band support
* Tuning range from 531 kHz to 1602 kHz
* 9 kHz channel spacing
* Default frequency of 810 kHz
* Rotary encoder station selection
* 32-bit numerically controlled oscillator
* I/Q quadrature mixer
* Two-stage CIC filter and decimator
* Approximate AM envelope detector
* DC carrier removal
* 8-bit recovered audio level
* PWM audio output
* Mute and tuning-home inputs

## Block diagram

```text
AM antenna
    |
    v
Input tuning network / RF amplifier
    |
    v
High-speed comparator and feedback RC network
    |
    | 1-bit RF stream
    v
+----------------------------------------+
| Keropiyo Tiny AM Radio                 |
|                                        |
|  32-bit NCO                            |
|      |                                 |
|      v                                 |
|  I/Q mixer                             |
|      |                                 |
|      v                                 |
|  Two-stage CIC filter                  |
|      |                                 |
|      v                                 |
|  Envelope detector: abs(I) + abs(Q)    |
|      |                                 |
|      v                                 |
|  DC removal and audio scaling          |
|      |                                 |
|      v                                 |
|  PWM audio generator                   |
+----------------------------------------+
    |
    v
External RC low-pass filter
    |
    v
Audio amplifier
    |
    v
Speaker
```

## How it works

The external analog front end receives and amplifies an AM radio signal. A high-speed comparator converts the analog RF waveform into a 1-bit digital stream connected to `ui_in[0]`.

Inside the Tiny Tapeout design, a 32-bit numerically controlled oscillator generates the selected local oscillator frequency.

The 1-bit input is mixed with two square-wave local oscillator signals with a quadrature phase relationship. This produces I and Q baseband signals.

A two-stage CIC filter performs low-pass filtering and decimates the 50 MHz input stream to approximately 97.7 ksample/s.

The AM envelope is approximated using:

```text
abs(I) + abs(Q)
```

A slow DC estimate is subtracted from the envelope to remove the carrier component and recover the audio modulation.

The recovered audio level is converted into a PWM signal on `uo_out[1]`. An external RC low-pass filter and audio amplifier are required to convert the PWM signal into audible sound.

## Tuning

The receiver starts at 810 kHz after reset.

A rotary encoder connected to `ENC_A` and `ENC_B` changes the selected station in 9 kHz steps.

```text
531 kHz
540 kHz
549 kHz
...
810 kHz
819 kHz
828 kHz
...
1602 kHz
```

The `TUNE_HOME` input returns the receiver to 810 kHz.

## Pinout

### Dedicated inputs

| Pin          | Name        | Description                                   |
| ------------ | ----------- | --------------------------------------------- |
| `ui_in[0]`   | `COMP_IN`   | Input from the external high-speed comparator |
| `ui_in[1]`   | `ENC_A`     | Rotary encoder A phase                        |
| `ui_in[2]`   | `ENC_B`     | Rotary encoder B phase                        |
| `ui_in[3]`   | `MUTE`      | Mutes the recovered audio                     |
| `ui_in[4]`   | `TUNE_HOME` | Returns tuning to 810 kHz                     |
| `ui_in[7:5]` | —           | Unused                                        |

### Dedicated outputs

| Pin           | Name          | Description                                   |
| ------------- | ------------- | --------------------------------------------- |
| `uo_out[0]`   | `COMP_OUT`    | Feedback output for the comparator RC network |
| `uo_out[1]`   | `PWM_AUDIO`   | PWM audio output                              |
| `uo_out[2]`   | `SAMPLE_TICK` | CIC output sample timing pulse                |
| `uo_out[7:3]` | `AUDIO_LEVEL` | Upper five bits of the recovered audio level  |

### Bidirectional outputs

| Pins           | Name      | Description                      |
| -------------- | --------- | -------------------------------- |
| `uio_out[6:0]` | `CHANNEL` | Selected 9 kHz AM channel number |
| `uio_out[7]`   | —         | Unused                           |

The bidirectional pins are configured as outputs.

## Channel number

The displayed channel number is calculated from the selected frequency:

```text
channel = (frequency_kHz - 531) / 9
```

For example:

```text
810 kHz -> channel 31
819 kHz -> channel 32
828 kHz -> channel 33
```

## Simulation

The project uses Cocotb and Icarus Verilog.

Two tests are included.

### Basic control test

`test/test.py` checks:

* Reset behavior
* Default 810 kHz tuning
* Comparator feedback
* CIC sample timing
* Rotary encoder tuning
* Tuning-home operation
* Muted PWM duty cycle

### AM demodulation test

`test/test_am.py` creates a virtual AM transmission with:

* 810 kHz carrier
* 1 kHz audio tone
* Dithered 1-bit comparator input
* 50 MHz sample clock

The test verifies that the recovered audio contains a dominant 1 kHz component.

The AM demodulation test has passed both RTL simulation and gate-level simulation.

## Build status

The current design has successfully completed:

* Verilog linting
* Logic synthesis
* Placement and routing
* GDS generation
* GDS Viewer generation
* Tiny Tapeout Precheck
* RTL Cocotb tests
* Gate-level Cocotb tests
* Simulated 810 kHz AM demodulation
* Simulated 1 kHz audio recovery

The design currently uses a `2x2` Tiny Tapeout tile area.

## External hardware

Real AM radio reception requires an external PCB containing:

* AM antenna or ferrite-bar antenna
* AM-band filter or tuning network
* RF amplifier
* High-speed comparator
* Comparator feedback RC network
* Rotary encoder
* PWM reconstruction filter
* Audio amplifier
* Speaker or suitably amplified headphones

The Tiny Tapeout output pin must not drive a speaker directly.

## Current limitations

* Real antenna reception has not yet been tested
* External comparator and RC values have not yet been finalized
* Adjacent-channel rejection requires hardware evaluation
* RF gain and noise performance require measurement
* Automatic gain control is not yet implemented
* Audio quality requires real PCB testing and adjustment

## Next steps

1. Verify the design on an FPGA
2. Generate a known 810 kHz AM test signal
3. Build the comparator and feedback RC circuit
4. Observe the recovered PWM audio with an oscilloscope
5. Add an RC reconstruction filter and audio amplifier
6. Test reception using an antenna
7. Optimize the design to reduce tile usage

## 日本語概要

Keropiyo Tiny AM Radioは、Verilogで作った1bit方式のデジタルAMラジオ受信回路です。

外付けのアンテナ、RFアンプ、高速コンパレータから入力された1bit信号を使い、Tiny Tapeout内部で選局、I/Q変換、CICフィルタ、AM包絡線検波、音声復元、PWM生成を行います。

現在は、810kHzの搬送波を1kHzの音声で変調した仮想AM信号を使い、RTLシミュレーションとゲートレベルシミュレーションの両方で音声復調に成功しています。

GDS生成、Viewer、Precheckも完了しています。

実際のAM放送受信には、アンテナ、RFアンプ、高速コンパレータ、RCフィルタ、音声アンプなどを搭載した外付けPCBが必要です。

## License

This project is licensed under the Apache License 2.0.
