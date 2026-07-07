#!/usr/bin/env python3
"""
Characterize zoospore trajectories from an XML particle-tracking file.

Input format expected by default:

<root>
  <particle>
    <detection t="0" x="..." y="..." />
    <detection t="1" x="..." y="..." />
    ...
  </particle>
  ...
</root>

The script writes one metric table per scale of analysis and one figure per metric.
It is designed so simulated trajectories and real trajectories can be compared
with identical parameters.
"""

from __future__ import annotations

import argparse
import csv
import math
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.collections import LineCollection


# -----------------------------------------------------------------------------
# Parameters
# -----------------------------------------------------------------------------


@dataclass(frozen=True)
class Parameters:
    xml_path: Path
    outdir: Path
    dt: float
    coord_scale: float
    unit: str
    min_spots: int
    max_spots: int | None
    crop_mode: str
    random_seed: int | None
    max_tracks_plot: int | None
    direction_threshold_deg: float
    speed_rel_change_threshold: float
    speed_abs_change_threshold: float | None
    stop_speed_threshold: float | None
    min_step_distance: float
    max_lag: int
    bins: int
    dpi: int
    show: bool
    direction_window: int

    @property
    def speed_unit(self) -> str:
        return f"{self.unit}/s"

    @property
    def area_unit(self) -> str:
        return f"{self.unit}²"


# -----------------------------------------------------------------------------
# Small numerical utilities
# -----------------------------------------------------------------------------


def finite(values: np.ndarray) -> np.ndarray:
    """Return finite values only."""
    return values[np.isfinite(values)]


def nanmean(values: np.ndarray) -> float:
    vals = finite(values)
    return float(np.mean(vals)) if vals.size else math.nan


def nanmedian(values: np.ndarray) -> float:
    vals = finite(values)
    return float(np.median(vals)) if vals.size else math.nan


def nanmax(values: np.ndarray) -> float:
    vals = finite(values)
    return float(np.max(vals)) if vals.size else math.nan


def wrap_degrees(angle: np.ndarray | float) -> np.ndarray | float:
    """Wrap angle(s) to [-180, 180)."""
    return (np.asarray(angle) + 180.0) % 360.0 - 180.0


def safe_div(num: float, den: float) -> float:
    return float(num / den) if den != 0 and np.isfinite(den) else math.nan


def ensure_outdir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def write_tsv(path: Path, rows: list[dict], fieldnames: list[str]) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t", extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


# -----------------------------------------------------------------------------
# Input parsing
# -----------------------------------------------------------------------------


@dataclass
class Track:
    track_id: int
    frames: np.ndarray
    xy: np.ndarray
    original_n_spots: int
    crop_start_index: int = 0

    @property
    def n_spots(self) -> int:
        return int(self.xy.shape[0])


def crop_track(
    frames: np.ndarray,
    xy: np.ndarray,
    max_spots: int | None,
    crop_mode: str,
    rng: np.random.Generator,
) -> tuple[np.ndarray, np.ndarray, int]:
    """Optionally crop one trajectory to at most max_spots detections.

    The crop is contiguous in time. With crop_mode="start", the first max_spots
    detections are kept. With crop_mode="random", the start index is sampled so
    the cropped track always contains exactly max_spots detections.
    """
    if max_spots is None or xy.shape[0] <= max_spots:
        return frames, xy, 0

    if crop_mode == "start":
        start = 0
    elif crop_mode == "random":
        start = int(rng.integers(0, xy.shape[0] - max_spots + 1))
    else:
        raise ValueError(f"Unsupported crop mode: {crop_mode!r}")

    end = start + max_spots
    return frames[start:end], xy[start:end], start


