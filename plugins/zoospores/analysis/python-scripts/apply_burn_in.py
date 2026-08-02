#!/usr/bin/env python3
"""
Apply a burn-in period to TrackMate-compatible XML trajectory files.

The script supports:
1. Standard TrackMate XML files, where spots are stored globally and tracks
   are defined by edges referencing spot IDs.
2. ABCA-style TrackMate XML files, including variants where spots are embedded
   directly inside track elements.

For each trajectory, observations before the burn-in threshold are removed.
Trajectories with fewer than MIN_REMAINING_SPOTS observations afterwards are
discarded.
"""

from __future__ import annotations

import argparse
import csv
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator


SPOT_ID_KEYS = ("ID", "id", "SPOT_ID", "spot_id")
FRAME_KEYS = ("FRAME", "frame", "Frame")
TIME_KEYS = ("POSITION_T", "position_t", "TIME", "time")
SOURCE_KEYS = ("SPOT_SOURCE_ID", "source", "SOURCE_ID", "spot_source_id")
TARGET_KEYS = ("SPOT_TARGET_ID", "target", "TARGET_ID", "spot_target_id")
TRACK_ID_KEYS = ("TRACK_ID", "track_id", "ID", "id")
TRACK_SPOT_COUNT_KEYS = ("NUMBER_SPOTS", "N_SPOTS", "nspots", "size")


@dataclass
class TrackRecord:
    element: ET.Element
    spot_ids: list[str]
    spot_elements: list[ET.Element]
    edge_elements: list[ET.Element]
    embedded: bool
    track_id: str


@dataclass
class FileSummary:
    source: Path
    output: Path
    xml_type: str
    tracks_before: int
    tracks_after: int
    tracks_removed: int
    spots_before: int
    spots_after: int
    spots_removed: int


def local_name(tag: str) -> str:
    """Return an XML tag without its namespace."""
    return tag.rsplit("}", 1)[-1]


def first_attribute(element: ET.Element, keys: Iterable[str]) -> str | None:
    """Return the first available attribute value among candidate keys."""
    for key in keys:
        if key in element.attrib:
            return element.attrib[key]
    return None


def spot_id(element: ET.Element) -> str | None:
    return first_attribute(element, SPOT_ID_KEYS)


def spot_frame(element: ET.Element) -> float:
    raw = first_attribute(element, FRAME_KEYS)
    if raw is None:
        raise ValueError("spot has no FRAME attribute")
    return float(raw)


def spot_time(element: ET.Element) -> float | None:
    raw = first_attribute(element, TIME_KEYS)
    return None if raw is None else float(raw)


def is_spot(element: ET.Element) -> bool:
    return local_name(element.tag).lower() == "spot"


def is_edge(element: ET.Element) -> bool:
    return local_name(element.tag).lower() == "edge"


def is_track(element: ET.Element) -> bool:
    return local_name(element.tag).lower() == "track"


def parent_map(root: ET.Element) -> dict[ET.Element, ET.Element]:
    return {child: parent for parent in root.iter() for child in parent}


def remove_element(
    element: ET.Element,
    parents: dict[ET.Element, ET.Element],
) -> None:
    parent = parents.get(element)
    if parent is not None and element in list(parent):
        parent.remove(element)


def iter_track_elements(root: ET.Element) -> Iterator[ET.Element]:
    for element in root.iter():
        if is_track(element):
            yield element


def build_spot_index(root: ET.Element) -> dict[str, ET.Element]:
    index: dict[str, ET.Element] = {}
    for element in root.iter():
        if not is_spot(element):
            continue
        identifier = spot_id(element)
        if identifier is not None:
            index[identifier] = element
    return index


def edge_endpoint(edge: ET.Element, keys: Iterable[str]) -> str | None:
    return first_attribute(edge, keys)


def track_identifier(track: ET.Element, fallback: int) -> str:
    return first_attribute(track, TRACK_ID_KEYS) or str(fallback)


