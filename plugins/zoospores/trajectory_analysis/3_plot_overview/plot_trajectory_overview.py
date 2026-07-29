#!/usr/bin/env python3
"""
Generate publication-ready overview plots from zoospore trajectory metrics.

Outputs:
    01_heading_isotropy.png
    01_heading_isotropy.csv
    01_heading_isotropy_summary.csv

    02_centered_trajectories.png
    02_centered_trajectories_data.csv
    02_mean_speed_colorbar.png

    03_trajectory_length_distribution.png
    03_trajectory_lengths.csv
    03_trajectory_length_summary.csv

    04_centered_trajectories_length_decile_01.png
    ...
    04_centered_trajectories_length_decile_10.png
    04_centered_trajectories_by_length_decile.csv
    04_trajectory_length_deciles.csv

    05_straightness_by_length_decile.png
    05_straightness_by_length_decile.csv
    05_straightness_by_length_decile_summary.csv

The global centered-trajectory plot samples trajectories across all ten
trajectory-length deciles. Faster trajectories are drawn first and slower
trajectories last, so slow trajectories remain visible in dense overlays.

The ten decile plots are exported as figure-ready vignettes without titles
or colorbars. A separate speed colorbar is exported once for figure assembly.
"""

from __future__ import annotations

import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path
from typing import Iterable
import tol_colors
import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.collections import LineCollection

mpl.rcParams.update(
    {
        "font.size": 17,
        "axes.labelsize": 18,
        "axes.titlesize": 18,
        "xtick.labelsize": 16,
        "ytick.labelsize": 16,
        "legend.fontsize": 15,
    }
)


GLOBAL_FIGSIZE = (6.0, 6.0)
GLOBAL_AX_RECT = (0.19, 0.14, 0.80, 0.74)
GLOBAL_CBAR_RECT = (0.85, 0.20, 0.035, 0.60)
VIGNETTE_FIGSIZE = (6.0, 6.0)
VIGNETTE_AX_RECT = (0.19, 0.14, 0.80, 0.74)