def read_tracks_xml(params: Parameters) -> list[Track]:
    tree = ET.parse(params.xml_path)
    root = tree.getroot()
    tracks: list[Track] = []
    rng = np.random.default_rng(params.random_seed)

    for track_id, particle in enumerate(root.findall("particle"), start=1):
        detections = particle.findall("detection")
        if len(detections) <= params.min_spots:
            continue

        try:
            detections.sort(key=lambda d: int(float(d.attrib["t"])))
            frames = np.array([int(float(d.attrib["t"])) for d in detections], dtype=int)
            xy = np.array(
                [
                    (float(d.attrib["x"]) * params.coord_scale,
                     float(d.attrib["y"]) * params.coord_scale)
                    for d in detections
                ],
                dtype=float,
            )
        except KeyError as exc:
            raise KeyError(f"Missing XML attribute {exc!s} in a detection element.") from exc
        except ValueError as exc:
            raise ValueError("Could not parse t/x/y as numeric values in the XML file.") from exc

        # Remove exact duplicate frames if present, keeping the first occurrence.
        keep = np.ones(frames.shape[0], dtype=bool)
        keep[1:] = frames[1:] != frames[:-1]
        frames = frames[keep]
        xy = xy[keep]

        # Selection is applied before cropping, so --min-spots refers to the
        # original usable trajectory length after duplicate-frame removal.
        # The comparison is strict: only tracks with > --min-spots are kept.
        original_n_spots = int(xy.shape[0])
        if original_n_spots <= params.min_spots:
            continue

        frames, xy, crop_start_index = crop_track(
            frames=frames,
            xy=xy,
            max_spots=params.max_spots,
            crop_mode=params.crop_mode,
            rng=rng,
        )

        tracks.append(
            Track(
                track_id=track_id,
                frames=frames,
                xy=xy,
                original_n_spots=original_n_spots,
                crop_start_index=crop_start_index,
            )
        )

    if not tracks:
        raise ValueError(
            f"No trajectory with more than {params.min_spots} detections was found in {params.xml_path}."
        )
    return tracks


# -----------------------------------------------------------------------------
# Metrics
# -----------------------------------------------------------------------------


