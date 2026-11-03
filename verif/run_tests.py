"""Run the UART regression using cocotb 2.0.x and NVC.

"""

import argparse
import os
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET

from cocotb_tools.runner import get_runner


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rtl-dir", type=Path, required=True)
    parser.add_argument("--clock-hz", type=int, default=100_000_000)
    parser.add_argument("--baud", type=int, default=115_200)
    parser.add_argument("--filter", help="Regex selecting cocotb test names")
    parser.add_argument("--waves", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    rtl = args.rtl_dir.resolve()
    names = ["telemetry_pkg.vhd", "uart_rx.vhd", "uart_tx.vhd", "uart_top.vhd"]
    sources = [rtl / name for name in names]
    missing = [str(path) for path in sources if not path.is_file()]
    if missing:
        parser.error("Missing VHDL sources:\n" + "\n".join(missing))
    if shutil.which("ghdl") is None:
        parser.error("GHDL is not on PATH. Install GHDL before running this VHDL DUT.")
    if args.clock_hz // args.baud < 4:
        parser.error("This receiver test requires at least four FPGA clocks per UART bit.")
    if args.clock_hz != 100_000_000:
        parser.error("This regression intentionally targets the board's 100 MHz clock.")
    os.environ["UART_CLOCK_HZ"] = str(args.clock_hz)
    os.environ["UART_BAUD"] = str(args.baud)
    runner = get_runner("ghdl")
    build = root / "sim_build"
    runner.build(
        sources=sources,
        hdl_toplevel="uart_top",
        hdl_library="work",
        build_args=["--std=08"],
        build_dir=build,
        always=True,
        waves=args.waves,
    )
    results = runner.test(
        hdl_toplevel="uart_top",
        hdl_toplevel_library="work",
        hdl_toplevel_lang="vhdl",
        test_module="test_uart_top",
        test_dir=root,
        build_dir=build,
        test_args=["--std=08", f"--workdir={build}"],
        parameters={"G_CLK_FREQ": args.clock_hz, "G_BAUD_RATE": args.baud},
        extra_env={"UART_CLOCK_HZ": str(args.clock_hz), "UART_BAUD": str(args.baud)},
        test_filter=args.filter,
        waves=args.waves,
        results_xml=str(root / "results.xml"),
    )
    # Standalone runners must propagate regression failures to the shell.
    cases = list(ET.parse(results).getroot().iter("testcase"))
    executed = [case for case in cases if case.find("skipped") is None]
    if not executed:
        raise SystemExit("No cocotb tests ran. Check --filter and simulator output.")
    failed = [case for case in cases if case.find("failure") is not None
              or case.find("error") is not None]
    if failed:
        raise SystemExit(f"{len(failed)}/{len(executed)} tests failed; see {results}")
    print(f"All {len(executed)} executed UART tests passed. Results: {results}")


if __name__ == "__main__":
    main()