def savefig_fixed_size(fig: mpl.figure.Figure, path: Path, dpi: int) -> None:
    """Save without content-dependent cropping."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=dpi)
    plt.close(fig)


def savefig(fig: mpl.figure.Figure, path: Path, dpi: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=dpi, bbox_inches="tight")
    plt.close(fig)


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        raise FileNotFoundError(f"Missing required file: {path}")
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(
    path: Path,
    rows: list[dict],
    fieldnames: list[str] | None = None,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if fieldnames is None:
        fieldnames = list(rows[0].keys()) if rows else []
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=fieldnames,
            extrasaction="ignore",
        )
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
            f"Expected exactly one column beginning with {prefix!r}; "
            f"found {matches}"
        )
    return matches[0]


def finite(values: Iterable[float]) -> np.ndarray:
    array = np.asarray(list(values), dtype=float)
    return array[np.isfinite(array)]


def group_steps(
    step_rows: list[dict[str, str]],
) -> dict[int, list[dict[str, str]]]:
    grouped: dict[int, list[dict[str, str]]] = defaultdict(list)
    for row in step_rows:
        track_id = int(float(row["track_id"]))
        grouped[track_id].append(row)

    for rows in grouped.values():
        rows.sort(key=lambda row: int(float(row["step_index"])))

    return dict(grouped)


def assign_length_deciles(
    grouped: dict[int, list[dict[str, str]]],
    speed_by_track: dict[int, float],
    straightness_by_track: dict[int, float],
) -> tuple[list[dict], list[list[dict]]]:
    """
    Rank trajectories by point count and split them into ten balanced groups.

    Equal-length trajectories can fall into adjacent groups when necessary.
    Track ID is used as a deterministic tie-breaker.
    """
    track_info = [
        {
            "track_id": track_id,
            "n_steps": len(rows),
            "n_points": len(rows) + 1,
            "mean_speed": speed_by_track.get(track_id, math.nan),
            "straightness": straightness_by_track.get(track_id, math.nan),
        }
        for track_id, rows in grouped.items()
        if rows
    ]

    if not track_info:
        raise ValueError("No trajectory could be assigned to a length decile.")

    track_info.sort(key=lambda item: (item["n_points"], item["track_id"]))
    index_groups = np.array_split(np.arange(len(track_info)), 10)

    decile_groups: list[list[dict]] = []
    for decile, indices in enumerate(index_groups, start=1):
        members = [track_info[int(index)] for index in indices]
        for member in members:
            member["decile"] = decile
        decile_groups.append(members)

    return track_info, decile_groups


def evenly_sample(items: list[dict], n: int) -> list[dict]:
    """Select a deterministic spread across an already ranked list."""
    if n <= 0 or len(items) <= n:
        return list(items)

    indices = np.linspace(0, len(items) - 1, n, dtype=int)
    return [items[int(index)] for index in indices]


def sample_across_deciles(
    decile_groups: list[list[dict]],
    max_tracks: int,
) -> list[dict]:
    """
    Sample as evenly as possible across all non-empty length deciles.

    Any unused quota from small deciles is redistributed to deciles that still
    contain unselected trajectories.
    """
    all_members = [member for group in decile_groups for member in group]
    if max_tracks <= 0 or len(all_members) <= max_tracks:
        return all_members

    selected_by_decile: list[list[dict]] = [[] for _ in decile_groups]
    remaining = max_tracks

    active = [i for i, group in enumerate(decile_groups) if group]
    while remaining > 0 and active:
        base, extra = divmod(remaining, len(active))
        requested = [
            base + (1 if rank < extra else 0)
            for rank in range(len(active))
        ]

        newly_selected = 0
        next_active: list[int] = []

        for rank, decile_index in enumerate(active):
            group = decile_groups[decile_index]
            already = len(selected_by_decile[decile_index])
            available = len(group) - already
            take = min(requested[rank], available)

            if take > 0:
                target_count = already + take
                selected_by_decile[decile_index] = evenly_sample(
                    group,
                    target_count,
                )
                newly_selected += take

            if len(selected_by_decile[decile_index]) < len(group):
                next_active.append(decile_index)

        if newly_selected == 0:
            break

        remaining -= newly_selected
        active = next_active

    return [
        member
        for selected_group in selected_by_decile
        for member in selected_group
    ]


def trajectory_array(
    rows: list[dict[str, str]],
    x_start_col: str,
    y_start_col: str,
    x_end_col: str,
    y_end_col: str,
) -> np.ndarray | None:
    if not rows:
        return None

    x0 = numeric(rows[0], x_start_col)
    y0 = numeric(rows[0], y_start_col)
    if not np.isfinite(x0) or not np.isfinite(y0):
        return None

    points = [[0.0, 0.0]]
    for row in rows:
        points.append(
            [
                numeric(row, x_end_col) - x0,
                numeric(row, y_end_col) - y0,
            ]
        )

    array = np.asarray(points, dtype=float)
    array = array[np.all(np.isfinite(array), axis=1)]
    if array.shape[0] < 2:
        return None
    return array


def compute_shared_trajectory_scales(
    grouped: dict[int, list[dict[str, str]]],
    track_rows: list[dict[str, str]],
    x_start_col: str,
    y_start_col: str,
    x_end_col: str,
    y_end_col: str,
    mean_speed_col: str,
) -> tuple[float, float, float, np.ndarray]:
    max_abs_coordinate = 0.0

    for rows in grouped.values():
        array = trajectory_array(
            rows,
            x_start_col,
            y_start_col,
            x_end_col,
            y_end_col,
        )
        if array is not None:
            max_abs_coordinate = max(
                max_abs_coordinate,
                float(np.max(np.abs(array))),
            )
    spatial_limit = 1.05 * max(max_abs_coordinate, 1.0)

    speeds = finite(numeric(row, mean_speed_col) for row in track_rows)
    if speeds.size == 0:
        raise ValueError("No finite track mean speed found.")

    speed_vmin, speed_vmax = np.percentile(speeds, [2, 98])
    if speed_vmin == speed_vmax:
        speed_vmin = float(np.min(speeds))
        speed_vmax = float(np.max(speeds))
        if speed_vmin == speed_vmax:
            speed_vmax = speed_vmin + 1e-12

    ticks = np.linspace(speed_vmin, speed_vmax, 5)
    return spatial_limit, float(speed_vmin), float(speed_vmax), ticks


def rayleigh_resultant(theta_rad: np.ndarray) -> tuple[float, float]:
    if theta_rad.size == 0:
        return math.nan, math.nan

    cosine = float(np.mean(np.cos(theta_rad)))
    sine = float(np.mean(np.sin(theta_rad)))
    resultant = math.sqrt(cosine * cosine + sine * sine)
    mean_angle = math.atan2(sine, cosine)
    return resultant, mean_angle


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
    resultant, mean_angle = rayleigh_resultant(theta)

    total = int(counts.sum())
    rows = [
        {
            "bin_index": i,
            "angle_start_deg": math.degrees(edges[i]),
            "angle_end_deg": math.degrees(edges[i + 1]),
            "angle_center_deg": math.degrees(centres[i]),
            "count": int(count),
            "frequency": float(count / total) if total else math.nan,
        }
        for i, count in enumerate(counts)
    ]
    write_csv(outdir / "01_heading_isotropy.csv", rows)

    write_csv(
        outdir / "01_heading_isotropy_summary.csv",
        [
            {
                "n_headings": headings_deg.size,
                "mean_resultant_length_R": resultant,
                "mean_direction_deg": math.degrees(mean_angle) % 360.0,
                "interpretation": (
                    "R close to 0 indicates isotropy; "
                    "R close to 1 indicates alignment"
                ),
            }
        ],
    )

    fig = plt.figure(figsize=(6.0, 6.0))

    # Décale le graphe vers la droite afin de laisser plus de place
    # aux annotations ou à une future légende sur la gauche.
    ax = fig.add_axes((0.22, 0.12, 0.70, 0.76), projection="polar")
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
    # Conserve les cercles de la grille radiale, mais masque leurs valeurs.
    ax.set_yticklabels([])
    ax.set_title("Heading isotropy", pad=18)
    #fig.text(
    #    0.035,
    #    0.10,
    #    f"n = {headings_deg.size}\nR = {resultant:.3f}",
    #    ha="left",
    #    va="bottom",
    #)
    savefig(fig, outdir / "01_heading_isotropy.png", dpi)



def make_speed_colorbar(
    outdir: Path,
    speed_vmin: float,
    speed_vmax: float,
    colorbar_ticks: np.ndarray,
    speed_label: str,
    dpi: int,
) -> None:
    """Export a standalone horizontal colorbar for figure composition."""
    scalar_mappable = mpl.cm.ScalarMappable(
        norm=mpl.colors.Normalize(vmin=speed_vmin, vmax=speed_vmax),
        cmap=plt.get_cmap("tol.PRGn"),
    )
    fig = plt.figure(figsize=(2.5, 6.0))
    cax = fig.add_axes((
        0.25,   # gauche
        0.08,   # bas
        0.18,   # largeur
        0.84,   # hauteur
    ))
    colorbar = fig.colorbar(
        scalar_mappable,
        cax=cax,
        orientation="vertical",
        ticks=colorbar_ticks,
    )
    colorbar.ax.yaxis.set_ticks_position("right")
    colorbar.ax.yaxis.set_label_position("left")
    colorbar.set_label(
        f"Mean speed ({speed_label})",
        rotation=90,
        labelpad=20,
    )
    colorbar.ax.tick_params(labelsize=12)
    savefig_fixed_size(fig, outdir / "02_mean_speed_colorbar.png", dpi)


def make_centered_trajectory_plot(
    grouped: dict[int, list[dict[str, str]]],
    decile_groups: list[list[dict]],
    outdir: Path,
    max_tracks: int,
    dpi: int,
    line_width: float,
    spatial_limit: float,
    speed_vmin: float,
    speed_vmax: float,
    colorbar_ticks: np.ndarray,
    x_start_col: str,
    y_start_col: str,
    x_end_col: str,
    y_end_col: str,
    mean_speed_col: str,
    unit: str,
) -> None:
    selected = sample_across_deciles(decile_groups, max_tracks)

    # LineCollection draws later segments on top. Drawing high speeds first and
    # low speeds last keeps the slow trajectories visible in dense overlays.
    selected.sort(
        key=lambda member: (
            member["mean_speed"]
            if np.isfinite(member["mean_speed"])
            else math.inf
        ),
        reverse=True,
    )

    segments: list[np.ndarray] = []
    speed_values: list[float] = []
    export_rows: list[dict] = []

    for member in selected:
        track_id = int(member["track_id"])
        array = trajectory_array(
            grouped[track_id],
            x_start_col,
            y_start_col,
            x_end_col,
            y_end_col,
        )
        if array is None:
            continue

        speed = float(member["mean_speed"])
        segments.append(array)
        speed_values.append(speed)

        for point_index, (x_value, y_value) in enumerate(array):
            export_rows.append(
                {
                    "decile": int(member["decile"]),
                    "track_id": track_id,
                    "n_points": int(member["n_points"]),
                    "point_index": point_index,
                    f"centered_x_{unit}": float(x_value),
                    f"centered_y_{unit}": float(y_value),
                    mean_speed_col: speed,
                }
            )

    if not segments:
        raise ValueError("No centered trajectory could be reconstructed.")

    write_csv(outdir / "02_centered_trajectories_data.csv", export_rows)

    fig = plt.figure(figsize=GLOBAL_FIGSIZE)
    ax = fig.add_axes(GLOBAL_AX_RECT)
    #cax = fig.add_axes(GLOBAL_CBAR_RECT)

    collection = LineCollection(
        segments,
        cmap=plt.get_cmap("tol.PRGn"),
        norm=mpl.colors.Normalize(vmin=speed_vmin, vmax=speed_vmax),
        linewidths=line_width,
        alpha=0.85,
    )
    collection.set_array(np.asarray(speed_values, dtype=float))
    ax.add_collection(collection)

    ax.set_xlim(-spatial_limit, spatial_limit)
    ax.set_ylim(-spatial_limit, spatial_limit)
    ax.set_aspect("equal", adjustable="box")
    ax.axhline(0, color="0.75", linewidth=0.8)
    ax.axvline(0, color="0.75", linewidth=0.8)
    ax.set_xlabel(f"Δx ({unit})")
    ax.set_ylabel(f"Δy ({unit})")
    ax.set_title(f"Centered trajectories (n = {len(segments)})")

    speed_label = mean_speed_col.removeprefix("mean_speed_").replace(
        "_per_s",
        "/s",
    )
    #colorbar = fig.colorbar(collection, cax=cax, ticks=colorbar_ticks)
    #colorbar.set_label(f"Mean speed ({speed_label})")

    savefig_fixed_size(
        fig,
        outdir / "02_centered_trajectories.png",
        dpi,
    )

    make_speed_colorbar(
        outdir=outdir,
        speed_vmin=speed_vmin,
        speed_vmax=speed_vmax,
        colorbar_ticks=colorbar_ticks,
        speed_label=speed_label,
        dpi=dpi,
    )


def make_trajectory_length_plot(
    track_rows: list[dict[str, str]],
    outdir: Path,
    dpi: int,
    suffix: str,
    title_qualifier: str,
) -> None:
    """
    Plot trajectory-length distribution from track_metrics.csv.

    suffix distinguishes complete and filtered datasets.
    """
    lengths_by_track = {
        int(float(row["track_id"])): int(float(row["n_spots"]))
        for row in track_rows
        if np.isfinite(numeric(row, "n_spots"))
    }

    lengths = np.asarray(
        list(lengths_by_track.values()),
        dtype=int,
    )

    if lengths.size == 0:
        raise ValueError(
            "No trajectory length could be calculated from track_metrics.csv."
        )

    write_csv(
        outdir / f"03_trajectory_lengths_{suffix}.csv",
        [
            {
                "track_id": track_id,
                "n_steps": n_points - 1,
                "n_points": n_points,
            }
            for track_id, n_points in sorted(lengths_by_track.items())
        ],
    )

    q1, median, q3 = np.percentile(lengths, [25, 50, 75])

    write_csv(
        outdir / f"03_trajectory_length_summary_{suffix}.csv",
        [
            {
                "dataset": suffix,
                "n_tracks": int(lengths.size),
                "min_points": int(np.min(lengths)),
                "q1_points": float(q1),
                "median_points": float(median),
                "mean_points": float(np.mean(lengths)),
                "q3_points": float(q3),
                "max_points": int(np.max(lengths)),
                "std_points": (
                    float(np.std(lengths, ddof=1))
                    if lengths.size > 1
                    else 0.0
                ),
            }
        ],
    )

    bins = np.arange(
        int(np.min(lengths)) - 0.5,
        int(np.max(lengths)) + 1.5,
        1.0,
    )

    fig, ax = plt.subplots(figsize=(9.2, 6.0))

    ax.hist(
        lengths,
        bins=bins,
        color="0.72",
        edgecolor="0.15",
        linewidth=0.7,
    )

    ax.axvline(
        median,
        color="0.15",
        linewidth=1.2,
        linestyle="--",
        label=f"Median = {median:g} points",
    )

    ax.set_xlabel("Trajectory length (number of points)")
    ax.set_ylabel("Number of trajectories")
    ax.set_title(
        f"Trajectory length distribution — {title_qualifier} "
        f"(n = {lengths.size})"
    )
    ax.legend(frameon=False)

    savefig(
        fig,
        outdir / f"03_trajectory_length_distribution_{suffix}.png",
        dpi,
    )


def make_centered_trajectory_decile_plots(
    grouped: dict[int, list[dict[str, str]]],
    decile_groups: list[list[dict]],
    outdir: Path,
    max_tracks_per_decile: int,
    dpi: int,
    line_width: float,
    spatial_limit: float,
    speed_vmin: float,
    speed_vmax: float,
    x_start_col: str,
    y_start_col: str,
    x_end_col: str,
    y_end_col: str,
    mean_speed_col: str,
    unit: str,
) -> None:
    """
    Export ten minimalist, figure-ready trajectory vignettes.

    The plots have no title and no colorbar. They retain only the trajectory
    panel, coordinate axes, tick marks and tick values. A shared standalone
    colorbar is written separately by make_centered_trajectory_plot().
    """
    all_export_rows: list[dict] = []
    summary_rows: list[dict] = []

    for decile, members in enumerate(decile_groups, start=1):
        plotted_members = evenly_sample(members, max_tracks_per_decile)

        # As in the global panel, draw slower trajectories last.
        plotted_members.sort(
            key=lambda member: (
                member["mean_speed"]
                if np.isfinite(member["mean_speed"])
                else math.inf
            ),
            reverse=True,
        )

        segments: list[np.ndarray] = []
        speeds: list[float] = []

        for member in plotted_members:
            track_id = int(member["track_id"])
            array = trajectory_array(
                grouped[track_id],
                x_start_col,
                y_start_col,
                x_end_col,
                y_end_col,
            )
            if array is None:
                continue

            speed = float(member["mean_speed"])
            segments.append(array)
            speeds.append(speed)

            for point_index, (x_value, y_value) in enumerate(array):
                all_export_rows.append(
                    {
                        "decile": decile,
                        "percentile_lower": (decile - 1) * 10,
                        "percentile_upper": decile * 10,
                        "track_id": track_id,
                        "n_points": int(member["n_points"]),
                        "point_index": point_index,
                        f"centered_x_{unit}": float(x_value),
                        f"centered_y_{unit}": float(y_value),
                        mean_speed_col: speed,
                    }
                )

        lengths = np.asarray(
            [member["n_points"] for member in members],
            dtype=int,
        )
        summary_rows.append(
            {
                "decile": decile,
                "percentile_range": f"{(decile - 1) * 10}-{decile * 10}",
                "n_tracks_total": len(members),
                "n_tracks_plotted": len(segments),
                "min_points": int(np.min(lengths)) if lengths.size else "",
                "median_points": (
                    float(np.median(lengths)) if lengths.size else ""
                ),
                "max_points": int(np.max(lengths)) if lengths.size else "",
            }
        )

        if not segments:
            continue

        local_max_abs_coordinate = max(
            float(np.max(np.abs(segment)))
            for segment in segments
        )

        local_spatial_limit = 1.05 * max(local_max_abs_coordinate, 1.0)

        fig = plt.figure(figsize=VIGNETTE_FIGSIZE)
        ax = fig.add_axes(VIGNETTE_AX_RECT)

        collection = LineCollection(
            segments,
            cmap=plt.get_cmap("tol.PRGn"),
            norm=mpl.colors.Normalize(vmin=speed_vmin, vmax=speed_vmax),
            linewidths=line_width,
            alpha=0.85,
        )
        collection.set_array(np.asarray(speeds, dtype=float))
        ax.add_collection(collection)

        # Remove local to get a global scale.
        ax.set_xlim(-local_spatial_limit, local_spatial_limit)
        ax.set_ylim(-local_spatial_limit, local_spatial_limit)
        ax.set_aspect("equal", adjustable="box")
        ax.axhline(0, color="0.75", linewidth=0.8)
        ax.axvline(0, color="0.75", linewidth=0.8)
        ax.set_xlabel(f"Δx ({unit})")
        ax.set_ylabel(f"Δy ({unit})")
        ax.set_title(
            f"Decile {decile} ({(decile - 1) * 10}–{decile * 10}%)\n"
            f"n = {len(segments)}; {int(np.min(lengths))}–"
            f"{int(np.max(lengths))} points",
            pad=9,
            fontsize=17,
        )

        savefig_fixed_size(
            fig,
            outdir
            / f"04_centered_trajectories_length_decile_{decile:02d}.png",
            dpi,
        )

    write_csv(
        outdir / "04_centered_trajectories_by_length_decile.csv",
        all_export_rows,
    )
    write_csv(
        outdir / "04_trajectory_length_deciles.csv",
        summary_rows,
    )


def make_straightness_by_decile_plot(
    decile_groups: list[list[dict]],
    outdir: Path,
    dpi: int,
) -> None:
    """Export per-track values and a median/IQR straightness plot by decile."""
    value_rows: list[dict] = []
    summary_rows: list[dict] = []
    distributions: list[np.ndarray] = []

    for decile, members in enumerate(decile_groups, start=1):
        values = finite(member["straightness"] for member in members)
        distributions.append(values)

        for member in members:
            straightness = float(member["straightness"])
            if np.isfinite(straightness):
                value_rows.append(
                    {
                        "decile": decile,
                        "track_id": int(member["track_id"]),
                        "n_points": int(member["n_points"]),
                        "straightness": straightness,
                    }
                )

        if values.size:
            q1, median, q3 = np.percentile(values, [25, 50, 75])
            summary_rows.append(
                {
                    "decile": decile,
                    "percentile_range": f"{(decile - 1) * 10}-{decile * 10}",
                    "n_tracks": int(values.size),
                    "mean_straightness": float(np.mean(values)),
                    "std_straightness": (
                        float(np.std(values, ddof=1))
                        if values.size > 1
                        else 0.0
                    ),
                    "q1_straightness": float(q1),
                    "median_straightness": float(median),
                    "q3_straightness": float(q3),
                }
            )
        else:
            summary_rows.append(
                {
                    "decile": decile,
                    "percentile_range": f"{(decile - 1) * 10}-{decile * 10}",
                    "n_tracks": 0,
                    "mean_straightness": "",
                    "std_straightness": "",
                    "q1_straightness": "",
                    "median_straightness": "",
                    "q3_straightness": "",
                }
            )

    write_csv(
        outdir / "05_straightness_by_length_decile.csv",
        value_rows,
    )
    write_csv(
        outdir / "05_straightness_by_length_decile_summary.csv",
        summary_rows,
    )

    valid_distributions = [
        values if values.size else np.asarray([math.nan])
        for values in distributions
    ]

    fig, ax = plt.subplots(figsize=(11.2, 6.0))
    boxplot = ax.boxplot(
        valid_distributions,
        positions=np.arange(1, 11),
        widths=0.70,
        patch_artist=True,
        showfliers=False,
        medianprops={"color": "black", "linewidth": 1.5},
        boxprops={
            "facecolor": "white",
            "alpha": 0.75,
            "edgecolor": "0.2",
            "linewidth": 1.2,
        },
        whiskerprops={"color": "0.2"},
        capprops={"color": "0.2"},
    )
    _ = boxplot

    rng = np.random.default_rng(42)  # reproductible

    for decile, values in enumerate(distributions, start=1):
        if values.size == 0:
            continue

        x = (
            np.full(values.size, decile)
            + rng.normal(0.0, 0.1, values.size)   # jitter horizontal
        )

        ax.scatter(
            x,
            values,
            s=5,                 # taille des points
            color="0.25",        # gris foncé
            alpha=0.18,          # transparence
            linewidths=0,
            rasterized=True,     # très utile avec beaucoup de points
            zorder=3,
        )

    ax.set_xticks(np.arange(1, 11))
    ax.set_xlabel("Trajectory-length decile")
    ax.set_ylabel("Straightness")
    ax.set_title("Straightness by trajectory-length decile")
    ax.set_ylim(0.0, 1.05)
    savefig(fig, outdir / "05_straightness_by_length_decile.png", dpi)


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
        help=(
            "Maximum number of trajectories in the global panel, sampled "
            "across all length deciles. Use 0 for all."
        ),
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
            "Maximum number of trajectories displayed in each decile vignette. "
            "Use 0 for all."
        ),
    )
    parser.add_argument(
        "--dpi",
        type=int,
        default=300,
        help="Output resolution in dots per inch.",
    )
    parser.add_argument(
        "--complete-metrics-dir",
        type=Path,
        default=None,
        help=(
            "Directory containing the complete, unfiltered track_metrics.csv. "
            "When provided, an additional complete trajectory-length "
            "distribution is generated."
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
    if not step_rows:
        raise ValueError("step_metrics.csv is empty.")
    if not track_rows:
        raise ValueError("track_metrics.csv is empty.")

    step_columns = step_rows[0].keys()
    track_columns = track_rows[0].keys()

    x_start_col = find_column(step_columns, "x_start_")
    y_start_col = find_column(step_columns, "y_start_")
    x_end_col = find_column(step_columns, "x_end_")
    y_end_col = find_column(step_columns, "y_end_")
    mean_speed_col = find_column(track_columns, "mean_speed_")
    straightness_col = find_column(track_columns, "straightness")
    unit = x_start_col.removeprefix("x_start_")

    grouped = group_steps(step_rows)
    speed_by_track = {
        int(float(row["track_id"])): numeric(row, mean_speed_col)
        for row in track_rows
    }
    straightness_by_track = {
        int(float(row["track_id"])): numeric(row, straightness_col)
        for row in track_rows
    }

    _, decile_groups = assign_length_deciles(
        grouped,
        speed_by_track,
        straightness_by_track,
    )

    (
        spatial_limit,
        speed_vmin,
        speed_vmax,
        colorbar_ticks,
    ) = compute_shared_trajectory_scales(
        grouped,
        track_rows,
        x_start_col,
        y_start_col,
        x_end_col,
        y_end_col,
        mean_speed_col,
    )

    make_isotropy_plot(
        step_rows,
        outdir,
        args.angular_bins,
        args.dpi,
    )
    make_centered_trajectory_plot(
        grouped,
        decile_groups,
        outdir,
        args.max_tracks,
        args.dpi,
        args.line_width,
        spatial_limit,
        speed_vmin,
        speed_vmax,
        colorbar_ticks,
        x_start_col,
        y_start_col,
        x_end_col,
        y_end_col,
        mean_speed_col,
        unit,
    )
    # Distribution for the dataset used by downstream analyses:
    # normally the filtered dataset.
    make_trajectory_length_plot(
        track_rows=track_rows,
        outdir=outdir,
        dpi=args.dpi,
        suffix="filtered",
        title_qualifier="filtered",
    )

    # Produce only the length distribution for the complete dataset.
    if args.complete_metrics_dir is not None:
        complete_track_rows = read_csv(
            args.complete_metrics_dir / "track_metrics.csv"
        )

        make_trajectory_length_plot(
            track_rows=complete_track_rows,
            outdir=outdir,
            dpi=args.dpi,
            suffix="complete",
            title_qualifier="complete dataset",
        )
    make_centered_trajectory_decile_plots(
        grouped,
        decile_groups,
        outdir,
        args.max_tracks_per_decile,
        args.dpi,
        args.line_width,
        spatial_limit,
        speed_vmin,
        speed_vmax,
        x_start_col,
        y_start_col,
        x_end_col,
        y_end_col,
        mean_speed_col,
        unit,
    )
    make_straightness_by_decile_plot(
        decile_groups,
        outdir,
        args.dpi,
    )

    print(f"Figures and CSV files written to: {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
