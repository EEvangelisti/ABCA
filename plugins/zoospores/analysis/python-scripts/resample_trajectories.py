#!/usr/bin/env python3
"""
Resample simulated ABCA trajectories so that their lengths follow an empirical
trajectory-length distribution.

Expected XML structure
----------------------
<root>
  <particle id="0">
    <detection t="0" x="..." y="..." />
    <detection t="1" x="..." y="..." />
    ...
  </particle>
  ...
</root>

For each selected empirical length, the script:
1. selects a simulated particle with at least that many detections;
2. extracts a random contiguous segment of exactly that length;
3. resets time so that the segment starts at t = 0;
4. writes the sampled trajectories to a new XML file.

Source particles may be reused. This is useful when the empirical dataset
contains more trajectories than the simulation.

Example
-------
python resample_abca_trajectory_lengths.py \
    zoospores-empirical.xml \
    03_trajectory_lengths_filtered.csv \
    zoospores-empirical_resampled.xml \
    --seed 42
"""

from __future__ import annotations

import argparse
import bisect
import copy
import csv
import random
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


LENGTH_COLUMN_CANDIDATES = (
    "trajectory_length",
    "trajectory length",
    "track_length",
    "track length",
    "n_points",
    "n points",
    "number_of_points",
    "number of points",
    "num_points",
    "num points",
    "length_points",
    "length",
)

COUNT_COLUMN_CANDIDATES = (
    "count",
    "frequency",
    "n",
    "number",
    "number_of_trajectories",
    "number of trajectories",
)


@dataclass(frozen=True)
class Particle:
    particle_id: str
    detections: tuple[ET.Element, ...]


@dataclass(frozen=True)
class SampleRecord:
    output_particle_id: int
    source_particle_id: str
    sampled_length_points: int
    source_length_points: int
    source_start_index: int


def local_name(tag: str) -> str:
    """Return an XML tag name without its namespace."""

    return tag.rsplit("}", 1)[-1]


def parse_int_like(value: str) -> int:
    """Parse an integer or an exactly integer-valued floating-point string."""

    number = float(value.strip())
    rounded = round(number)

    if abs(number - rounded) > 1e-9:
        raise ValueError(f"Expected an integer-like value, got {value!r}.")

    return int(rounded)


def normalise_header(value: str) -> str:
    """Normalise a CSV header for robust column-name matching."""

    return " ".join(value.strip().lower().replace("_", " ").split())


def detect_column(
    fieldnames: Sequence[str],
    candidates: Sequence[str],
) -> str | None:
    """Return the original name of the first matching candidate column."""

    normalised = {normalise_header(name): name for name in fieldnames}

    for candidate in candidates:
        match = normalised.get(normalise_header(candidate))
        if match is not None:
            return match

    return None


def numeric_columns(
    rows: Sequence[dict[str, str]],
    fieldnames: Sequence[str],
) -> list[str]:
    """Return columns whose non-empty values are all numeric."""

    result: list[str] = []

    for field in fieldnames:
        seen_value = False

        for row in rows:
            value = (row.get(field) or "").strip()
            if not value:
                continue

            seen_value = True
            try:
                float(value)
            except ValueError:
                break
        else:
            if seen_value:
                result.append(field)

    return result