def collect_tracks(root: ET.Element) -> tuple[list[TrackRecord], str]:
    """
    Collect trajectories from standard TrackMate and embedded ABCA variants.
    """
    global_spots = build_spot_index(root)
    records: list[TrackRecord] = []
    saw_edges = False
    saw_embedded = False

    for position, track in enumerate(iter_track_elements(root), start=1):
        edges = [element for element in track.iter() if is_edge(element)]
        ids: list[str] = []

        if edges:
            saw_edges = True
            seen: set[str] = set()
            for edge in edges:
                source = edge_endpoint(edge, SOURCE_KEYS)
                target = edge_endpoint(edge, TARGET_KEYS)
                for identifier in (source, target):
                    if identifier is not None and identifier not in seen:
                        ids.append(identifier)
                        seen.add(identifier)

            spots = [global_spots[i] for i in ids if i in global_spots]
            records.append(
                TrackRecord(
                    element=track,
                    spot_ids=ids,
                    spot_elements=spots,
                    edge_elements=edges,
                    embedded=False,
                    track_id=track_identifier(track, position),
                )
            )
            continue

        embedded_spots = [
            element for element in track.iter()
            if element is not track and is_spot(element)
        ]
        if embedded_spots:
            saw_embedded = True
            records.append(
                TrackRecord(
                    element=track,
                    spot_ids=[
                        identifier
                        for element in embedded_spots
                        if (identifier := spot_id(element)) is not None
                    ],
                    spot_elements=embedded_spots,
                    edge_elements=[],
                    embedded=True,
                    track_id=track_identifier(track, position),
                )
            )

    if saw_edges and saw_embedded:
        xml_type = "mixed"
    elif saw_edges:
        xml_type = "trackmate"
    elif saw_embedded:
        xml_type = "abca-embedded"
    else:
        raise ValueError(
            "no supported trajectories found: expected Track elements with "
            "Edge references or embedded Spot elements"
        )

    return records, xml_type


def burn_in_threshold(
    frames: list[float],
    burn_in_frames: int,
    mode: str,
) -> float:
    if mode == "absolute":
        return float(burn_in_frames)
    return min(frames) + float(burn_in_frames)


def update_track_metadata(track: TrackRecord, kept_spots: list[ET.Element]) -> None:
    """Update common TrackMate summary attributes when they are present."""
    count = len(kept_spots)
    for key in TRACK_SPOT_COUNT_KEYS:
        if key in track.element.attrib:
            track.element.set(key, str(count))

    frames = [spot_frame(spot) for spot in kept_spots]
    times = [time for spot in kept_spots if (time := spot_time(spot)) is not None]

    updates: dict[str, float] = {}
    if frames:
        updates.update(
            {
                "TRACK_START_FRAME": min(frames),
                "TRACK_STOP_FRAME": max(frames),
            }
        )
    if times:
        updates.update(
            {
                "TRACK_START": min(times),
                "TRACK_STOP": max(times),
                "TRACK_DURATION": max(times) - min(times),
            }
        )

    for key, value in updates.items():
        if key in track.element.attrib:
            track.element.set(key, format_number(value))


def format_number(value: float) -> str:
    if value.is_integer():
        return str(int(value))
    return format(value, ".15g")


def update_global_counts(root: ET.Element) -> None:
    spots = [element for element in root.iter() if is_spot(element)]
    tracks = [element for element in root.iter() if is_track(element)]

    for element in root.iter():
        name = local_name(element.tag).lower()
        if name == "allspots":
            for key in ("nspots", "NSPOTS", "NUMBER_SPOTS"):
                if key in element.attrib:
                    element.set(key, str(len(spots)))
        elif name == "alltracks":
            for key in ("ntracks", "NTRACKS", "NUMBER_TRACKS"):
                if key in element.attrib:
                    element.set(key, str(len(tracks)))


def remove_filtered_track_references(
    root: ET.Element,
    removed_track_ids: set[str],
    parents: dict[ET.Element, ET.Element],
) -> None:
    """Remove TrackID references to trajectories discarded by the filter."""
    for element in list(root.iter()):
        if local_name(element.tag).lower() not in {
            "trackid",
            "filteredtrack",
            "trackref",
        }:
            continue
        identifier = first_attribute(element, TRACK_ID_KEYS)
        if identifier in removed_track_ids:
            remove_element(element, parents)


