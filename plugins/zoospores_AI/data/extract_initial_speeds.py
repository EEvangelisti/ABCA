#!/usr/bin/env python3
"""
Extract the initial-speed distribution used by the ABCA-AI zoospore model.

The input is the TrackMate simple XML format:

    <Tracks frameInterval="0.0700506" ...>
      <particle nSpots="...">
        <detection t="..." x="..." y="..." z="..." />
        ...
      </particle>
      ...
    </Tracks>

Only trajectories with at least MIN_SPOTS detections are eligible.
Eligible trajectories are assigned deterministically to train/validation/test
using SHA-256("20250301:<retained_track_id>").

For each TRAIN trajectory, the speed between its first two detections is
written to the output CSV after conversion to IEEE-754 float32.

The XML is parsed incrementally, so very large files do not need to be loaded
into memory.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


SPLIT_SEED = "20250301"
MIN_SPOTS = 10
TRAIN_FRACTION = 0.60
VALIDATION_FRACTION = 0.20

# Expected value for the dataset/model from which discovered-swimming-v1.1
# was derived. Set to None with --no-check.
EXPECTED_INITIAL_SPEEDS = 40_747


def float32(value: float) -> float:
    """Round a Python float to IEEE-754 binary32, then return it as a float."""
    return struct.unpack("<f", struct.pack("<f", value))[0]


def split_value(track_id: int) -> float:
    """
    Deterministically map a retained track ID to [0, 1).

    We use the first 8 bytes of SHA-256 as an unsigned big-endian integer.
    """
    key = f"{SPLIT_SEED}:{track_id}".encode("utf-8")
    digest = hashlib.sha256(key).digest()
    integer = int.from_bytes(digest[:8], byteorder="big", signed=False)
    return integer / 2**64


def split_name(track_id: int) -> str:
    u = split_value(track_id)
    if u < TRAIN_FRACTION:
        return "train"
    if u < TRAIN_FRACTION + VALIDATION_FRACTION:
        return "validation"
    return "test"


def initial_speed(
    first: tuple[float, float, float],
    second: tuple[float, float, float],
    frame_interval: float,
) -> float:
    t0, x0, y0 = first
    t1, x1, y1 = second

    dt_frames = t1 - t0
    if dt_frames <= 0:
        raise ValueError(
            f"non-positive detection interval: t0={t0}, t1={t1}"
        )

    dt_seconds = dt_frames * frame_interval
    distance_um = math.hypot(x1 - x0, y1 - y0)
    return float32(distance_um / dt_seconds)


def extract(
    xml_path: Path,
    output_path: Path,
    expected_count: int | None,
) -> dict[str, int | float]:
    total_particles = 0
    eligible_particles = 0
    retained_track_id = 0

    counts = {
        "train": 0,
        "validation": 0,
        "test": 0,
    }

    written = 0
    frame_interval: float | None = None

    # We deliberately write progressively: memory usage remains essentially
    # constant even for very large TrackMate XML files.
    with output_path.open("w", newline="", encoding="utf-8") as out:
        writer = csv.writer(out)
        writer.writerow(["speed_um_s"])

        # start/end events let us read the root metadata and then process each
        # complete <particle> independently.
        context = ET.iterparse(xml_path, events=("start", "end"))

        for event, elem in context:
            tag = elem.tag.rsplit("}", 1)[-1]  # also tolerates XML namespaces

            if event == "start" and tag == "Tracks":
                value = elem.attrib.get("frameInterval")
                if value is None:
                    raise ValueError(
                        "Root <Tracks> element has no frameInterval attribute."
                    )
                frame_interval = float(value)
                if frame_interval <= 0:
                    raise ValueError("frameInterval must be positive.")

            if event != "end" or tag != "particle":
                continue

            total_particles += 1

            try:
                n_spots = int(elem.attrib["nSpots"])
            except (KeyError, ValueError) as exc:
                raise ValueError(
                    f"particle {total_particles} has invalid nSpots"
                ) from exc

            if n_spots >= MIN_SPOTS:
                eligible_particles += 1

                # IMPORTANT:
                # This is the ID among RETAINED tracks, not the raw particle
                # index. If the original discovered_swimming.ml increments
                # its retained_track_id differently, this is the one line of
                # logic that must be changed.
                track_id = retained_track_id
                retained_track_id += 1

                subset = split_name(track_id)
                counts[subset] += 1

                if subset == "train":
                    detections = []
                    for child in elem:
                        child_tag = child.tag.rsplit("}", 1)[-1]
                        if child_tag != "detection":
                            continue

                        try:
                            detection = (
                                float(child.attrib["t"]),
                                float(child.attrib["x"]),
                                float(child.attrib["y"]),
                            )
                        except (KeyError, ValueError) as exc:
                            raise ValueError(
                                f"invalid detection in retained track {track_id}"
                            ) from exc

                        detections.append(detection)
                        if len(detections) == 2:
                            break

                    if len(detections) < 2:
                        raise ValueError(
                            f"retained track {track_id} has fewer than "
                            "two readable detections"
                        )

                    if frame_interval is None:
                        raise RuntimeError(
                            "frameInterval was not read before particle data."
                        )

                    speed = initial_speed(
                        detections[0],
                        detections[1],
                        frame_interval,
                    )

                    # 9 significant digits are sufficient to round-trip every
                    # IEEE-754 float32 value exactly.
                    writer.writerow([format(speed, ".9g")])
                    written += 1

            # Release the particle and all its detections immediately.
            elem.clear()

    if frame_interval is None:
        raise ValueError("No <Tracks> element found.")

    if expected_count is not None and written != expected_count:
        raise RuntimeError(
            "\nCOUNT CHECK FAILED\n"
            f"Expected {expected_count:,} initial TRAIN speeds, "
            f"but generated {written:,}.\n"
            "The output file was created, but do NOT use it yet. "
            "Check the split-ID convention against discovered_swimming.ml."
        )

    return {
        "frame_interval": frame_interval,
        "total_particles": total_particles,
        "eligible_particles": eligible_particles,
        "train": counts["train"],
        "validation": counts["validation"],
        "test": counts["test"],
        "initial_speeds": written,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Extract the TRAIN initial-speed distribution for "
            "the ABCA-AI zoospore model."
        )
    )
    parser.add_argument(
        "xml",
        type=Path,
        help="input trajectories_Trackmate.xml",
    )
    parser.add_argument(
        "output",
        type=Path,
        help="output initial_training_speeds.csv",
    )
    parser.add_argument(
        "--expected-count",
        type=int,
        default=EXPECTED_INITIAL_SPEEDS,
        help=(
            "required number of extracted speeds "
            f"(default: {EXPECTED_INITIAL_SPEEDS})"
        ),
    )
    parser.add_argument(
        "--no-check",
        action="store_true",
        help="do not enforce the expected number of extracted speeds",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if not args.xml.is_file():
        print(f"ERROR: input file not found: {args.xml}", file=sys.stderr)
        return 2

    expected = None if args.no_check else args.expected_count

    try:
        stats = extract(args.xml, args.output, expected)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print()
    print("ABCA-AI initial-speed extraction")
    print("--------------------------------")
    print(f"Input:              {args.xml}")
    print(f"Output:             {args.output}")
    print(f"Frame interval:     {stats['frame_interval']:.10g} s")
    print(f"Particles:          {stats['total_particles']:,}")
    print(f"Eligible (>=10):    {stats['eligible_particles']:,}")
    print(f"TRAIN tracks:       {stats['train']:,}")
    print(f"VALIDATION tracks:  {stats['validation']:,}")
    print(f"TEST tracks:        {stats['test']:,}")
    print(f"Initial speeds:     {stats['initial_speeds']:,}")

    if expected is not None:
        print(f"Expected:           {expected:,}  [OK]")

    print()
    print("Extraction completed successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
