#!/usr/bin/env python3
"""Every charted field must be a label some adapter actually emits.

A mistyped field name fails silently and completely: the chart finds no rows,
draws nothing, and reports no error at any layer. Nothing else catches it —
field labels live in GlasshouseSensors, which is iOS-only, so the Core test
suite cannot import them and a unit test is impossible. This grep is the gate.
"""
import re
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parent.parent

labels: dict[str, set[str]] = {}
for path in (root / "Sources/GlasshouseSensors").glob("*.swift"):
    text = path.read_text()
    # Each file holds several sources; split so a struct's id and its fields
    # stay together, rather than pooling every label in the file.
    for block in re.split(r"(?=public struct \w+: SensorSource)", text):
        found = re.search(r'id: SensorID = "([^"]+)"', block)
        if found:
            labels.setdefault(found.group(1), set()).update(
                re.findall(r'SensorField\("([^"]+)"', block)
            )

charts = root / "Sources/GlasshouseCore/Logging/ChartableSignals.swift"
featured = re.findall(r'sensor: "([^"]+)", field: "([^"]+)"', charts.read_text())

problems = []
for sensor, field in featured:
    if sensor not in labels:
        problems.append(f"{sensor}: no adapter declares this sensor")
    elif field not in labels[sensor]:
        problems.append(
            f"{sensor}: no field {field!r} — adapter emits {sorted(labels[sensor])}"
        )

for problem in problems:
    print(f"chart fields: {problem}", file=sys.stderr)

if problems:
    sys.exit(1)
print(f"chart fields: all {len(featured)} match a real adapter label")