def read_empirical_lengths(csv_path: Path) -> list[int]:
    """
    Read empirical trajectory lengths from either one row per trajectory or an
    aggregated length/count table.
    """

    with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
        sample = handle.read(8192)
        handle.seek(0)

        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=",;\t")
        except csv.Error:
            dialect = csv.excel

        reader = csv.DictReader(handle, dialect=dialect)

        if not reader.fieldnames:
            raise ValueError(f"{csv_path} has no header row.")

        rows = list(reader)
        if not rows:
            raise ValueError(f"{csv_path} contains no data rows.")

        length_column = detect_column(
            reader.fieldnames,
            LENGTH_COLUMN_CANDIDATES,
        )
        count_column = detect_column(
            reader.fieldnames,
            COUNT_COLUMN_CANDIDATES,
        )

        if length_column is None:
            candidate_columns = numeric_columns(rows, reader.fieldnames)

            if len(candidate_columns) == 1:
                length_column = candidate_columns[0]
            else:
                raise ValueError(
                    "Could not identify the trajectory-length column.\n"
                    f"CSV columns: {reader.fieldnames}\n"
                    "Rename the relevant column to 'trajectory_length'."
                )

        lengths: list[int] = []

        for row_number, row in enumerate(rows, start=2):
            raw_length = (row.get(length_column) or "").strip()
            if not raw_length:
                continue

            try:
                length = parse_int_like(raw_length)
            except ValueError as exc:
                raise ValueError(
                    f"Invalid trajectory length on line {row_number}: "
                    f"{raw_length!r}"
                ) from exc

            if length < 2:
                continue

            repetitions = 1

            if count_column is not None and count_column != length_column:
                raw_count = (row.get(count_column) or "").strip()

                if raw_count:
                    repetitions = parse_int_like(raw_count)
                    if repetitions < 0:
                        raise ValueError(
                            f"Negative count on line {row_number}: "
                            f"{repetitions}"
                        )

            lengths.extend([length] * repetitions)

    if not lengths:
        raise ValueError(
            f"No valid trajectory lengths >= 2 were found in {csv_path}."
        )

    return lengths


def read_particles(xml_path: Path) -> tuple[ET.ElementTree, list[Particle]]:
    """Read particles and time-sort their detections."""

    tree = ET.parse(xml_path)
    root = tree.getroot()

    if local_name(root.tag) != "root":
        raise ValueError(
            f"Expected XML root element <root>, "
            f"found <{local_name(root.tag)}>."
        )

    particles: list[Particle] = []

    for ordinal, particle_element in enumerate(root):
        if local_name(particle_element.tag) != "particle":
            continue

        particle_id = particle_element.attrib.get("id", str(ordinal))
        detections = [
            detection
            for detection in particle_element
            if local_name(detection.tag) == "detection"
        ]

        if not detections:
            continue

        try:
            detections.sort(
                key=lambda detection: float(
                    detection.attrib.get("t", "0")
                )
            )
        except ValueError as exc:
            raise ValueError(
                f"Particle {particle_id} contains a non-numeric t value."
            ) from exc

        particles.append(
            Particle(
                particle_id=particle_id,
                detections=tuple(detections),
            )
        )

    if not particles:
        raise ValueError(
            "No <particle> elements containing <detection> entries were found."
        )

    return tree, particles


def choose_empirical_lengths(
    lengths: Sequence[int],
    n_samples: int | None,
    sampling_mode: str,
    rng: random.Random,
) -> list[int]:
    """Select the empirical lengths to reproduce."""

    if n_samples is None:
        selected = list(lengths)
        rng.shuffle(selected)
        return selected

    if n_samples <= 0:
        raise ValueError("--n-samples must be positive.")

    if sampling_mode == "without-replacement":
        if n_samples > len(lengths):
            raise ValueError(
                f"Requested {n_samples} lengths without replacement, but the "
                f"CSV contains only {len(lengths)}."
            )
        return rng.sample(list(lengths), n_samples)

    return [rng.choice(lengths) for _ in range(n_samples)]


def apply_too_long_policy(
    lengths: Sequence[int],
    maximum_simulated_length: int,
    policy: str,
) -> tuple[list[int], int]:
    """Apply the selected policy to empirical lengths that cannot be sampled."""

    result: list[int] = []
    affected_count = 0

    for length in lengths:
        if length <= maximum_simulated_length:
            result.append(length)
            continue

        affected_count += 1

        if policy == "error":
            raise ValueError(
                f"Empirical length {length} exceeds the longest simulated "
                f"trajectory ({maximum_simulated_length} points). "
                "Use '--too-long cap' or '--too-long drop' if appropriate."
            )

        if policy == "cap":
            result.append(maximum_simulated_length)

    if not result:
        raise ValueError("No target lengths remain after applying --too-long.")

    return result, affected_count


def infer_particle_tag(root: ET.Element) -> str:
    """Infer and preserve the particle tag, including any XML namespace."""

    for child in root:
        if local_name(child.tag) == "particle":
            return child.tag

    return "particle"


