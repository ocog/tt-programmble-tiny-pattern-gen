# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

BAUD_RATE     = 9600
BIT_PERIOD_NS = round(1_000_000_000 / 9600)  # = 104167 ns
# Must match pattern_player.v (CLK_FREQ / PLAY_RATE_HZ) and the RAM
# depth in ram_256x8.v / pattern_player.v.
PLAY_DIVISOR = 10_000
RAM_DEPTH    = 64

# ui_in bit positions
RX_BIT   = 0   # UART RX (idle high)
MODE_BIT = 1   # 0 = DAC, 1 = PWM
LOAD_BIT = 2   # assert high to leave LOAD state and enter PLAY state


async def uart_send_byte(dut, byte):
    """Bit-bang one 8N1 UART byte (LSB first) onto ui_in[0]."""
    # Start bit (low)
    dut.ui_in.value = int(dut.ui_in.value) & 0xFE
    await Timer(BIT_PERIOD_NS, units="ns")

    for i in range(8):
        bit = (byte >> i) & 1
        cur = int(dut.ui_in.value)
        if bit:
            dut.ui_in.value = cur | 0x01
        else:
            dut.ui_in.value = cur & 0xFE
        await Timer(BIT_PERIOD_NS, units="ns")

    # Stop bit (high)
    dut.ui_in.value = int(dut.ui_in.value) | 0x01
    await Timer(BIT_PERIOD_NS, units="ns")


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # 100 ns period -> 10 MHz system clock
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    # Reset
    # ui_in[0]=1 (UART RX idle high), ui_in[1]=0 (DAC mode), ui_in[2]=0 (LOAD low)
    dut._log.info("Reset")
    dut.ena.value    = 1
    dut.ui_in.value  = 0x01   # 0b0000_0001
    dut.uio_in.value = 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value  = 1

    # ------------------------------------------------------------------
    # INIT state
    # The FSM spends 64 clock cycles zero-initialising RAM before moving
    # to LOAD.  uo_out must be 0x00 throughout (play_en is de-asserted).
    # ------------------------------------------------------------------
    dut._log.info("INIT state: verifying uo_out is muted")
    await ClockCycles(dut.clk, 5)
    assert int(dut.uo_out.value) == 0x00, \
        f"uo_out not muted during INIT (got {int(dut.uo_out.value):#04x})"

    # Wait well past the 64-cycle INIT window before touching UART.
    await ClockCycles(dut.clk, 70)

    # ------------------------------------------------------------------
    # LOAD state
    # INIT is complete; chip is now in LOAD.  uo_out stays muted.
    # Send RAM_DEPTH bytes over UART while LOAD pin remains low.
    # RAM[i] = i after this loop.
    # ------------------------------------------------------------------
    dut._log.info("LOAD state: verifying uo_out still muted on LOAD entry")
    assert int(dut.uo_out.value) == 0x00, \
        f"uo_out not muted on entry to LOAD (got {int(dut.uo_out.value):#04x})"

    dut._log.info("LOAD state: filling RAM with 0x00-0x3F over UART")
    for i in range(RAM_DEPTH):
        await uart_send_byte(dut, i)
    await ClockCycles(dut.clk, 5)

    assert int(dut.uo_out.value) == 0x00, \
        f"uo_out not muted during LOAD (got {int(dut.uo_out.value):#04x})"

    # ------------------------------------------------------------------
    # Transition to PLAY
    # Assert ui_in[2] (LOAD pin) high to move the FSM from LOAD -> PLAY.
    # ------------------------------------------------------------------
    dut._log.info("Asserting LOAD pin -> entering PLAY state")
    dut.ui_in.value = int(dut.ui_in.value) | (1 << LOAD_BIT)
    await ClockCycles(dut.clk, 2)

    # ------------------------------------------------------------------
    # PLAY state — DAC mode
    # uo_out now reflects RAM playback.  Sample over one full loop and
    # confirm the loaded values appear and the output is not constant.
    # ------------------------------------------------------------------
    dut._log.info("PLAY state: sampling uo_out over one full playback loop")
    samples = set()
    for _ in range(RAM_DEPTH + 1):
        try:
            samples.add(int(dut.uo_out.value))
        except ValueError:
            pass  # skip uninitialized X values
        await ClockCycles(dut.clk, PLAY_DIVISOR)

    assert (RAM_DEPTH - 1) in samples, \
        f"last RAM byte (0x{RAM_DEPTH - 1:02x}) never appeared on uo_out"
    assert len(samples) > 1, "uo_out is stuck at a single value in PLAY/DAC mode"

    # ------------------------------------------------------------------
    # PLAY state — PWM mode
    # Switch ui_in[1] high; the shared 8-bit PWM counter should make
    # uo_out toggle within one 256-cycle counter period.
    # ------------------------------------------------------------------
    dut._log.info("Switching to PWM mode")
    dut.ui_in.value = int(dut.ui_in.value) | (1 << MODE_BIT)
    await ClockCycles(dut.clk, 2)

    pwm_initial = int(dut.uo_out.value)
    toggled = False
    for _ in range(300):
        await ClockCycles(dut.clk, 1)
        if int(dut.uo_out.value) != pwm_initial:
            toggled = True
            break

    assert toggled, "uo_out did not toggle in PWM mode"