def compute_metrics(params: Parameters, tracks: list[Track]) -> tuple[list[dict], list[dict], list[dict]]:
    track_rows: list[dict] = []
    step_rows: list[dict] = []
    turn_rows: list[dict] = []

    for track in tracks:
        xy = track.xy
        frames = track.frames
        w = params.direction_window

        dxy = xy[1:] - xy[:-1]
        frame_dt = np.diff(frames).astype(float) * params.dt

        if w == 1:
            heading_dxy = dxy
        else:
            heading_dxy = xy[w:] - xy[:-w]
        valid_dt = frame_dt > 0

        distance = np.sqrt(np.sum(dxy**2, axis=1))
        speed = np.full_like(distance, np.nan, dtype=float)
        speed[valid_dt] = distance[valid_dt] / frame_dt[valid_dt]

        heading = np.full(distance.shape, np.nan, dtype=float)

        if w == 1:
            valid = distance > params.min_step_distance
            heading[valid] = np.degrees(np.arctan2(dxy[valid, 1], dxy[valid, 0]))
        else:
            smoothed_distance = np.sqrt(np.sum(heading_dxy**2, axis=1))
            smoothed_heading = np.degrees(np.arctan2(heading_dxy[:, 1], heading_dxy[:, 0]))
            valid = smoothed_distance > params.min_step_distance
            heading[: smoothed_heading.size][valid] = smoothed_heading[valid]

        for i in range(distance.size):
            step_rows.append(
                {
                    "track_id": track.track_id,
                    "step_index": i + 1,
                    "frame_start": int(frames[i]),
                    "frame_end": int(frames[i + 1]),
                    "dt_s": frame_dt[i],
                    f"x_start_{params.unit}": xy[i, 0],
                    f"y_start_{params.unit}": xy[i, 1],
                    f"x_end_{params.unit}": xy[i + 1, 0],
                    f"y_end_{params.unit}": xy[i + 1, 1],
                    f"dx_{params.unit}": dxy[i, 0],
                    f"dy_{params.unit}": dxy[i, 1],
                    f"distance_{params.unit}": distance[i],
                    f"speed_{params.speed_unit}": speed[i],
                    "heading_deg": heading[i],
                }
            )

        # Turn metrics are defined at internal points: step i -> step i+1.
        direction_change_count = 0
        speed_change_count = 0
        run_lengths_s: list[float] = []
        current_run_s = 0.0

        for i in range(distance.size - 1):
            turn_angle = math.nan
            abs_turn_angle = math.nan
            curvature = math.nan
            rel_speed_change = math.nan
            abs_speed_change = math.nan
            is_direction_change = False
            is_speed_change = False

            if np.isfinite(heading[i]) and np.isfinite(heading[i + 1]):
                turn_angle = float(wrap_degrees(heading[i + 1] - heading[i]))
                abs_turn_angle = abs(turn_angle)
                is_direction_change = abs_turn_angle >= params.direction_threshold_deg
                denom_distance = max(distance[i + 1], distance[i])
                curvature = safe_div(math.radians(abs_turn_angle), denom_distance)

            if np.isfinite(speed[i]) and np.isfinite(speed[i + 1]):
                abs_speed_change = float(abs(speed[i + 1] - speed[i]))
                rel_speed_change = safe_div(abs_speed_change, max(abs(speed[i]), 1e-12))
                if params.speed_abs_change_threshold is not None:
                    is_speed_change = abs_speed_change >= params.speed_abs_change_threshold
                else:
                    is_speed_change = rel_speed_change >= params.speed_rel_change_threshold

            if is_direction_change:
                direction_change_count += 1
            if is_speed_change:
                speed_change_count += 1

            current_run_s += frame_dt[i] if np.isfinite(frame_dt[i]) else 0.0
            if is_direction_change:
                run_lengths_s.append(current_run_s)
                current_run_s = 0.0

            turn_rows.append(
                {
                    "track_id": track.track_id,
                    "turn_index": i + 1,
                    "frame": int(frames[i + 1]),
                    "heading_before_deg": heading[i],
                    "heading_after_deg": heading[i + 1],
                    "turn_angle_deg": turn_angle,
                    "abs_turn_angle_deg": abs_turn_angle,
                    f"speed_before_{params.speed_unit}": speed[i],
                    f"speed_after_{params.speed_unit}": speed[i + 1],
                    f"abs_speed_change_{params.speed_unit}": abs_speed_change,
                    "rel_speed_change": rel_speed_change,
                    f"curvature_rad_per_{params.unit}": curvature,
                    "is_direction_change": int(is_direction_change),
                    "is_speed_change": int(is_speed_change),
                }
            )

        # Finish the last run if the track has at least one step.
        if distance.size:
            current_run_s += frame_dt[-1] if np.isfinite(frame_dt[-1]) else 0.0
            if current_run_s > 0:
                run_lengths_s.append(current_run_s)

        path_length = float(np.nansum(distance))
        net_displacement = float(np.linalg.norm(xy[-1] - xy[0]))
        duration = float((frames[-1] - frames[0]) * params.dt)
        persistence = safe_div(net_displacement, path_length)

        if params.stop_speed_threshold is None:
            low_speed_fraction = math.nan
        else:
            finite_speed = finite(speed)
            low_speed_fraction = (
                float(np.mean(finite_speed < params.stop_speed_threshold)) if finite_speed.size else math.nan
            )

        track_rows.append(
            {
                "track_id": track.track_id,
                "n_spots": track.n_spots,
                "original_n_spots": track.original_n_spots,
                "crop_start_index": track.crop_start_index,
                "n_steps": int(distance.size),
                "duration_s": duration,
                f"path_length_{params.unit}": path_length,
                f"net_displacement_{params.unit}": net_displacement,
                "persistence": persistence,
                f"mean_speed_{params.speed_unit}": nanmean(speed),
                f"median_speed_{params.speed_unit}": nanmedian(speed),
                f"max_speed_{params.speed_unit}": nanmax(speed),
                "direction_change_count": direction_change_count,
                "direction_change_frequency_per_s": safe_div(direction_change_count, duration),
                "direction_change_frequency_per_step": safe_div(direction_change_count, max(distance.size - 1, 1)),
                "speed_change_count": speed_change_count,
                "speed_change_frequency_per_s": safe_div(speed_change_count, duration),
                "speed_change_frequency_per_step": safe_div(speed_change_count, max(distance.size - 1, 1)),
                "low_speed_fraction": low_speed_fraction,
                "mean_run_duration_s": nanmean(np.array(run_lengths_s, dtype=float)),
                "median_run_duration_s": nanmedian(np.array(run_lengths_s, dtype=float)),
            }
        )

    return track_rows, step_rows, turn_rows