def process_xml(
    source: Path,
    output: Path,
    burn_in_frames: int,
    minimum_remaining_spots: int,
    mode: str,
    indent: bool,
) -> FileSummary:
    tree = ET.parse(source)
    root = tree.getroot()
    parents = parent_map(root)
    tracks, xml_type = collect_tracks(root)

    all_spots_before = [element for element in root.iter() if is_spot(element)]
    removed_spots: set[ET.Element] = set()
    removed_track_ids: set[str] = set()
    retained_tracks = 0

    for track in tracks:
        if not track.spot_elements:
            removed_track_ids.add(track.track_id)
            remove_element(track.element, parents)
            continue

        frames = [spot_frame(spot) for spot in track.spot_elements]
        threshold = burn_in_threshold(frames, burn_in_frames, mode)

        kept_spots = [
            spot for spot in track.spot_elements
            if spot_frame(spot) >= threshold
        ]
        discarded_spots = [
            spot for spot in track.spot_elements
            if spot_frame(spot) < threshold
        ]

        if len(kept_spots) < minimum_remaining_spots:
            removed_track_ids.add(track.track_id)
            removed_spots.update(track.spot_elements)
            remove_element(track.element, parents)
            continue

        retained_tracks += 1
        removed_spots.update(discarded_spots)

        if track.edge_elements:
            kept_ids = {
                identifier
                for spot in kept_spots
                if (identifier := spot_id(spot)) is not None
            }
            for edge in track.edge_elements:
                source_id = edge_endpoint(edge, SOURCE_KEYS)
                target_id = edge_endpoint(edge, TARGET_KEYS)
                if source_id not in kept_ids or target_id not in kept_ids:
                    remove_element(edge, parents)

        if track.embedded:
            for spot in discarded_spots:
                remove_element(spot, parents)

        update_track_metadata(track, kept_spots)

    # Remove globally stored TrackMate spots only after every track has been
    # examined, avoiding accidental removal during graph reconstruction.
    for spot in removed_spots:
        remove_element(spot, parents)

    # Remove now-empty frame containers where applicable.
    for element in list(root.iter()):
        if local_name(element.tag).lower() == "spotsinframe":
            if not any(is_spot(child) for child in element):
                remove_element(element, parents)

    remove_filtered_track_references(root, removed_track_ids, parents)
    update_global_counts(root)

    output.parent.mkdir(parents=True, exist_ok=True)
    if indent and hasattr(ET, "indent"):
        ET.indent(tree, space="  ")
    tree.write(output, encoding="utf-8", xml_declaration=True)

    spots_after = sum(1 for element in root.iter() if is_spot(element))
    return FileSummary(
        source=source,
        output=output,
        xml_type=xml_type,
        tracks_before=len(tracks),
        tracks_after=retained_tracks,
        tracks_removed=len(tracks) - retained_tracks,
        spots_before=len(all_spots_before),
        spots_after=spots_after,
        spots_removed=len(all_spots_before) - spots_after,
    )


def collect_sources(source: Path, pattern: str) -> list[Path]:
    if source.is_file():
        return [source]
    return sorted(path for path in source.glob(pattern) if path.is_file())


def write_summary(path: Path, rows: list[FileSummary]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "source",
                "output",
                "xml_type",
                "tracks_before",
                "tracks_after",
                "tracks_removed",
                "spots_before",
                "spots_after",
                "spots_removed",
            ]
        )
        for row in rows:
            writer.writerow(
                [
                    row.source,
                    row.output,
                    row.xml_type,
                    row.tracks_before,
                    row.tracks_after,
                    row.tracks_removed,
                    row.spots_before,
                    row.spots_after,
                    row.spots_removed,
                ]
            )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Remove an initial burn-in period from TrackMate or ABCA trajectory "
            "XML files and discard trajectories that become too short."
        )
    )
    parser.add_argument("xml_source", type=Path)
    parser.add_argument("--outdir", required=True, type=Path)
    parser.add_argument("--burn-in-frames", required=True, type=int)
    parser.add_argument("--min-remaining-spots", type=int, default=10)
    parser.add_argument(
        "--mode",
        choices=("absolute", "relative"),
        default="absolute",
        help=(
            "absolute: remove observations with FRAME < burn-in; "
            "relative: remove burn-in frames from each track start"
        ),
    )
    parser.add_argument("--pattern", default="*.xml")
    parser.add_argument(
        "--summary-filename",
        default="burn_in_summary.csv",
    )
    parser.add_argument(
        "--indent-xml",
        action="store_true",
        help="Pretty-print output XML files; increases file size.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_arguments()

    if args.burn_in_frames < 0:
        raise SystemExit("--burn-in-frames must be non-negative")
    if args.min_remaining_spots < 1:
        raise SystemExit("--min-remaining-spots must be positive")
    if not args.xml_source.exists():
        raise SystemExit(f"XML source not found: {args.xml_source}")

    sources = collect_sources(args.xml_source, args.pattern)
    if not sources:
        raise SystemExit(
            f"No XML files matching {args.pattern!r} found in {args.xml_source}"
        )

    args.outdir.mkdir(parents=True, exist_ok=True)
    summaries: list[FileSummary] = []

    for index, source in enumerate(sources, start=1):
        output = args.outdir / source.name
        try:
            summary = process_xml(
                source=source,
                output=output,
                burn_in_frames=args.burn_in_frames,
                minimum_remaining_spots=args.min_remaining_spots,
                mode=args.mode,
                indent=args.indent_xml,
            )
        except (ET.ParseError, ValueError, OSError) as error:
            print(f"Error processing {source}: {error}", file=sys.stderr)
            return 1

        summaries.append(summary)
        print(
            f"[{index}/{len(sources)}] {source.name}: "
            f"{summary.xml_type}, "
            f"{summary.tracks_after}/{summary.tracks_before} tracks retained, "
            f"{summary.spots_after}/{summary.spots_before} spots retained"
        )

    write_summary(args.outdir / args.summary_filename, summaries)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
