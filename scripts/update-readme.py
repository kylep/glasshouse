#!/usr/bin/env python3
"""Inject the ledger's capability table into README.md between markers.

The table is generated so it cannot drift from the code. Editing it by hand is
pointless — bootstrap.sh overwrites it on the next run.
"""
import pathlib
import subprocess
import sys

BEGIN = "<!-- BEGIN CAPABILITIES -->"
END = "<!-- END CAPABILITIES -->"

root = pathlib.Path(__file__).resolve().parent.parent
readme = root / "README.md"

table = subprocess.run(
    ["swift", "run", "-q", "glasshouse-ledger", "readme"],
    cwd=root, capture_output=True, text=True, check=True,
).stdout.strip()

text = readme.read_text()
if BEGIN not in text or END not in text:
    sys.exit(f"error: {readme} is missing the {BEGIN} / {END} markers")

head, rest = text.split(BEGIN, 1)
_, tail = rest.split(END, 1)
readme.write_text(f"{head}{BEGIN}\n{table}\n{END}{tail}")
print("Updated the capability table in README.md")
