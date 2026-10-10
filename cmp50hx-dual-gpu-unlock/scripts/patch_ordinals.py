#!/usr/bin/env python3
"""Generate two CMP 50HX EFI source variants by ordinal BDF selection.

Patches the selected upstream source *without* bundling its copyrighted code.
Anchors match the xrip/cmp50hx-unlock revision tested on 2026-10-10.
Fails closed if upstream code differs. No GPU writes are performed here.
"""
from __future__ import annotations

import argparse
from pathlib import Path

FUNC_START = "static int u40x_find_gpu_pass(INTN enc)"
FUNC_END = "static int u40x_find_gpu(void)"
FAST_LOOP = "    for (k = 0; k < sizeof(fastL) / sizeof(fastL[0]); k++) {"
SWEEP_LOOP = "    for (b = 0; b < maxBus; b++) {"
SELECT_LINE = "                    gBus = b; gDev = d; gFn = f;"


def generate(source: str, ordinal: int) -> str:
    assert ordinal in (0, 1)
    start = source.index(FUNC_START)
    end = source.index(FUNC_END, start)
    section = source[start:end]

    for label, anchor in (("fast", FAST_LOOP), ("sweep", SWEEP_LOOP), ("selection", SELECT_LINE)):
        if section.count(anchor) != 1:
            raise ValueError(f"Unexpected upstream layout: {label} anchor count is {section.count(anchor)}")

    # Remove the priority list so both builds see the *same* scan order.
    # Preserve the remaining original BDF scan, including its PCI-ID checks.
    fast_offset = section.index(FAST_LOOP)
    sweep_offset = section.index(SWEEP_LOOP, fast_offset)
    section = section[:fast_offset] + section[sweep_offset:]
    section = section.replace(
        SWEEP_LOOP,
        "    UINTN match_index = 0;\n" + SWEEP_LOOP,
        1,
    )
    section = section.replace(
        SELECT_LINE,
        f"                    if (match_index++ != {ordinal}u) continue;\n" + SELECT_LINE,
        1,
    )
    return source[:start] + section + source[end:]


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True, type=Path, help="Pristine upstream unlock50x_v1.c")
    p.add_argument("--output-dir", required=True, type=Path)
    a = p.parse_args()
    source = a.input.read_text(encoding="utf-8")
    a.output_dir.mkdir(parents=True, exist_ok=True)
    for ordinal in (0, 1):
        out = a.output_dir / f"unlock50x_auto{ordinal}.c"
        out.write_text(generate(source, ordinal), encoding="utf-8")
        print(f"Generated {out} (matching CMP ordinal {ordinal})")


if __name__ == "__main__":
    main()
