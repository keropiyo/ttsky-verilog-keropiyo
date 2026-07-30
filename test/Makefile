# SPDX-FileCopyrightText: 2026 keropiyo
# SPDX-License-Identifier: Apache-2.0

"""
AM demodulation test for Keropiyo Tiny AM Radio.

This test creates a virtual 810 kHz AM broadcast carrying a 1 kHz tone.
The analog front end is approximated by adding deterministic dither and
converting the RF waveform to one bit, as an external comparator would.

The Verilog core must recover a strong 1 kHz component in its audio output.
No NumPy or SciPy is required.
"""

import csv
import json
import math
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge


CLOCK_HZ = 50_000_000
CLOCK_PERIOD_NS = 20

CARRIER_HZ = 810_000
AUDIO_HZ = 1_000

# 300,000 clocks = 6 ms at 50 MHz.
# The first half is discarded while the CIC and DC estimator settle.
TOTAL_CLOCKS = 300_000
WARMUP_CLOCKS = TOTAL_CLOCKS // 2

# The CIC emits one audio sample every 512 clocks.
AUDIO_SAMPLE_HZ = CLOCK_HZ / 512.0

OUTPUT_DIR = Path("output")


def signal_value(signal) -> int:
    """Read a cocotb signal as a Python integer."""
    return int(signal.value)


def set_comparator_input(dut, bit: int) -> None:
    """Set ui_in[0], leaving all other controls low."""
    dut.ui_in.value = bit & 1


def xorshift32(state: int) -> int:
    """Small deterministic pseudo-random generator for repeatable dither."""
    state ^= (state << 13) & 0xFFFFFFFF
    state ^= state >> 17
    state ^= (state << 5) & 0xFFFFFFFF
    return state & 0xFFFFFFFF


def tone_amplitude(samples: list[float], frequency_hz: float) -> float:
    """
    Measure one frequency using sine/cosine correlation.

    The phase is not assumed, so the sine and cosine terms are combined.
    """
    if not samples:
        return 0.0

    mean_value = sum(samples) / len(samples)
    cosine_sum = 0.0
    sine_sum = 0.0

    for index, sample in enumerate(samples):
        centered = sample - mean_value
        angle = 2.0 * math.pi * frequency_hz * index / AUDIO_SAMPLE_HZ
        cosine_sum += centered * math.cos(angle)
        sine_sum += centered * math.sin(angle)

    return 2.0 * math.hypot(cosine_sum, sine_sum) / len(samples)


def write_results(
    samples: list[int],
    target_amplitude: float,
    reference_amplitudes: dict[int, float],
) -> None:
    """Save samples and measurements as GitHub Actions artifacts."""
    OUTPUT_DIR.mkdir(exist_ok=True)

    with (OUTPUT_DIR / "am_audio_samples.csv").open(
        "w", newline="", encoding="utf-8"
    ) as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(("sample", "time_seconds", "audio_level"))
        for index, sample in enumerate(samples):
            writer.writerow((index, index / AUDIO_SAMPLE_HZ, sample))

    metrics = {
        "carrier_hz": CARRIER_HZ,
        "expected_audio_hz": AUDIO_HZ,
        "clock_hz": CLOCK_HZ,
        "audio_sample_hz": AUDIO_SAMPLE_HZ,
        "analyzed_samples": len(samples),
        "target_amplitude": target_amplitude,
        "reference_amplitudes": reference_amplitudes,
    }

    with (OUTPUT_DIR / "am_demod_metrics.json").open(
        "w", encoding="utf-8"
    ) as json_file:
        json.dump(metrics, json_file, indent=2)


@cocotb.test()
async def test_am_demodulates_1khz_tone(dut):
    """
    Feed a dithered 1-bit 810 kHz AM signal and detect the recovered 1 kHz tone.
    """

    dut._log.info("Starting Keropiyo AM demodulation simulation")
    dut._log.info(
        "Input: %d kHz carrier, %d kHz audio tone",
        CARRIER_HZ // 1_000,
        AUDIO_HZ // 1_000,
    )

    clock = Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset at the default/home station of 810 kHz.
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 10)

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    assert signal_value(dut.uio_out) == 31, (
        "The receiver did not start at channel 31 / 810 kHz"
    )

    # Start immediately after a falling edge so each generated bit is stable
    # before the following rising edge.
    await FallingEdge(dut.clk)

    random_state = 0x12345678
    audio_samples: list[int] = []

    for clock_index in range(TOTAL_CLOCKS):
        time_seconds = clock_index / CLOCK_HZ

        # AM envelope ranges from 0.4 to 1.0.
        audio_tone = math.sin(
            2.0 * math.pi * AUDIO_HZ * time_seconds
        )
        envelope = 0.70 + 0.30 * audio_tone

        rf_wave = envelope * math.cos(
            2.0 * math.pi * CARRIER_HZ * time_seconds
        )

        # A hard zero-crossing comparator alone discards amplitude.
        # Deterministic dither makes the one-bit density carry amplitude
        # information, approximating a noisy oversampled comparator front end.
        random_state = xorshift32(random_state)
        dither = (
            (random_state / 4_294_967_296.0) * 2.0 - 1.0
        )

        comparator_bit = 1 if (rf_wave + dither) >= 0.0 else 0
        set_comparator_input(dut, comparator_bit)

        await FallingEdge(dut.clk)

        # uo_out[2] is asserted for one clock for every CIC output sample.
        if (
            clock_index >= WARMUP_CLOCKS
            and (signal_value(dut.uo_out) & 0x04)
        ):
            # uo_out[7:3] exposes the upper five bits of audio_level.
            audio_level = signal_value(dut.uo_out) & 0xF8
            audio_samples.append(audio_level)

    assert len(audio_samples) >= 250, (
        f"Too few audio samples collected: {len(audio_samples)}"
    )

    target_amplitude = tone_amplitude(audio_samples, AUDIO_HZ)

    # Use frequencies away from the expected tone and its strongest harmonic.
    reference_frequencies = (400, 1_400, 2_400, 3_200)
    reference_amplitudes = {
        frequency: tone_amplitude(audio_samples, frequency)
        for frequency in reference_frequencies
    }
    reference_mean = (
        sum(reference_amplitudes.values())
        / len(reference_amplitudes)
    )

    write_results(
        audio_samples,
        target_amplitude,
        reference_amplitudes,
    )

    dut._log.info(
        "Recovered 1 kHz amplitude: %.3f",
        target_amplitude,
    )
    dut._log.info(
        "Reference-frequency mean amplitude: %.3f",
        reference_mean,
    )
    dut._log.info(
        "Tone/reference ratio: %.2f",
        target_amplitude / max(reference_mean, 1.0e-9),
    )

    # These limits are deliberately generous. They verify that a real,
    # dominant 1 kHz component is present without overfitting analog details.
    assert target_amplitude > 20.0, (
        "Recovered 1 kHz tone is too weak: "
        f"{target_amplitude:.3f}"
    )
    assert target_amplitude > 4.0 * reference_mean, (
        "The recovered audio is not dominated by the expected 1 kHz tone: "
        f"target={target_amplitude:.3f}, references={reference_mean:.3f}"
    )

    dut._log.info("AM demodulation test passed")