def compute_msd(params: Parameters, tracks: list[Track]) -> list[dict]:
    rows: list[dict] = []
    for lag in range(1, params.max_lag + 1):
        values: list[float] = []
        for track in tracks:
            if track.xy.shape[0] <= lag:
                continue
            disp = track.xy[lag:] - track.xy[:-lag]
            sq = np.sum(disp**2, axis=1)
            values.extend([float(x) for x in sq if np.isfinite(x)])
        if values:
            arr = np.array(values, dtype=float)
            rows.append(
                {
                    "lag_frames": lag,
                    "lag_s": lag * params.dt,
                    f"msd_{params.area_unit}": float(np.mean(arr)),
                    f"median_squared_displacement_{params.area_unit}": float(np.median(arr)),
                    "n_pairs": int(arr.size),
                }
            )
    return rows


def compute_direction_autocorrelation(params: Parameters, step_rows: list[dict]) -> list[dict]:
    # Regroup headings per track.
    headings_by_track: dict[int, list[float]] = {}
    for row in step_rows:
        headings_by_track.setdefault(int(row["track_id"]), []).append(float(row["heading_deg"]))

    rows: list[dict] = []
    for lag in range(1, params.max_lag + 1):
        values: list[float] = []
        for headings in headings_by_track.values():
            h = np.array(headings, dtype=float)
            if h.size <= lag:
                continue
            a = np.radians(h[:-lag])
            b = np.radians(h[lag:])
            ok = np.isfinite(a) & np.isfinite(b)
            if np.any(ok):
                values.extend(np.cos(b[ok] - a[ok]).tolist())
        if values:
            arr = np.array(values, dtype=float)
            rows.append(
                {
                    "lag_steps": lag,
                    "lag_s_approx": lag * params.dt,
                    "direction_autocorrelation": float(np.mean(arr)),
                    "n_pairs": int(arr.size),
                }
            )
    return rows


def global_summary(params: Parameters, tracks: list[Track], track_rows: list[dict], step_rows: list[dict], turn_rows: list[dict]) -> list[dict]:
    def values(key: str, rows: list[dict]) -> np.ndarray:
        return np.array([float(row[key]) for row in rows if key in row and row[key] not in ("", None)], dtype=float)

    speed_key = f"speed_{params.speed_unit}"
    mean_speed_key = f"mean_speed_{params.speed_unit}"
    distance_key = f"distance_{params.unit}"
    path_key = f"path_length_{params.unit}"

    summary = {
        "xml_path": str(params.xml_path),
        "n_tracks": len(tracks),
        "n_spots": int(sum(t.n_spots for t in tracks)),
        "n_steps": len(step_rows),
        "n_turns": len(turn_rows),
        "dt_s": params.dt,
        "coord_scale": params.coord_scale,
        "unit": params.unit,
        "direction_threshold_deg": params.direction_threshold_deg,
        "speed_rel_change_threshold": params.speed_rel_change_threshold,
        "speed_abs_change_threshold": params.speed_abs_change_threshold if params.speed_abs_change_threshold is not None else "",
        "stop_speed_threshold": params.stop_speed_threshold if params.stop_speed_threshold is not None else "",
        "min_spots_strictly_more_than": params.min_spots,
        "max_spots_after_crop": params.max_spots if params.max_spots is not None else "",
        "crop_mode": params.crop_mode,
        "random_seed": params.random_seed if params.random_seed is not None else "",
        "n_spots_before_crop": int(sum(t.original_n_spots for t in tracks)),
        f"global_mean_speed_{params.speed_unit}": nanmean(values(speed_key, step_rows)),
        f"median_instant_speed_{params.speed_unit}": nanmedian(values(speed_key, step_rows)),
        f"median_track_mean_speed_{params.speed_unit}": nanmedian(values(mean_speed_key, track_rows)),
        f"median_step_distance_{params.unit}": nanmedian(values(distance_key, step_rows)),
        f"median_path_length_{params.unit}": nanmedian(values(path_key, track_rows)),
        "median_persistence": nanmedian(values("persistence", track_rows)),
        "median_direction_change_frequency_per_s": nanmedian(values("direction_change_frequency_per_s", track_rows)),
        "median_speed_change_frequency_per_s": nanmedian(values("speed_change_frequency_per_s", track_rows)),
        "median_abs_turn_angle_deg": nanmedian(values("abs_turn_angle_deg", turn_rows)),
        "median_rel_speed_change": nanmedian(values("rel_speed_change", turn_rows)),
    }
    return [summary]