def infer_detection_tag(particles: Sequence[Particle]) -> str:
    """Infer and preserve the detection tag, including any XML namespace."""

    return particles[0].detections[0].tag


def clone_detection(
    source: ET.Element,
    output_t: int,
    preserve_extra_attributes: bool,
) -> ET.Element:
    """Clone one detection and reset its time coordinate."""

    if preserve_extra_attributes:
        cloned = copy.deepcopy(source)
    else:
        cloned = ET.Element(source.tag)
        for key in ("x", "y", "z"):
            if key in source.attrib:
                cloned.set(key, source.attrib[key])

    cloned.set("t", str(output_t))
    return cloned


def rebuild_xml(
    tree: ET.ElementTree,
    particles: Sequence[Particle],
    target_lengths: Sequence[int],
    rng: random.Random,
    preserve_extra_attributes: bool,
) -> tuple[list[SampleRecord], int]:
    """Replace source particles with randomly sampled trajectory segments."""

    root = tree.getroot()
    particle_tag = infer_particle_tag(root)
    detection_tag = infer_detection_tag(particles)

    # Preserve root-level metadata and remove only particle elements.
    for child in list(root):
        if local_name(child.tag) == "particle":
            root.remove(child)

    particles_sorted = sorted(
        particles,
        key=lambda particle: len(particle.detections),
    )
    source_lengths = [
        len(particle.detections)
        for particle in particles_sorted
    ]

    records: list[SampleRecord] = []
    output_detection_count = 0

    for output_particle_id, target_length in enumerate(target_lengths):
        first_eligible = bisect.bisect_left(source_lengths, target_length)

        if first_eligible == len(particles_sorted):
            raise AssertionError(
                f"No simulated particle is long enough for "
                f"{target_length} points."
            )

        source_particle = rng.choice(particles_sorted[first_eligible:])
        source_length = len(source_particle.detections)
        start_index = rng.randint(0, source_length - target_length)

        selected_detections = source_particle.detections[
            start_index : start_index + target_length
        ]

        output_particle = ET.Element(
            particle_tag,
            {"id": str(output_particle_id)},
        )

        for output_t, source_detection in enumerate(selected_detections):
            cloned = clone_detection(
                source_detection,
                output_t=output_t,
                preserve_extra_attributes=preserve_extra_attributes,
            )
            cloned.tag = detection_tag
            output_particle.append(cloned)
            output_detection_count += 1

        root.append(output_particle)

        records.append(
            SampleRecord(
                output_particle_id=output_particle_id,
                source_particle_id=source_particle.particle_id,
                sampled_length_points=target_length,
                source_length_points=source_length,
                source_start_index=start_index,
            )
        )

    return records, output_detection_count


def ensure_parent_directory(path: Path) -> None:
    """Create a file's parent directory when needed."""

    path.parent.mkdir(parents=True, exist_ok=True)


def write_provenance(
    path: Path,
    records: Sequence[SampleRecord],
) -> None:
    """Write source-trajectory provenance for each sampled output."""

    ensure_parent_directory(path)

    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            (
                "output_particle_id",
                "source_particle_id",
                "sampled_length_points",
                "source_length_points",
                "source_start_index",
            )
        )

        for record in records:
            writer.writerow(
                (
                    record.output_particle_id,
                    record.source_particle_id,
                    record.sampled_length_points,
                    record.source_length_points,
                    record.source_start_index,
                )
            )


