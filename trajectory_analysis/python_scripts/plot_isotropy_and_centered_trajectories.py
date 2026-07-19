#!/usr/bin/env python3
"""
Generate:
1. an isotropy plot in grayscale;
2. centered trajectories colored by mean speed with the viridis palette;
3. a grayscale histogram of trajectory lengths (number of points);
4. ten centered-trajectory plots, one for each trajectory-length decile.

The eleven trajectory figures (one global plot and ten decile plots) are
exported with identical canvas dimensions, panel geometry, spatial limits,
and speed-color normalization.

Input:
    A metrics directory produced by the reorganized zoospore pipeline,
    containing:
        step_metrics.csv
        track_metrics.csv

Outputs:
    01_heading_isotropy.png
    01_heading_isotropy.csv
    02_centered_trajectories_viridis.png
    02_centered_trajectories_data.csv
    03_trajectory_length_distribution.png
    03_trajectory_lengths.csv
    03_trajectory_length_summary.csv
    04_centered_trajectories_length_decile_01.png
    ...
    04_centered_trajectories_length_decile_10.png
    04_centered_trajectories_by_length_decile.csv
    04_trajectory_length_deciles.csv
"""

from __future__ import annotations

import argparse
import csv
import math
import tol_colors as tc
from collections import defaultdict
from pathlib import Path
from typing import Iterable

import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.collections import LineCollection


# Fixed geometry for every trajectory figure.
#
# Saving with bbox_inches="tight" would crop each image according to its title,
# tick labels and axis limits, producing PNG files with different dimensions.
# These constants instead define one invariant canvas and one invariant layout.
TRAJECTORY_FIGSIZE = (8.0, 7.5)
TRAJECTORY_AX_RECT = (0.11, 0.11, 0.70, 0.78)
TRAJECTORY_CBAR_RECT = (0.85, 0.20, 0.035, 0.60)


def new_trajectory_figure() -> tuple[mpl.figure.Figure, mpl.axes.Axes, mpl.axes.Axes]:
    """Create the invariant layout used by all eleven trajectory figures."""
    fig = plt.figure(figsize=TRAJECTORY_FIGSIZE)
    ax = fig.add_axes(TRAJECTORY_AX_RECT)
    cax = fig.add_axes(TRAJECTORY_CBAR_RECT)
    return fig, ax, cax