# -----------------------------------------------------------------------------
# Plotting
# -----------------------------------------------------------------------------


def savefig(params: Parameters, fig: mpl.figure.Figure, stem: str) -> None:
    fig.savefig(params.outdir / f"{stem}.png", dpi=params.dpi, bbox_inches="tight")
    fig.savefig(params.outdir / f"{stem}.pdf", bbox_inches="tight")
    if params.show:
        plt.show()
    plt.close(fig)


def hist_plot(
    params: Parameters,
    values: np.ndarray,
    stem: str,
    title: str,
    xlabel: str,
    ylabel: str = "Count",
    bins: int | str | np.ndarray | None = None,
) -> None:
    vals = finite(values)
    if vals.size == 0:
        return
    fig, ax = plt.subplots(figsize=(7.0, 4.5))
    ax.hist(vals, bins=bins if bins is not None else params.bins)
    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.axvline(np.median(vals), linestyle="--", linewidth=1)
    ax.text(
        0.98,
        0.95,
        f"n = {vals.size}\nmedian = {np.median(vals):.3g}",
        transform=ax.transAxes,
        ha="right",
        va="top",
    )
    savefig(params, fig, stem)


def clean_axes(ax: mpl.axes.Axes) -> None:
    ax.set_axis_off()
    ax.set_xticks([])
    ax.set_yticks([])
    for spine in ax.spines.values():
        spine.set_visible(False)


def plot_centered_trajectories(params: Parameters, tracks: list[Track], track_rows: list[dict]) -> None:
    speed_key = f"mean_speed_{params.speed_unit}"
    speed_by_id = {int(row["track_id"]): float(row[speed_key]) for row in track_rows}

    ordered = sorted(tracks, key=lambda t: speed_by_id.get(t.track_id, 0.0), reverse=True)
    if params.max_tracks_plot is not None:
        ordered = ordered[: params.max_tracks_plot]
    if not ordered:
        return

    segs = [track.xy - track.xy[0] for track in ordered]
    vals = np.array([speed_by_id.get(track.track_id, math.nan) for track in ordered], dtype=float)
    vals_finite = finite(vals)
    if vals_finite.size == 0:
        return

    vmin, vmax = np.percentile(vals_finite, [2, 98])
    if vmin == vmax:
        vmin, vmax = np.min(vals_finite), np.max(vals_finite) + 1e-12

    fig, ax = plt.subplots(figsize=(7.5, 7.5))
    lc = LineCollection(
        segs,
        cmap=plt.get_cmap("viridis"),
        norm=mpl.colors.Normalize(vmin=vmin, vmax=vmax),
        linewidths=0.5,
    )
    lc.set_array(vals)
    ax.add_collection(lc)
    ax.axhline(0, linewidth=1)
    ax.axvline(0, linewidth=1)
    ax.set_aspect("equal", adjustable="box")
    ax.set_xlabel(f"Δx ({params.unit})")
    ax.set_ylabel(f"Δy ({params.unit})")
    ax.set_title(f"Centered trajectories colored by mean speed (n={len(ordered)})")
    cbar = fig.colorbar(lc, ax=ax)
    cbar.set_label(f"Mean speed ({params.speed_unit})")
    ax.autoscale()
    savefig(params, fig, "01_centered_trajectories_mean_speed")

    # Clean display version: trajectories only, no axis, no title, no colorbar.
    fig, ax = plt.subplots(figsize=(7.5, 7.5))
    lc = LineCollection(
        segs,
        cmap=plt.get_cmap("viridis"),
        norm=mpl.colors.Normalize(vmin=vmin, vmax=vmax),
        linewidths=0.5,
    )
    lc.set_array(vals)
    ax.add_collection(lc)
    ax.set_aspect("equal", adjustable="box")
    ax.autoscale()
    clean_axes(ax)

    fig.subplots_adjust(left=0, right=1, bottom=0, top=1)
    fig.savefig(
        params.outdir / "01_centered_trajectories_mean_speed_clean.png",
        dpi=params.dpi,
        bbox_inches="tight",
        pad_inches=0,
    )
    fig.savefig(
        params.outdir / "01_centered_trajectories_mean_speed_clean.pdf",
        bbox_inches="tight",
        pad_inches=0,
    )
    plt.close(fig)