def write_sampled_lengths(
    path: Path,
    records: Sequence[SampleRecord],
) -> None:
    """Write the final trajectory length associated with each output particle."""

    ensure_parent_directory(path)

    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(("particle_id", "trajectory_length"))

        for record in records:
            writer.writerow(
                (
                    record.output_particle_id,
                    record.sampled_length_points,
                )
            )


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""

    parser = argparse.ArgumentParser(
        description=(
            "Resample ABCA XML trajectories so their point-count distribution "
            "follows an empirical CSV."
        )
    )
    parser.add_argument("input_xml", type=Path)
    parser.add_argument("empirical_lengths_csv", type=Path)
    parser.add_argument("output_xml", type=Path)

    parser.add_argument(
        "--n-samples",
        type=int,
        default=None,
        help=(
            "Number of output trajectories. By default, every empirical "
            "length in the CSV is used."
        ),
    )
    parser.add_argument(
        "--empirical-sampling",
        choices=("with-replacement", "without-replacement"),
        default="without-replacement",
        help=(
            "How empirical lengths are selected when --n-samples is supplied "
            "(default: without-replacement)."
        ),
    )
    parser.add_argument(
        "--too-long",
        choices=("error", "cap", "drop"),
        default="error",
        help=(
            "Policy for empirical lengths longer than all simulated "
            "trajectories (default: error)."
        ),
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed (default: 42).",
    )
    parser.add_argument(
        "--provenance-csv",
        type=Path,
        default=None,
        help=(
            "Optional output path for the resampling-provenance table. "
            "By default, it is written beside the output XML."
        ),
    )
    parser.add_argument(
        "--sampled-lengths-csv",
        type=Path,
        default=None,
        help=(
            "Optional output path for the sampled-length table. "
            "By default, it is written beside the output XML."
        ),
    )
    parser.add_argument(
        "--minimal-detections",
        action="store_true",
        help=(
            "Write only t/x/y/z detection attributes. By default, all extra "
            "detection attributes are preserved."
        ),
    )

    return parser.parse_args()


def median(values: Sequence[int]) -> float:
    """Return the median of an already sorted, non-empty integer sequence."""

    count = len(values)
    middle = count // 2

    if count % 2:
        return float(values[middle])

    return (values[middle - 1] + values[middle]) / 2


def main() -> int:
    """Run the resampling workflow."""

    args = parse_args()
    rng = random.Random(args.seed)

    for path, description in (
        (args.input_xml, "input XML"),
        (args.empirical_lengths_csv, "empirical length CSV"),
    ):
        if not path.is_file():
            print(
                f"Error: {description} does not exist: {path}",
                file=sys.stderr,
            )
            return 2

    try:
        empirical_lengths = read_empirical_lengths(
            args.empirical_lengths_csv
        )
        selected_lengths = choose_empirical_lengths(
            empirical_lengths,
            n_samples=args.n_samples,
            sampling_mode=args.empirical_sampling,
            rng=rng,
        )

        tree, particles = read_particles(args.input_xml)
        maximum_length = max(
            len(particle.detections)
            for particle in particles
        )

        target_lengths, affected_count = apply_too_long_policy(
            selected_lengths,
            maximum_simulated_length=maximum_length,
            policy=args.too_long,
        )

        records, detection_count = rebuild_xml(
            tree,
            particles=particles,
            target_lengths=target_lengths,
            rng=rng,
            preserve_extra_attributes=not args.minimal_detections,
        )

        ensure_parent_directory(args.output_xml)
        ET.indent(tree, space="  ")
        tree.write(
            args.output_xml,
            encoding="utf-8",
            xml_declaration=True,
        )

        provenance_path = args.provenance_csv or args.output_xml.with_name(
            f"{args.output_xml.stem}_resampling_provenance.csv"
        )
        sampled_lengths_path = (
            args.sampled_lengths_csv
            or args.output_xml.with_name(
                f"{args.output_xml.stem}_sampled_lengths.csv"
            )
        )

        write_provenance(provenance_path, records)
        write_sampled_lengths(sampled_lengths_path, records)

    except (ValueError, ET.ParseError, OSError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    sampled_lengths = sorted(
        record.sampled_length_points
        for record in records
    )

    print("Resampling completed.")
    print(f"  Source particles: {len(particles)}")
    print(f"  Longest source trajectory: {maximum_length} points")
    print(f"  Empirical lengths available: {len(empirical_lengths)}")
    print(f"  Output particles: {len(records)}")
    print(f"  Output detections: {detection_count}")
    print(f"  Sampled median length: {median(sampled_lengths):g} points")
    print(
        f"  Sampled range: {sampled_lengths[0]}-"
        f"{sampled_lengths[-1]} points"
    )

    if affected_count:
        print(
            f"  Lengths affected by --too-long={args.too_long}: "
            f"{affected_count}"
        )

    print(f"  XML: {args.output_xml}")
    print(f"  Provenance: {provenance_path}")
    print(f"  Sampled lengths: {sampled_lengths_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
