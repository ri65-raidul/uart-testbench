#!/usr/bin/env python3
"""
coverage_sweep.py
-----------------
Cumulative coverage sweep: merge tests 1..k for k = 1..N with urg,
record DUT-only code coverage (from hierarchy.txt, the 'dut' instance
subtree) plus functional GROUP coverage for each k, write a CSV, and plot it.

Run from the build/ folder AFTER `make coverage` (so the .vdb holds
every test, each saved under -cm_name uart_test_<N>):

    python3 coverage_sweep.py
    python3 coverage_sweep.py --tests 11 --vdb simv_uart_test_top_RTL.vdb

Outputs:
    coverage_sweep.csv   one row per k
    coverage_sweep.png   line plot (only if matplotlib is installed)
"""

import argparse
import csv
import os
import re
import subprocess
import sys

METRICS = ["SCORE", "LINE", "COND", "TOGGLE", "FSM", "BRANCH", "GROUP"]


def test_name(vdb, n):
    # Tests are stored as <simv name>/<cm_name> inside the .vdb.
    # Check the "tests" page of an existing urg report if this differs.
    simv = os.path.basename(vdb).replace(".vdb", "")
    return f"{simv}/uart_test_{n}"


def run_urg(vdb, tests, report_dir):
    test_file = report_dir + ".tests"
    with open(test_file, "w") as f:
        f.write("\n".join(tests) + "\n")

    cmd = ["urg", "-dir", vdb, "-tests", test_file,
           "-format", "text", "-report", report_dir]
    result = subprocess.run(cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    if result.returncode != 0:
        print(result.stdout)
        sys.exit(f"urg failed for {report_dir}")


def parse_dashboard(report_dir):
    """Return {metric: value} from the Total Coverage Summary table."""
    path = os.path.join(report_dir, "dashboard.txt")
    with open(path) as f:
        lines = [l.strip() for l in f]

    for i, line in enumerate(lines):
        if line.startswith("Total Coverage Summary"):
            header = lines[i + 1].split()
            values = lines[i + 2].split()
            row = {}
            for name, val in zip(header, values):
                try:
                    row[name] = float(val)
                except ValueError:
                    row[name] = None      # e.g. "--" for an unused metric
            return row

    sys.exit(f"No 'Total Coverage Summary' found in {path}")


NUM = r"(?:\d+(?:\.\d+)?|--)"


def parse_dut(report_dir, inst):
    """
    Return {metric: value} for the DUT instance only, from hierarchy.txt.
    The row looks like:  SCORE LINE COND TOGGLE FSM BRANCH  <name>
    where <name> is 'dut' (indented under uart_test_top) or 'uart_test_top.dut'.
    These scores include the whole subtree under the DUT, and nothing from
    the testbench.
    """
    path = os.path.join(report_dir, "hierarchy.txt")
    with open(path) as f:
        lines = f.read().splitlines()

    header = None
    for line in lines:
        toks = line.split()
        if toks[:1] == ["SCORE"]:
            # Header row; some urg versions end it with NAME, some don't
            header = [t for t in toks if t != "NAME"]
            continue
        if header is None or len(toks) != len(header) + 1:
            continue
        name = toks[-1]
        if name == inst or name.endswith("." + inst):
            if all(re.fullmatch(NUM, t) for t in toks[:-1]):
                return {m: (None if v == "--" else float(v))
                        for m, v in zip(header, toks[:-1])}

    sys.exit(f"No row for instance '{inst}' in {path}. "
             f"Open it and check the instance name.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tests", type=int, default=11)
    ap.add_argument("--vdb", default="simv_uart_test_top_RTL.vdb")
    ap.add_argument("--out", default="coverage_sweep")
    ap.add_argument("--inst", default="dut",
                    help="DUT instance name under the testbench top")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    rows = []

    for k in range(1, args.tests + 1):
        tests = [test_name(args.vdb, n) for n in range(1, k + 1)]
        report_dir = os.path.join(args.out, f"tests_1_to_{k}")
        print(f"[sweep] merging tests 1..{k}")
        run_urg(args.vdb, tests, report_dir)

        # Code coverage: DUT subtree only (no testbench code)
        row = parse_dut(report_dir, args.inst)
        # Functional coverage: covergroups, from the dashboard
        row["GROUP"] = parse_dashboard(report_dir).get("GROUP")
        row["TESTS"] = k
        rows.append(row)
        print("        " + "  ".join(
            f"{m}={row.get(m)}" for m in METRICS if m in row))

    # ---- CSV ----
    csv_path = args.out + ".csv"
    present = [m for m in METRICS if any(m in r for r in rows)]
    with open(csv_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["TESTS"] + present)
        for r in rows:
            w.writerow([r["TESTS"]] + [r.get(m) for m in present])
    print(f"[sweep] wrote {csv_path}")

    # ---- Plot (optional) ----
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("[sweep] matplotlib not installed; skipping plot "
              "(plot the CSV elsewhere)")
        return

    xs = [r["TESTS"] for r in rows]
    fig, ax = plt.subplots(figsize=(9, 5))
    for m in present:
        ys = [r.get(m) for r in rows]
        width = 2.8 if m == "SCORE" else 1.6
        ax.plot(xs, ys, marker="o", linewidth=width, label=m)

    ax.set_xticks(xs)
    ax.set_xlabel("Tests included (cumulative, 1..k)")
    ax.set_ylabel("Coverage (%)")
    ax.set_ylim(0, 100)
    ax.set_title("UART DUT coverage as directed tests are added")
    ax.grid(True, alpha=0.3)
    ax.legend(loc="lower right")
    fig.tight_layout()

    png_path = args.out + ".png"
    fig.savefig(png_path, dpi=150)
    print(f"[sweep] wrote {png_path}")


if __name__ == "__main__":
    main()