def plot_turn_angle_signed(params: Parameters, turn_rows: list[dict]) -> None:
    vals = np.array([float(row["turn_angle_deg"]) for row in turn_rows], dtype=float)
    bins = np.linspace(-180, 180, 73)
    hist_plot(
        params,
        vals,
        "04_signed_turn_angle_distribution",
        "Signed turning angles",
        "Turning angle (degrees)",
        bins=bins,
    )


def plot_heading_rose(params: Parameters, step_rows: list[dict]) -> None:
    vals = finite(np.array([float(row["heading_deg"]) for row in step_rows], dtype=float))
    if vals.size == 0:
        return
    theta = np.radians((vals + 360.0) % 360.0)
    bins = np.linspace(0, 2 * np.pi, 37)
    counts, edges = np.histogram(theta, bins=bins)
    widths = np.diff(edges)

    fig = plt.figure(figsize=(6.0, 6.0))
    ax = fig.add_subplot(111, projection="polar")
    ax.bar(edges[:-1], counts, width=widths, align="edge")
    ax.set_title("Heading direction distribution")
    savefig(params, fig, "13_heading_rose")


def plot_scatter_speed_vs_turn(params: Parameters, turn_rows: list[dict]) -> None:
    speed_key = f"speed_before_{params.speed_unit}"
    x = np.array([float(row[speed_key]) for row in turn_rows], dtype=float)
    y = np.array([float(row["abs_turn_angle_deg"]) for row in turn_rows], dtype=float)
    ok = np.isfinite(x) & np.isfinite(y)
    if not np.any(ok):
        return
    x = x[ok]
    y = y[ok]
    if x.size > 50000:
        rng = np.random.default_rng(42)
        keep = rng.choice(x.size, size=50000, replace=False)
        x = x[keep]
        y = y[keep]

    fig, ax = plt.subplots(figsize=(6.5, 5.0))
    ax.scatter(x, y, s=4, alpha=0.25)
    ax.set_title("Speed before turn vs absolute turning angle")
    ax.set_xlabel(f"Speed before turn ({params.speed_unit})")
    ax.set_ylabel("Absolute turning angle (degrees)")
    savefig(params, fig, "10_speed_vs_abs_turn_scatter")


def plot_line_from_rows(
    params: Parameters,
    rows: list[dict],
    xkey: str,
    ykey: str,
    stem: str,
    title: str,
    xlabel: str,
    ylabel: str,
) -> None:
    if not rows:
        return
    x = np.array([float(row[xkey]) for row in rows], dtype=float)
    y = np.array([float(row[ykey]) for row in rows], dtype=float)
    ok = np.isfinite(x) & np.isfinite(y)
    if not np.any(ok):
        return
    fig, ax = plt.subplots(figsize=(6.5, 4.5))
    ax.plot(x[ok], y[ok], marker="o", linewidth=1)
    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    savefig(params, fig, stem)


