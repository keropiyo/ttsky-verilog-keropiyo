# SPDX-FileCopyrightText: 2026 keropiyo
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge


CLOCK_PERIOD_NS = 20  # 50 MHz


def signal_value(signal) -> int:
    """Read a cocotb signal as a normal Python integer."""
    return int(signal.value)


def set_input_bit(dut, bit_number: int, enabled: bool) -> None:
    """Change one ui_in bit without changing the other input bits."""
    value = signal_value(dut.ui_in)

    if enabled:
        value |= 1 << bit_number
    else:
        value &= ~(1 << bit_number)

    dut.ui_in.value = value


async def drive_encoder_state(dut, a: int, b: int) -> None:
    """
    Hold one rotary-encoder state long enough to pass through
    the two-stage input synchronizers.
    """
    value = signal_value(dut.ui_in)
    value &= ~((1 << 1) | (1 << 2))
    value |= (a & 1) << 1
    value |= (b & 1) << 2
    dut.ui_in.value = value

    await ClockCycles(dut.clk, 5)


async def rotate_one_step_up(dut) -> None:
    """00 -> 01 -> 11 -> 10 -> 00: increase by one 9 kHz channel."""
    for a, b in ((0, 1), (1, 1), (1, 0), (0, 0)):
        await drive_encoder_state(dut, a, b)


async def rotate_one_step_down(dut) -> None:
    """00 -> 10 -> 11 -> 01 -> 00: decrease by one 9 kHz channel."""
    for a, b in ((1, 0), (1, 1), (0, 1), (0, 0)):
        await drive_encoder_state(dut, a, b)


@cocotb.test()
async def test_keropiyo_am_radio(dut):
    """Check the basic controls and timing of the AM radio core."""

    dut._log.info("Starting 50 MHz clock")
    clock = Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    # ------------------------------------------------------------
    # Reset
    # ------------------------------------------------------------
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 10)

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    # The bidirectional pins are configured as outputs.
    assert signal_value(dut.uio_oe) == 0xFF

    # Reset/home frequency is 810 kHz.
    # Channel number = (810 - 531) / 9 = 31.
    assert signal_value(dut.uio_out) == 31

    # ------------------------------------------------------------
    # Comparator feedback
    # ui_in[0] should appear at uo_out[0] after synchronization.
    # ------------------------------------------------------------
    dut._log.info("Checking comparator feedback")

    set_input_bit(dut, 0, True)
    await ClockCycles(dut.clk, 4)
    assert signal_value(dut.uo_out) & 0x01

    set_input_bit(dut, 0, False)
    await ClockCycles(dut.clk, 4)
    assert (signal_value(dut.uo_out) & 0x01) == 0

    # ------------------------------------------------------------
    # CIC sample tick
    # DECIM_BITS=9 means one pulse every 512 clock cycles.
    # Therefore 1024 cycles must contain exactly two pulses.
    # ------------------------------------------------------------
    dut._log.info("Checking CIC sample timing")

    sample_tick_count = 0

    for _ in range(1024):
        await FallingEdge(dut.clk)

        if signal_value(dut.uo_out) & 0x04:
            sample_tick_count += 1

    assert sample_tick_count == 2

    # ------------------------------------------------------------
    # Rotary encoder tuning
    # ------------------------------------------------------------
    dut._log.info("Checking rotary encoder tuning")

    await rotate_one_step_up(dut)
    assert signal_value(dut.uio_out) == 32  # 819 kHz

    await rotate_one_step_down(dut)
    assert signal_value(dut.uio_out) == 31  # back to 810 kHz

    await rotate_one_step_up(dut)
    await rotate_one_step_up(dut)
    assert signal_value(dut.uio_out) == 33  # 828 kHz

    # ------------------------------------------------------------
    # Home input
    # ui_in[4] returns tuning to 810 kHz/channel 31.
    # ------------------------------------------------------------
    dut._log.info("Checking tuning home input")

    set_input_bit(dut, 4, True)
    await ClockCycles(dut.clk, 5)

    set_input_bit(dut, 4, False)
    await ClockCycles(dut.clk, 5)

    assert signal_value(dut.uio_out) == 31

    # ------------------------------------------------------------
    # Muted PWM
    # Mute produces a constant 50% duty-cycle PWM level.
    # Across one full 8-bit PWM period, 128 of 256 samples are high.
    # ------------------------------------------------------------
    dut._log.info("Checking muted PWM duty cycle")

    set_input_bit(dut, 3, True)
    await ClockCycles(dut.clk, 5)

    pwm_high_count = 0

    for _ in range(256):
        await FallingEdge(dut.clk)

        if signal_value(dut.uo_out) & 0x02:
            pwm_high_count += 1

    assert pwm_high_count == 128

    dut._log.info("All basic AM radio tests passed")