def savefig_fixed_size(fig: mpl.figure.Figure, path: Path, dpi: int) -> None:
    """
    Save a figure without content-dependent cropping.

    At 300 dpi, an 8.0 × 7.5 inch canvas always yields a 2400 × 2250 px PNG.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=dpi)
    plt.close(fig)


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        raise FileNotFoundError(f"Missing required file: {path}")
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict], fieldnames: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if fieldnames is None:
        fieldnames = list(rows[0].keys()) if rows else []
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def numeric(row: dict[str, str], key: str) -> float:
    try:
        return float(row[key])
    except (KeyError, TypeError, ValueError):
        return math.nan


def find_column(columns: Iterable[str], prefix: str) -> str:
    matches = [name for name in columns if name.startswith(prefix)]
    if len(matches) != 1:
        raise ValueError(
            f"Expected exactly one column beginning with {prefix!r}; found {matches}"
        )
    return matches[0]


def finite(values: Iterable[float]) -> np.ndarray:
    arr = np.asarray(list(values), dtype=float)
    return arr[np.isfinite(arr)]


def compute_shared_trajectory_scales(
    step_rows: list[dict[str, str]],
    track_rows: list[dict[str, str]],
) -> tuple[float, float, float, np.ndarray]:
    """
    Compute the spatial and color scales shared by all trajectory figures.

    The spatial limit is based on every reconstructed centered trajectory.
    The speed normalization is based on the 2nd and 98th percentiles of all
    finite track mean speeds. The returned colorbar ticks are therefore also
    identical for the global plot and all ten decile plots.
    """
    if not step_rows:
        raise ValueError("step_metrics.csv is empty.")
    if not track_rows:
        raise ValueError("track_metrics.csv is empty.")

    columns = step_rows[0].keys()
    x_start_col = find_column(columns, "x_start_")
    y_start_col = find_column(columns, "y_start_")
    x_end_col = find_column(columns, "x_end_")
    y_end_col = find_column(columns, "y_end_")
    mean_speed_col = find_column(track_rows[0].keys(), "mean_speed_")

    grouped: dict[int, list[dict[str, str]]] = defaultdict(list)
    for row in step_rows:
        track_id = int(float(row["track_id"]))
        grouped[track_id].append(row)

    for rows in grouped.values():
        rows.sort(key=lambda row: int(float(row["step_index"])))

    max_abs_coordinate = 0.0
    for rows in grouped.values():
        if not rows:
            continue

        x0 = numeric(rows[0], x_start_col)
        y0 = numeric(rows[0], y_start_col)
        if not np.isfinite(x0) or not np.isfinite(y0):
            continue

        for row in rows:
            x = numeric(row, x_end_col) - x0
            y = numeric(row, y_end_col) - y0
            if np.isfinite(x):
                max_abs_coordinate = max(max_abs_coordinate, abs(x))
            if np.isfinite(y):
                max_abs_coordinate = max(max_abs_coordinate, abs(y))

    if max_abs_coordinate <= 0.0:
        max_abs_coordinate = 1.0
    spatial_limit = 1.05 * max_abs_coordinate

    finite_speeds = finite(numeric(row, mean_speed_col) for row in track_rows)
    if finite_speeds.size == 0:
        raise ValueError("No finite track mean speed found.")

    speed_vmin, speed_vmax = np.percentile(finite_speeds, [2, 98])
    if speed_vmin == speed_vmax:
        speed_vmin = float(np.min(finite_speeds))
        speed_vmax = float(np.max(finite_speeds))
        if speed_vmin == speed_vmax:
            speed_vmax = speed_vmin + 1e-12

    colorbar_ticks = np.linspace(speed_vmin, speed_vmax, 5)
    return spatial_limit, float(speed_vmin), float(speed_vmax), colorbar_ticks


def savefig(fig: mpl.figure.Figure, path: Path, dpi: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=dpi, bbox_inches="tight")
    plt.close(fig)


def rayleigh_resultant(theta_rad: np.ndarray) -> tuple[float, float]:
    """
    Return mean resultant length R and mean direction in radians.

    R = 0 indicates perfect isotropy in the sample.
    R = 1 indicates perfect alignment.
    """
    if theta_rad.size == 0:
        return math.nan, math.nan

    c = float(np.mean(np.cos(theta_rad)))
    s = float(np.mean(np.sin(theta_rad)))
    r = math.sqrt(c * c + s * s)
    mean_angle = math.atan2(s, c)
    return r, mean_angle


def make_isotropy_plot(
    step_rows: list[dict[str, str]],
    outdir: Path,
    angular_bins: int,
    dpi: int,
) -> None:
    headings_deg = finite(numeric(row, "heading_deg") for row in step_rows)
    if headings_deg.size == 0:
        raise ValueError("No finite heading values found in step_metrics.csv.")

    theta = np.radians(headings_deg % 360.0)
    edges = np.linspace(0.0, 2.0 * np.pi, angular_bins + 1)
    counts, _ = np.histogram(theta, bins=edges)
    widths = np.diff(edges)
    centres = edges[:-1] + widths / 2.0

    r, mean_angle = rayleigh_resultant(theta)

    rows = []
    total = int(counts.sum())
    for i, count in enumerate(counts):
        rows.append(
            {
                "bin_index": i,
                "angle_start_deg": math.degrees(edges[i]),
                "angle_end_deg": math.degrees(edges[i + 1]),
                "angle_center_deg": math.degrees(centres[i]),
                "count": int(count),
                "frequency": float(count / total) if total else math.nan,
            }
        )

    write_csv(outdir / "01_heading_isotropy.csv", rows)

    summary = [
        {
            "n_headings": headings_deg.size,
            "mean_resultant_length_R": r,
            "mean_direction_deg": math.degrees(mean_angle) % 360.0,
            "interpretation": "R close to 0 indicates isotropy; R close to 1 indicates alignment",
        }
    ]
    write_csv(outdir / "01_heading_isotropy_summary.csv", summary)

    fig = plt.figure(figsize=(6.4, 6.4))
    ax = fig.add_subplot(111, projection="polar")

    ax.bar(
        edges[:-1],
        counts,
        width=widths,
        align="edge",
        color="0.72",
        edgecolor="0.15",
        linewidth=0.6,
    )

    ax.set_theta_zero_location("E")
    ax.set_theta_direction(1)
    ax.set_title("Heading isotropy", pad=18)

    ax.text(
        0.02,
        0.02,
        f"n = {headings_deg.size}\nR = {r:.3f}",
        transform=ax.transAxes,
        ha="left",
        va="bottom",
    )

    savefig(fig, outdir / "01_heading_isotropy.png", dpi)


def make_centered_trajectory_plot(
    step_rows: list[dict[str, str]],
    track_rows: list[dict[str, str]],
    outdir: Path,
    max_tracks: int,
    dpi: int,
    line_width: float,
    spatial_limit: float,
    speed_vmin: float,
    speed_vmax: float,
    colorbar_ticks: np.ndarray,
) -> None:
    if not step_rows:
        raise ValueError("step_metrics.csv is empty.")
    if not track_rows:
        raise ValueError("track_metrics.csv is empty.")

    columns = step_rows[0].keys()
    x_start_col = find_column(columns, "x_start_")
    y_start_col = find_column(columns, "y_start_")
    x_end_col = find_column(columns, "x_end_")
    y_end_col = find_column(columns, "y_end_")

    unit = x_start_col.removeprefix("x_start_")
    mean_speed_col = find_column(track_rows[0].keys(), "mean_speed_")

    speed_by_track = {
        int(float(row["track_id"])): numeric(row, mean_speed_col)
        for row in track_rows
    }

    grouped: dict[int, list[dict[str, str]]] = defaultdict(list)
    for row in step_rows:
        track_id = int(float(row["track_id"]))
        grouped[track_id].append(row)

    for rows in grouped.values():
        rows.sort(key=lambda row: int(float(row["step_index"])))

    ordered_track_ids = sorted(
        grouped,
        key=lambda tid: (
            len(grouped[tid]),
            speed_by_track.get(tid, math.nan)
            if np.isfinite(speed_by_track.get(tid, math.nan))
            else -math.inf,
        ),
        reverse=True,
    )

    if max_tracks > 0:
        ordered_track_ids = ordered_track_ids[:max_tracks]

    segments: list[np.ndarray] = []
    values: list[float] = []
    export_rows: list[dict] = []

    for track_id in ordered_track_ids:
        rows = grouped[track_id]
        if not rows:
            continue

        x0 = numeric(rows[0], x_start_col)
        y0 = numeric(rows[0], y_start_col)
        speed = speed_by_track.get(track_id, math.nan)

        points = [[0.0, 0.0]]
        for row in rows:
            points.append(
                [
                    numeric(row, x_end_col) - x0,
                    numeric(row, y_end_col) - y0,
                ]
            )

        arr = np.asarray(points, dtype=float)
        if arr.shape[0] < 2:
            continue

        segments.append(arr)
        values.append(speed)

        for point_index, (x, y) in enumerate(arr):
            export_rows.append(
                {
                    "track_id": track_id,
                    "point_index": point_index,
                    f"centered_x_{unit}": float(x),
                    f"centered_y_{unit}": float(y),
                    mean_speed_col: speed,
                }
            )

    if not segments:
        raise ValueError("No centered trajectory could be reconstructed.")

    write_csv(outdir / "02_centered_trajectories_data.csv", export_rows)

    speed_values = np.asarray(values, dtype=float)
    if not np.any(np.isfinite(speed_values)):
        raise ValueError("No finite track mean speed found.")

    fig, ax, cax = new_trajectory_figure()

    collection = LineCollection(
        segments,
        cmap=tc.colormaps["PRGn"], #plt.get_cmap("viridis"),
        norm=mpl.colors.Normalize(vmin=speed_vmin, vmax=speed_vmax),
        linewidths=line_width,
        alpha=0.85,
    )
    collection.set_array(speed_values)

    ax.add_collection(collection)
    ax.set_xlim(-spatial_limit, spatial_limit)
    ax.set_ylim(-spatial_limit, spatial_limit)
    ax.set_aspect("equal", adjustable="box")
    ax.axhline(0, color="0.75", linewidth=0.8)
    ax.axvline(0, color="0.75", linewidth=0.8)
    ax.set_xlabel(f"Δx ({unit})")
    ax.set_ylabel(f"Δy ({unit})")
    ax.set_title(f"Centered trajectories (n = {len(segments)})")

    colorbar = fig.colorbar(collection, cax=cax, ticks=colorbar_ticks)
    speed_label = mean_speed_col.removeprefix("mean_speed_").replace("_per_s", "/s")
    colorbar.set_label(f"Mean speed ({speed_label})")

    savefig_fixed_size(
        fig,
        outdir / "02_centered_trajectories_viridis.png",
        dpi,
    )



def make_trajectory_length_plot(
    step_rows: list[dict[str, str]],
    outdir: Path,
    dpi: int,
) -> None:
    """Plot the distribution of trajectory lengths, expressed as point counts."""
    if not step_rows:
        raise ValueError("step_metrics.csv is empty.")

    steps_by_track: dict[int, int] = defaultdict(int)
    for row in step_rows:
        track_id = int(float(row["track_id"]))
        steps_by_track[track_id] += 1

    # A trajectory containing n displacements contains n + 1 recorded points.
    lengths = np.asarray([n_steps + 1 for n_steps in steps_by_track.values()], dtype=int)
    if lengths.size == 0:
        raise ValueError("No trajectory length could be calculated.")

    length_rows = [
        {
            "track_id": track_id,
            "n_steps": n_steps,
            "n_points": n_steps + 1,
        }
        for track_id, n_steps in sorted(steps_by_track.items())
    ]
    write_csv(outdir / "03_trajectory_lengths.csv", length_rows)

    q1, median, q3 = np.percentile(lengths, [25, 50, 75])
    summary = [
        {
            "n_tracks": int(lengths.size),
            "min_points": int(np.min(lengths)),
            "q1_points": float(q1),
            "median_points": float(median),
            "mean_points": float(np.mean(lengths)),
            "q3_points": float(q3),
            "max_points": int(np.max(lengths)),
            "std_points": float(np.std(lengths, ddof=1)) if lengths.size > 1 else 0.0,
        }
    ]
    write_csv(outdir / "03_trajectory_length_summary.csv", summary)

    min_length = int(np.min(lengths))
    max_length = int(np.max(lengths))
    bins = np.arange(min_length - 0.5, max_length + 1.5, 1.0)

    fig, ax = plt.subplots(figsize=(7.2, 5.2))
    ax.hist(
        lengths,
        bins=bins,
        color="0.72",
        edgecolor="0.15",
        linewidth=0.7,
    )
    ax.axvline(median, color="0.15", linewidth=1.2, linestyle="--",
               label=f"Median = {median:g} points")
    ax.set_xlabel("Trajectory length (number of points)")
    ax.set_ylabel("Number of trajectories")
    ax.set_title(f"Trajectory length distribution (n = {lengths.size})")
    ax.legend(frameon=False)

    savefig(fig, outdir / "03_trajectory_length_distribution.png", dpi)


def make_centered_trajectory_decile_plots(
    step_rows: list[dict[str, str]],
    track_rows: list[dict[str, str]],
    outdir: Path,
    max_tracks_per_decile: int,
    dpi: int,
    line_width: float,
    spatial_limit: float,
    speed_vmin: float,
    speed_vmax: float,
    colorbar_ticks: np.ndarray,
) -> None:
    """
    Plot centered trajectories separately for each decile of trajectory length.

    Deciles are assigned by rank after sorting trajectories by their number of
    recorded points. Using ``np.array_split`` guarantees ten groups whose sizes
    differ by at most one, even when many trajectories share the same length.
    Consequently, equal-length trajectories may occasionally fall into adjacent
    deciles; the CSV output records the exact assignment.
    """
    if not step_rows:
        raise ValueError("step_metrics.csv is empty.")
    if not track_rows:
        raise ValueError("track_metrics.csv is empty.")

    columns = step_rows[0].keys()
    x_start_col = find_column(columns, "x_start_")
    y_start_col = find_column(columns, "y_start_")
    x_end_col = find_column(columns, "x_end_")
    y_end_col = find_column(columns, "y_end_")
    unit = x_start_col.removeprefix("x_start_")

    mean_speed_col = find_column(track_rows[0].keys(), "mean_speed_")
    speed_by_track = {
        int(float(row["track_id"])): numeric(row, mean_speed_col)
        for row in track_rows
    }

    grouped: dict[int, list[dict[str, str]]] = defaultdict(list)
    for row in step_rows:
        track_id = int(float(row["track_id"]))
        grouped[track_id].append(row)

    for rows in grouped.values():
        rows.sort(key=lambda row: int(float(row["step_index"])))

    track_info = [
        {
            "track_id": track_id,
            "n_steps": len(rows),
            "n_points": len(rows) + 1,
            "mean_speed": speed_by_track.get(track_id, math.nan),
        }
        for track_id, rows in grouped.items()
        if rows
    ]
    if not track_info:
        raise ValueError("No trajectory could be assigned to a length decile.")

    # Stable deterministic ranking: first by length, then by track ID.
    track_info.sort(key=lambda item: (item["n_points"], item["track_id"]))
    index_groups = np.array_split(np.arange(len(track_info)), 10)

    all_export_rows: list[dict] = []
    decile_summary_rows: list[dict] = []

    for decile_index, indices in enumerate(index_groups, start=1):
        members = [track_info[int(i)] for i in indices]

        if not members:
            decile_summary_rows.append(
                {
                    "decile": decile_index,
                    "percentile_range": f"{(decile_index - 1) * 10}-{decile_index * 10}",
                    "n_tracks_total": 0,
                    "n_tracks_plotted": 0,
                    "min_points": "",
                    "median_points": "",
                    "max_points": "",
                }
            )
            continue

        # When limiting display, retain a representative spread across the rank
        # range rather than keeping only the shortest or longest trajectories.
        if max_tracks_per_decile > 0 and len(members) > max_tracks_per_decile:
            chosen = np.linspace(
                0, len(members) - 1, max_tracks_per_decile, dtype=int
            )
            plotted_members = [members[int(i)] for i in chosen]
        else:
            plotted_members = members

        segments: list[np.ndarray] = []
        speed_values: list[float] = []

        for member in plotted_members:
            track_id = int(member["track_id"])
            rows = grouped[track_id]

            x0 = numeric(rows[0], x_start_col)
            y0 = numeric(rows[0], y_start_col)
            speed = float(member["mean_speed"])

            points = [[0.0, 0.0]]
            for row in rows:
                points.append(
                    [
                        numeric(row, x_end_col) - x0,
                        numeric(row, y_end_col) - y0,
                    ]
                )

            arr = np.asarray(points, dtype=float)
            valid = np.all(np.isfinite(arr), axis=1)
            arr = arr[valid]
            if arr.shape[0] < 2:
                continue

            segments.append(arr)
            speed_values.append(speed)

            for point_index, (x, y) in enumerate(arr):
                all_export_rows.append(
                    {
                        "decile": decile_index,
                        "percentile_lower": (decile_index - 1) * 10,
                        "percentile_upper": decile_index * 10,
                        "track_id": track_id,
                        "n_points": int(member["n_points"]),
                        "point_index": point_index,
                        f"centered_x_{unit}": float(x),
                        f"centered_y_{unit}": float(y),
                        mean_speed_col: speed,
                    }
                )

        lengths = np.asarray([item["n_points"] for item in members], dtype=int)
        decile_summary_rows.append(
            {
                "decile": decile_index,
                "percentile_range": f"{(decile_index - 1) * 10}-{decile_index * 10}",
                "n_tracks_total": len(members),
                "n_tracks_plotted": len(segments),
                "min_points": int(np.min(lengths)),
                "median_points": float(np.median(lengths)),
                "max_points": int(np.max(lengths)),
            }
        )

        if not segments:
            continue

        values = np.asarray(speed_values, dtype=float)
        finite_speeds = values[np.isfinite(values)]

        fig, ax, cax = new_trajectory_figure()

        if finite_speeds.size:
            collection = LineCollection(
                segments,
                cmap=tc.colormaps["PRGn"], #plt.get_cmap("viridis"),
                norm=mpl.colors.Normalize(vmin=speed_vmin, vmax=speed_vmax),
                linewidths=line_width,
                alpha=0.85,
            )
            collection.set_array(values)
            ax.add_collection(collection)

            colorbar = fig.colorbar(collection, cax=cax, ticks=colorbar_ticks)
            speed_label = (
                mean_speed_col.removeprefix("mean_speed_")
                .replace("_per_s", "/s")
            )
            colorbar.set_label(f"Mean speed ({speed_label})")
        else:
            collection = LineCollection(
                segments,
                colors="0.25",
                linewidths=line_width,
                alpha=0.85,
            )
            ax.add_collection(collection)
            cax.set_visible(False)

        ax.set_xlim(-spatial_limit, spatial_limit)
        ax.set_ylim(-spatial_limit, spatial_limit)
        ax.set_aspect("equal", adjustable="box")
        ax.axhline(0, color="0.75", linewidth=0.8)
        ax.axvline(0, color="0.75", linewidth=0.8)
        ax.set_xlabel(f"Δx ({unit})")
        ax.set_ylabel(f"Δy ({unit})")
        ax.set_title(
            f"Centered trajectories — length decile {decile_index}\n"
            f"{(decile_index - 1) * 10}–{decile_index * 10}% "
            f"(n = {len(segments)}, {int(np.min(lengths))}–"
            f"{int(np.max(lengths))} points)"
        )

        savefig_fixed_size(
            fig,
            outdir
            / f"04_centered_trajectories_length_decile_{decile_index:02d}.png",
            dpi,
        )

    write_csv(
        outdir / "04_centered_trajectories_by_length_decile.csv",
        all_export_rows,
    )
    write_csv(
        outdir / "04_trajectory_length_deciles.csv",
        decile_summary_rows,
    )

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "metrics_dir",
        type=Path,
        help="Directory containing step_metrics.csv and track_metrics.csv.",
    )
    parser.add_argument(
        "-o",
        "--outdir",
        type=Path,
        default=None,
        help="Output directory. Default: METRICS_DIR/trajectory_overview",
    )
    parser.add_argument(
        "--angular-bins",
        type=int,
        default=36,
        help="Number of angular bins used for the isotropy plot.",
    )
    parser.add_argument(
        "--max-tracks",
        type=int,
        default=2000,
        help="Maximum number of trajectories displayed. Use 0 for all.",
    )
    parser.add_argument(
        "--line-width",
        type=float,
        default=0.55,
        help="Line width used for centered trajectories.",
    )
    parser.add_argument(
        "--max-tracks-per-decile",
        type=int,
        default=500,
        help=(
            "Maximum number of trajectories displayed in each length decile. "
            "Use 0 for all."
        ),
    )
    parser.add_argument(
        "--dpi",
        type=int,
        default=300,
        help=(
            "Output resolution. Trajectory PNG dimensions are always "
            "8.0 × 7.5 inches multiplied by this value "
            "(2400 × 2250 px at 300 dpi)."
        ),
    )
    args = parser.parse_args()

    if args.angular_bins < 4:
        parser.error("--angular-bins must be at least 4")
    if args.max_tracks < 0:
        parser.error("--max-tracks must be >= 0")
    if args.line_width <= 0:
        parser.error("--line-width must be > 0")
    if args.max_tracks_per_decile < 0:
        parser.error("--max-tracks-per-decile must be >= 0")

    return args


def main() -> int:
    args = parse_args()
    outdir = args.outdir or args.metrics_dir / "trajectory_overview"
    outdir.mkdir(parents=True, exist_ok=True)

    step_rows = read_csv(args.metrics_dir / "step_metrics.csv")
    track_rows = read_csv(args.metrics_dir / "track_metrics.csv")

    (
        shared_spatial_limit,
        shared_speed_vmin,
        shared_speed_vmax,
        shared_colorbar_ticks,
    ) = compute_shared_trajectory_scales(step_rows, track_rows)

    make_isotropy_plot(
        step_rows=step_rows,
        outdir=outdir,
        angular_bins=args.angular_bins,
        dpi=args.dpi,
    )

    make_centered_trajectory_plot(
        step_rows=step_rows,
        track_rows=track_rows,
        outdir=outdir,
        max_tracks=args.max_tracks,
        dpi=args.dpi,
        line_width=args.line_width,
        spatial_limit=shared_spatial_limit,
        speed_vmin=shared_speed_vmin,
        speed_vmax=shared_speed_vmax,
        colorbar_ticks=shared_colorbar_ticks,
    )

    make_trajectory_length_plot(
        step_rows=step_rows,
        outdir=outdir,
        dpi=args.dpi,
    )

    make_centered_trajectory_decile_plots(
        step_rows=step_rows,
        track_rows=track_rows,
        outdir=outdir,
        max_tracks_per_decile=args.max_tracks_per_decile,
        dpi=args.dpi,
        line_width=args.line_width,
        spatial_limit=shared_spatial_limit,
        speed_vmin=shared_speed_vmin,
        speed_vmax=shared_speed_vmax,
        colorbar_ticks=shared_colorbar_ticks,
    )

    print(f"Figures and CSV files written to: {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