def make_plots(
    params: Parameters,
    tracks: list[Track],
    track_rows: list[dict],
    step_rows: list[dict],
    turn_rows: list[dict],
    msd_rows: list[dict],
    autocorr_rows: list[dict],
) -> None:
    speed_key = f"speed_{params.speed_unit}"
    mean_speed_key = f"mean_speed_{params.speed_unit}"
    distance_key = f"distance_{params.unit}"

    plot_centered_trajectories(params, tracks, track_rows)

    hist_plot(
        params,
        np.array([float(row[speed_key]) for row in step_rows], dtype=float),
        "02_instantaneous_speed_distribution",
        "Instantaneous speed distribution",
        f"Instantaneous speed ({params.speed_unit})",
    )

    hist_plot(
        params,
        np.array([float(row[mean_speed_key]) for row in track_rows], dtype=float),
        "03_track_mean_speed_distribution",
        "Track mean speed distribution",
        f"Mean speed per trajectory ({params.speed_unit})",
    )

    plot_turn_angle_signed(params, turn_rows)

    hist_plot(
        params,
        np.array([float(row["abs_turn_angle_deg"]) for row in turn_rows], dtype=float),
        "05_absolute_turn_angle_distribution",
        "Absolute turning angle distribution",
        "Absolute turning angle (degrees)",
        bins=np.linspace(0, 180, 37),
    )

    hist_plot(
        params,
        np.array([float(row["direction_change_frequency_per_s"]) for row in track_rows], dtype=float),
        "06_direction_change_frequency_distribution",
        f"Direction-change frequency distribution (≥ {params.direction_threshold_deg:g}°)",
        "Direction changes per second",
    )

    hist_plot(
        params,
        np.array([float(row["speed_change_frequency_per_s"]) for row in track_rows], dtype=float),
        "07_speed_change_frequency_distribution",
        "Speed-change frequency distribution",
        "Speed changes per second",
    )

    hist_plot(
        params,
        np.array([float(row["persistence"]) for row in track_rows], dtype=float),
        "08_persistence_distribution",
        "Trajectory persistence distribution",
        "Net displacement / path length",
        bins=np.linspace(0, 1, 41),
    )

    hist_plot(
        params,
        np.array([float(row["mean_run_duration_s"]) for row in track_rows], dtype=float),
        "09_run_duration_distribution",
        "Run duration distribution",
        "Mean run duration per trajectory (s)",
    )

    plot_scatter_speed_vs_turn(params, turn_rows)

    hist_plot(
        params,
        np.array([float(row[distance_key]) for row in step_rows], dtype=float),
        "11_step_length_distribution",
        "Step-length distribution",
        f"Step length ({params.unit})",
    )

    msd_key = f"msd_{params.area_unit}"
    plot_line_from_rows(
        params,
        msd_rows,
        "lag_s",
        msd_key,
        "12_mean_squared_displacement",
        "Mean squared displacement",
        "Lag (s)",
        f"MSD ({params.area_unit})",
    )

    plot_line_from_rows(
        params,
        autocorr_rows,
        "lag_s_approx",
        "direction_autocorrelation",
        "14_direction_autocorrelation",
        "Direction autocorrelation",
        "Lag (s)",
        "Mean cos(Δheading)",
    )

    plot_heading_rose(params, step_rows)


# -----------------------------------------------------------------------------
# Command-line interface
# -----------------------------------------------------------------------------


