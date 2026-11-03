"""Serial-pin tests for uart_top. Target: cocotb 2.0.x.

No internal FSM signals are forced or read. The bench acts as the PC UART:
it drives i_rx, independently decodes o_tx, and checks o_display_mode.
Run with run_tests.py; do not instantiate uart_rx_tb.vhd.
"""

import os

import cocotb
from cocotb.clock import Clock
from cocotb.queue import Queue
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge, Timer, with_timeout


CLOCK_HZ = int(os.getenv("UART_CLOCK_HZ", "100000000"))
BAUD = int(os.getenv("UART_BAUD", "115200"))
CLOCK_PS = round(1_000_000_000_000 / CLOCK_HZ)
# Use the PC's nominal baud, independently of the DUT's truncated divider.
BIT_PS = round(1_000_000_000_000 / BAUD)

VOLTAGE_REPLY = b"Showing Voltage!\r\n"
CURRENT_REPLY = b"Showing Current!\r\n"
ERROR_REPLY = b"ERROR: Use either 'v' or 'i'!\r\n"

# telemetry_pkg: type t_display_mode is (SHOW_VOLTAGE, SHOW_CURRENT).
SHOW_VOLTAGE = 0
SHOW_CURRENT = 1


class UartBench:
    """One PC-side input driver and one continuously running output monitor."""

    def __init__(self, dut):
        self.dut = dut
        self.received = Queue()
        self.monitor_task = None

    async def start(self):
        self.dut.i_rst_n.value = 0
        self.dut.i_rx.value = 1
        cocotb.start_soon(Clock(self.dut.i_clk, CLOCK_PS, unit="ps").start())
        await self.reset()
        return self

    def mode(self):
        """Read an enum exposed as an ordinal or a named VHDL value."""
        value = self.dut.o_display_mode.value
        spelling = str(value).upper()
        if "SHOW_VOLTAGE" in spelling:
            return SHOW_VOLTAGE
        if "SHOW_CURRENT" in spelling:
            return SHOW_CURRENT
        return int(value)

    async def reset(self):
        # End any partial PC-side decode before aborting the hardware frame.
        if self.monitor_task is not None:
            self.monitor_task.cancel()
        await FallingEdge(self.dut.i_clk)
        self.dut.i_rst_n.value = 0
        self.dut.i_rx.value = 1
        for _ in range(5):
            await RisingEdge(self.dut.i_clk)
        await ReadOnly()
        assert int(self.dut.o_tx.value) == 1, "TX must idle high during reset"
        assert self.mode() == SHOW_VOLTAGE, "Reset must select voltage mode"
        await FallingEdge(self.dut.i_clk)
        self.dut.i_rst_n.value = 1
        await RisingEdge(self.dut.i_clk)
        await ReadOnly()
        assert int(self.dut.o_tx.value) == 1
        assert self.mode() == SHOW_VOLTAGE
        self.received = Queue()
        self.monitor_task = cocotb.start_soon(self._monitor_tx())
        # Return in a writable phase; callers may now drive stimulus.
        await FallingEdge(self.dut.i_clk)

    async def _monitor_tx(self):
        """Independent 8N1 UART receiver, sampling near bit midpoints."""
        while True:
            await FallingEdge(self.dut.o_tx)
            await Timer(BIT_PS // 2, unit="ps")
            await ReadOnly()
            assert int(self.dut.o_tx.value) == 0, "TX start bit is too short"
            value = 0
            for bit in range(8):
                await Timer(BIT_PS, unit="ps")
                await ReadOnly()
                value |= int(self.dut.o_tx.value) << bit
            await Timer(BIT_PS, unit="ps")
            await ReadOnly()
            assert int(self.dut.o_tx.value) == 1, (
                f"Missing/high-invalid TX stop bit after byte 0x{value:02x}"
            )
            self.received.put_nowait(value)
            # Finish the stop period before listening for another start edge.
            await Timer(BIT_PS - BIT_PS // 2, unit="ps")

    async def send_byte(self, value, *, good_stop=True, baud_scale=1.0):
        """Drive a UART frame, LSB first, away from FPGA rising edges.

        baud_scale > 1 means the PC transmitter is faster than nominal.
        """
        assert 0 <= value <= 255
        period = round(BIT_PS / baud_scale)
        await FallingEdge(self.dut.i_clk)
        await Timer(CLOCK_PS // 4, unit="ps")
        self.dut.i_rx.value = 0
        await Timer(period, unit="ps")
        for bit in range(8):
            self.dut.i_rx.value = (value >> bit) & 1
            await Timer(period, unit="ps")
        self.dut.i_rx.value = int(good_stop)
        await Timer(period, unit="ps")
        self.dut.i_rx.value = 1
        if not good_stop:
            # Give the receiver an unambiguous idle interval to recover.
            await Timer(2 * BIT_PS, unit="ps")

    async def next_tx_byte(self):
        # A timeout turns a stuck handshake into a useful assertion failure.
        return await with_timeout(self.received.get(), 20 * BIT_PS, "ps")

    async def expect_reply(self, expected):
        actual = bytearray()
        for index, wanted in enumerate(expected):
            actual.append(await self.next_tx_byte())
            assert actual[-1] == wanted, (
                f"Reply byte {index}: expected 0x{wanted:02x}, "
                f"got 0x{actual[-1]:02x}; received {bytes(actual)!r}"
            )
        assert bytes(actual) == expected
        self.dut._log.info("Received reply: %r", bytes(actual))
        # Also catch duplicate or extra output after the expected last byte.
        await self.expect_quiet()

    async def expect_quiet(self, bit_periods=12):
        await Timer(bit_periods * BIT_PS, unit="ps")
        await ReadOnly()
        assert self.received.empty(), "Unexpected or duplicate reply byte"
        assert int(self.dut.o_tx.value) == 1, "TX must return to idle high"
        await FallingEdge(self.dut.i_clk)


@cocotb.test(timeout_time=5, timeout_unit="ms")
async def reset_and_enter_are_quiet(dut):
    bench = await UartBench(dut).start()
    await bench.expect_quiet()
    for byte in b"\r\n":
        await bench.send_byte(byte)
        await bench.expect_quiet()
        assert bench.mode() == SHOW_VOLTAGE


@cocotb.test(timeout_time=15, timeout_unit="ms")
async def commands_reply_in_full_and_repeat(dut):
    bench = await UartBench(dut).start()
    for command, reply, mode in [
        (b"i", CURRENT_REPLY, SHOW_CURRENT),
        (b"v", VOLTAGE_REPLY, SHOW_VOLTAGE),
        (b"v", VOLTAGE_REPLY, SHOW_VOLTAGE),
        (b"i", CURRENT_REPLY, SHOW_CURRENT),
    ]:
        await bench.send_byte(command[0])
        await bench.expect_reply(reply)
        assert bench.mode() == mode


@cocotb.test(timeout_time=20, timeout_unit="ms")
async def unknown_commands_reply_without_changing_mode(dut):
    bench = await UartBench(dut).start()
    await bench.send_byte(ord("i"))
    await bench.expect_reply(CURRENT_REPLY)
    # Uppercase is deliberately not accepted by the current case statement.
    for value in [ord("x"), ord("V"), 0x00, 0xFF]:
        await bench.send_byte(value)
        await bench.expect_reply(ERROR_REPLY)
        assert bench.mode() == SHOW_CURRENT
    # After the longer error string, a short reply must restart at index 1.
    await bench.send_byte(ord("v"))
    await bench.expect_reply(VOLTAGE_REPLY)
    assert bench.mode() == SHOW_VOLTAGE


@cocotb.test(timeout_time=10, timeout_unit="ms")
async def command_during_reply_is_ignored_by_current_design(dut):
    bench = await UartBench(dut).start()
    await bench.send_byte(ord("i"))
    # Seeing the first character proves the reply is already in progress.
    assert await bench.next_tx_byte() == CURRENT_REPLY[0]
    await bench.send_byte(ord("v"))
    await bench.expect_reply(CURRENT_REPLY[1:])
    assert bench.mode() == SHOW_CURRENT
    # Ignored commands are not queued and must not appear after the reply.
    await bench.expect_quiet(30)
    await bench.send_byte(ord("v"))
    await bench.expect_reply(VOLTAGE_REPLY)
    assert bench.mode() == SHOW_VOLTAGE


@cocotb.test(timeout_time=10, timeout_unit="ms")
async def reset_aborts_a_reply_and_allows_a_new_command(dut):
    bench = await UartBench(dut).start()
    await bench.send_byte(ord("i"))
    assert await bench.next_tx_byte() == CURRENT_REPLY[0]
    # Abort in the middle of the second output character.
    await Timer(3 * BIT_PS, unit="ps")
    await bench.reset()
    await bench.expect_quiet()
    await bench.send_byte(ord("v"))
    await bench.expect_reply(VOLTAGE_REPLY)
    assert bench.mode() == SHOW_VOLTAGE


@cocotb.test(timeout_time=10, timeout_unit="ms")
async def short_glitch_and_bad_stop_do_not_launch_a_reply(dut):
    bench = await UartBench(dut).start()
    await FallingEdge(dut.i_clk)
    dut.i_rx.value = 0
    await Timer(BIT_PS // 4, unit="ps")
    dut.i_rx.value = 1
    await bench.expect_quiet(15)
    await bench.send_byte(ord("i"), good_stop=False)
    await bench.expect_quiet(15)
    assert bench.mode() == SHOW_VOLTAGE
    await bench.send_byte(ord("i"))
    await bench.expect_reply(CURRENT_REPLY)
    assert bench.mode() == SHOW_CURRENT


@cocotb.test(timeout_time=10, timeout_unit="ms")
async def modest_pc_baud_mismatch_is_tolerated(dut):
    bench = await UartBench(dut).start()
    for scale, command, reply, mode in [
        (0.99, ord("i"), CURRENT_REPLY, SHOW_CURRENT),
        (1.01, ord("v"), VOLTAGE_REPLY, SHOW_VOLTAGE),
    ]:
        await bench.send_byte(command, baud_scale=scale)
        await bench.expect_reply(reply)
        assert bench.mode() == mode