def parse_args(argv: Iterable[str] | None = None) -> Parameters:
    parser = argparse.ArgumentParser(
        description="Characterize zoospore trajectories from a particle-tracking XML file."
    )
    parser.add_argument("xml", type=Path, help="Input XML file containing particle/detection elements.")
    parser.add_argument("-o", "--outdir", type=Path, default=Path("zoospore_trajectory_metrics"), help="Output directory.")
    parser.add_argument("--dt", type=float, default=0.2217, help="Time between two consecutive frames, in seconds. Default: 0.2217.")
    parser.add_argument(
        "--coord-scale",
        type=float,
        default=1.0,
        help="Multiplier applied to x/y coordinates. Use 10 for simulated grid cells of 10 µm.",
    )
    parser.add_argument("--unit", default="px", help="Spatial unit after scaling, e.g. px, µm, um, cell.")
    parser.add_argument(
        "--min-spots",
        type=int,
        default=10,
        help="Keep only trajectories with strictly more than this number of detections before optional cropping.",
    )
    parser.add_argument(
        "--max-spots",
        type=int,
        default=None,
        help="Optional maximum number of detections kept per trajectory after filtering.",
    )
    parser.add_argument(
        "--crop-mode",
        choices=("start", "random"),
        default="start",
        help="Cropping strategy used when --max-spots is set: keep the start, or sample a valid contiguous window.",
    )
    parser.add_argument(
        "--random-seed",
        type=int,
        default=42,
        help="Random seed used with --crop-mode random. Use a fixed value for reproducible crops.",
    )
    parser.add_argument(
        "--max-tracks-plot",
        type=int,
        default=2000,
        help="Maximum number of trajectories shown in the centered-trajectory plot. Use 0 for all.",
    )
    parser.add_argument(
        "--direction-threshold-deg",
        type=float,
        default=30.0,
        help="Absolute turning angle above which a direction change is counted.",
    )
    parser.add_argument(
        "--speed-rel-change-threshold",
        type=float,
        default=0.25,
        help="Relative speed-change threshold, used when --speed-abs-change-threshold is absent.",
    )
    parser.add_argument(
        "--speed-abs-change-threshold",
        type=float,
        default=None,
        help="Absolute speed-change threshold in output unit/s. Overrides the relative threshold if set.",
    )
    parser.add_argument(
        "--stop-speed-threshold",
        type=float,
        default=None,
        help="Optional low-speed threshold in output unit/s; enables low_speed_fraction in track metrics.",
    )
    parser.add_argument(
        "--min-step-distance",
        type=float,
        default=0.0,
        help="Steps at or below this distance are ignored for heading/turn-angle estimates.",
    )
    parser.add_argument("--max-lag", type=int, default=25, help="Maximum lag, in frames/steps, for MSD and autocorrelation.")
    parser.add_argument("--bins", type=int, default=50, help="Default number of bins for histograms.")
    parser.add_argument("--dpi", type=int, default=300, help="PNG resolution.")
    parser.add_argument("--show", action="store_true", help="Display figures interactively in addition to saving them.")
    parser.add_argument(
        "--direction-window",
        type=int,
        default=1,
        help="Number of successive movements used to estimate direction. Default: 1.",
    )

    args = parser.parse_args(argv)
    max_tracks_plot = None if args.max_tracks_plot == 0 else args.max_tracks_plot

    if args.dt <= 0:
        parser.error("--dt must be > 0")
    if args.coord_scale <= 0:
        parser.error("--coord-scale must be > 0")
    if args.min_spots < 3:
        parser.error("--min-spots must be at least 3 to compute turning angles")
    if args.max_spots is not None and args.max_spots < 3:
        parser.error("--max-spots must be at least 3 when set")
    if args.max_lag < 1:
        parser.error("--max-lag must be at least 1")
    if args.direction_window < 1:
        parser.error("--direction-window must be at least 1")

    return Parameters(
        xml_path=args.xml,
        outdir=args.outdir,
        dt=args.dt,
        coord_scale=args.coord_scale,
        unit=args.unit,
        min_spots=args.min_spots,
        max_spots=args.max_spots,
        crop_mode=args.crop_mode,
        random_seed=args.random_seed,
        max_tracks_plot=max_tracks_plot,
        direction_threshold_deg=args.direction_threshold_deg,
        speed_rel_change_threshold=args.speed_rel_change_threshold,
        speed_abs_change_threshold=args.speed_abs_change_threshold,
        stop_speed_threshold=args.stop_speed_threshold,
        min_step_distance=args.min_step_distance,
        max_lag=args.max_lag,
        bins=args.bins,
        dpi=args.dpi,
        show=args.show,
        direction_window=args.direction_window,
    )


def main(argv: Iterable[str] | None = None) -> int:
    params = parse_args(argv)
    ensure_outdir(params.outdir)

    tracks = read_tracks_xml(params)
    track_rows, step_rows, turn_rows = compute_metrics(params, tracks)
    msd_rows = compute_msd(params, tracks)
    autocorr_rows = compute_direction_autocorrelation(params, step_rows)
    summary_rows = global_summary(params, tracks, track_rows, step_rows, turn_rows)

    write_tsv(params.outdir / "track_metrics.tsv", track_rows, list(track_rows[0].keys()))
    write_tsv(params.outdir / "step_metrics.tsv", step_rows, list(step_rows[0].keys()))
    write_tsv(params.outdir / "turn_metrics.tsv", turn_rows, list(turn_rows[0].keys()) if turn_rows else [])
    write_tsv(params.outdir / "msd.tsv", msd_rows, list(msd_rows[0].keys()) if msd_rows else [])
    write_tsv(
        params.outdir / "direction_autocorrelation.tsv",
        autocorr_rows,
        list(autocorr_rows[0].keys()) if autocorr_rows else [],
    )
    write_tsv(params.outdir / "summary.tsv", summary_rows, list(summary_rows[0].keys()))

    make_plots(params, tracks, track_rows, step_rows, turn_rows, msd_rows, autocorr_rows)

    print(f"Analyzed {len(tracks)} trajectories after filtering.")
    if params.max_spots is not None:
        print(f"Cropped trajectories to at most {params.max_spots} points using mode: {params.crop_mode}.")
    print(f"Tables and figures written to: {params.outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
