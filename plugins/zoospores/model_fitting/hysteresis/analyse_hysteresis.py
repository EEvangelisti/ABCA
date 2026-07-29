#!/usr/bin/env python3
"""Compare Otsu FAST/SLOW segmentation with increasing hysteresis widths.

The script reads ``step_metrics.csv`` from a trajectory-metrics directory,
computes a single Otsu threshold from all finite instantaneous speeds, and
resegments every trajectory with several symmetric hysteresis half-widths.

For a half-width ``delta``:

    lower threshold = Otsu threshold - delta
    upper threshold = Otsu threshold + delta

A FAST observation switches to SLOW only below the lower threshold; a SLOW
observation switches to FAST only above the upper threshold. Speeds inside the
intermediate band retain the preceding state. ``delta = 0`` reproduces the
ordinary single-threshold segmentation.

Outputs include, for every tested half-width:

- FAST/SLOW episode table;
- transition probabilities;
- FAST and SLOW duration histograms;
- FAST and SLOW episode-length histograms;
- threshold/hysteresis-band plot.

The root output directory also contains comparison CSV files and sensitivity
plots showing how episode counts, one-step episodes, median durations, median
lengths, state occupancy and transition probabilities change with hysteresis.
"""

from __future__ import annotations

import argparse
import csv
import math
from collections import defaultdict
from collections.abc import Iterable, Sequence
from pathlib import Path
import tol_colors
import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np


# -----------------------------------------------------------------------------
# Publication style
# -----------------------------------------------------------------------------

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

FIGURE_HEIGHT = 6.0
FIGSIZE_STANDARD = (8.0, FIGURE_HEIGHT)
FIGSIZE_WIDE = (8.0, FIGURE_HEIGHT)
HISTOGRAM_FACE = "0.82"
HISTOGRAM_EDGE = "0.30"
LINE_COLOR = "0.10"
REFERENCE_COLOR = "0.50"
DISPLAY_FAST_SLOW_LEGEND=0


CMAP = plt.get_cmap("tol.PRGn")
SLOW_COLOR = CMAP(0.10)       # violet
FAST_COLOR = CMAP(0.90)       # vert
HYSTERESIS_COLOR = "0.85"     # gris clair

# -----------------------------------------------------------------------------
# I/O and generic helpers
# -----------------------------------------------------------------------------


def read_csv(path: Path) -> list[dict[str, str]]:
    """Read a CSV file and return its rows as dictionaries."""
    if not path.exists():
        raise FileNotFoundError(f"Missing required file: {path}")
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(
    path: Path,
    rows: Sequence[dict],
    fieldnames: Sequence[str] | None = None,
) -> None:
    """Write dictionaries to a CSV file, creating parent directories."""
    path.parent.mkdir(parents=True, exist_ok=True)
    resolved = list(fieldnames) if fieldnames is not None else (
        list(rows[0].keys()) if rows else []
    )
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=resolved, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def numeric(row: dict[str, str], key: str) -> float:
    """Return a numeric CSV value, or NaN when conversion fails."""
    try:
        return float(row[key])
    except (KeyError, TypeError, ValueError):
        return math.nan


def finite(values: Iterable[float]) -> np.ndarray:
    """Return finite values as a one-dimensional NumPy array."""
    array = np.asarray(list(values), dtype=float)
    return array[np.isfinite(array)]


def find_column(columns: Iterable[str], prefix: str) -> str:
    """Find the unique column whose name starts with ``prefix``."""
    matches = [column for column in columns if column.startswith(prefix)]
    if len(matches) != 1:
        raise ValueError(
            f"Expected exactly one column beginning with {prefix!r}; found {matches}"
        )
    return matches[0]


def group_steps_by_track(
    rows: list[dict[str, str]],
) -> dict[int, list[dict[str, str]]]:
    """Group step rows by trajectory and sort them by step index."""
    grouped: dict[int, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        grouped[int(float(row["track_id"]))].append(row)
    for track_rows in grouped.values():
        track_rows.sort(key=lambda row: int(float(row["step_index"])))
    return dict(grouped)


def make_figure(
    figsize: tuple[float, float] = FIGSIZE_STANDARD,
) -> tuple[mpl.figure.Figure, mpl.axes.Axes]:
    """Create a figure using a consistent publication layout."""
    fig, ax = plt.subplots(figsize=figsize)
    fig.subplots_adjust(left=0.14, right=0.97, bottom=0.15, top=0.88)
    return fig, ax


def save_figure(fig: mpl.figure.Figure, path: Path, dpi: int) -> None:
    """Save a figure without content-dependent cropping."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=dpi)
    plt.close(fig)


# -----------------------------------------------------------------------------
# Thresholding and state segmentation
# -----------------------------------------------------------------------------


def otsu_threshold(values: np.ndarray, bins: int = 256) -> float:
    """Estimate a binary threshold by maximising between-class variance."""
    data = values[np.isfinite(values)]
    if data.size < 2:
        raise ValueError("At least two finite speed values are required for Otsu.")
    if np.all(data == data[0]):
        raise ValueError("Otsu threshold is undefined for constant speed data.")

    counts, edges = np.histogram(data, bins=bins)
    centres = (edges[:-1] + edges[1:]) / 2.0
    counts = counts.astype(float)

    weight_left = np.cumsum(counts)
    weight_right = counts.sum() - weight_left
    sum_left = np.cumsum(counts * centres)
    total_sum = float(np.sum(counts * centres))

    valid = (weight_left > 0) & (weight_right > 0)
    mean_left = np.zeros_like(centres)
    mean_right = np.zeros_like(centres)
    mean_left[valid] = sum_left[valid] / weight_left[valid]
    mean_right[valid] = (total_sum - sum_left[valid]) / weight_right[valid]

    score = weight_left * weight_right * (mean_left - mean_right) ** 2
    score[~valid] = -np.inf
    return float(centres[int(np.argmax(score))])


def classify_with_hysteresis(
    speeds: Sequence[float],
    threshold: float,
    half_width: float,
) -> list[str]:
    """Classify an ordered speed series as FAST/SLOW using hysteresis."""
    if half_width < 0:
        raise ValueError("Hysteresis half-width must be non-negative.")

    lower = threshold - half_width
    upper = threshold + half_width
    states: list[str] = []

    for index, speed in enumerate(speeds):
        if not np.isfinite(speed):
            raise ValueError("classify_with_hysteresis received a non-finite speed.")

        if index == 0:
            # The first observation has no history. Initialise it relative to
            # the central Otsu threshold, not one edge of the hysteresis band.
            state = "FAST" if speed >= threshold else "SLOW"
        elif states[-1] == "FAST":
            state = "SLOW" if speed < lower else "FAST"
        else:
            state = "FAST" if speed > upper else "SLOW"
        states.append(state)

    return states


def segment_tracks(
    grouped_steps: dict[int, list[dict[str, str]]],
    speed_column: str,
    distance_column: str,
    unit: str,
    threshold: float,
    half_width: float,
) -> tuple[list[dict], list[dict], dict[str, int], dict[str, int]]:
    """Segment all tracks and return episodes, step states and counts."""
    episodes: list[dict] = []
    state_rows: list[dict] = []
    transition_counts = {
        "SLOW_SLOW": 0,
        "SLOW_FAST": 0,
        "FAST_SLOW": 0,
        "FAST_FAST": 0,
    }
    state_counts = {"SLOW": 0, "FAST": 0}
    episode_id = 1

    for track_id, rows in grouped_steps.items():
        usable_rows = [
            row for row in rows if np.isfinite(numeric(row, speed_column))
        ]
        if not usable_rows:
            continue

        speeds = [numeric(row, speed_column) for row in usable_rows]
        states = classify_with_hysteresis(speeds, threshold, half_width)

        for row, state in zip(usable_rows, states):
            state_counts[state] += 1
            state_rows.append(
                {
                    "track_id": track_id,
                    "step_index": int(float(row["step_index"])),
                    "frame_start": int(float(row["frame_start"])),
                    "frame_end": int(float(row["frame_end"])),
                    speed_column: numeric(row, speed_column),
                    "state": state,
                }
            )

        for current, following in zip(states[:-1], states[1:]):
            transition_counts[f"{current}_{following}"] += 1

        start = 0
        while start < len(usable_rows):
            state = states[start]
            end = start + 1
            while end < len(usable_rows) and states[end] == state:
                end += 1

            episode_rows = usable_rows[start:end]
            episode_speeds = [numeric(row, speed_column) for row in episode_rows]
            episodes.append(
                {
                    "episode_id": episode_id,
                    "track_id": track_id,
                    "state": state,
                    "start_frame": int(float(episode_rows[0]["frame_start"])),
                    "end_frame": int(float(episode_rows[-1]["frame_end"])),
                    "n_steps": len(episode_rows),
                    "duration_s": float(
                        sum(numeric(row, "dt_s") for row in episode_rows)
                    ),
                    f"length_{unit}": float(
                        sum(numeric(row, distance_column) for row in episode_rows)
                    ),
                    f"mean_speed_{unit}_per_s": float(np.mean(episode_speeds)),
                }
            )
            episode_id += 1
            start = end

    return episodes, state_rows, transition_counts, state_counts


def transition_table(counts: dict[str, int]) -> list[dict]:
    """Convert transition counts to row-normalised probabilities."""
    rows: list[dict] = []
    for source, target in (
        ("SLOW", "SLOW"),
        ("SLOW", "FAST"),
        ("FAST", "SLOW"),
        ("FAST", "FAST"),
    ):
        count = counts[f"{source}_{target}"]
        denominator = counts[f"{source}_SLOW"] + counts[f"{source}_FAST"]
        rows.append(
            {
                "from_state": source,
                "to_state": target,
                "count": count,
                "probability": count / denominator if denominator else math.nan,
            }
        )
    return rows


# -----------------------------------------------------------------------------
# Plotting
# -----------------------------------------------------------------------------


def plot_histogram(
    values: Iterable[float],
    output_path: Path,
    title: str,
    xlabel: str,
    bins: int,
    dpi: int,
    facecolor
) -> None:
    """Plot a percentage histogram with a median line and summary."""
    data = finite(values)
    if data.size == 0:
        return

    median = float(np.median(data))
    weights = np.full(data.shape, 100.0 / data.size, dtype=float)
    fig, ax = make_figure()
    ax.hist(
        data,
        bins=bins,
        weights=weights,
        color=facecolor,
        edgecolor=HISTOGRAM_EDGE,
        linewidth=0.6,
    )
    ax.axvline(median, color=LINE_COLOR, linestyle="--", linewidth=1.2)
    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel("Relative frequency (%)")
    ax.text(
        0.98,
        0.95,
        f"n = {data.size}\nmedian = {median:.3g}",
        transform=ax.transAxes,
        ha="right",
        va="top",
    )
    save_figure(fig, output_path, dpi)


def plot_threshold_band(
    speeds: np.ndarray,
    threshold: float,
    half_width: float,
    unit: str,
    bins: int,
    output_path: Path,
    dpi: int,
) -> None:
    """Plot speed distribution with Otsu and hysteresis thresholds."""

    weights = np.full(
        speeds.shape,
        100.0 / speeds.size,
        dtype=float,
    )

    lower = threshold - half_width
    upper = threshold + half_width

    fig, ax = make_figure(FIGSIZE_WIDE)

    _, bin_edges, patches = ax.hist(
        speeds,
        bins=bins,
        weights=weights,
        edgecolor=HISTOGRAM_EDGE,
        linewidth=0.6,
    )

    for patch, left, right in zip(
        patches,
        bin_edges[:-1],
        bin_edges[1:],
    ):
        centre = 0.5 * (left + right)

        if centre < lower:
            patch.set_facecolor(SLOW_COLOR)
        elif centre > upper:
            patch.set_facecolor(FAST_COLOR)
        else:
            patch.set_facecolor(HYSTERESIS_COLOR)

    ax.axvline(
        threshold,
        color=LINE_COLOR,
        linestyle="--",
        linewidth=1.5,
        zorder=4,
    )

    if half_width > 0:
        ax.axvline(
            lower,
            color=REFERENCE_COLOR,
            linestyle=":",
            linewidth=1.5,
            zorder=4,
        )
        ax.axvline(
            upper,
            color=REFERENCE_COLOR,
            linestyle=":",
            linewidth=1.5,
            zorder=4,
        )

    ymax = ax.get_ylim()[1]

    xmin, xmax = ax.get_xlim()

    if half_width > 0 and DISPLAY_FAST_SLOW_LEGEND:
        ax.text(
            xmin + 0.18 * (xmax - xmin),
            ymax * 0.82,
            "SLOW",
            color=SLOW_COLOR,
            ha="center",
            va="center",
            fontweight="bold",
        )

        ax.text(
            xmin + 0.68 * (xmax - xmin),
            ymax * 0.82,
            "FAST",
            color=FAST_COLOR,
            ha="center",
            va="center",
            fontweight="bold",
        )

    ax.set_title(
        f"Binary state assignment with hysteresis ±{half_width:g} {unit}/s"
    )
    ax.set_xlabel(f"Speed ({unit}/s)")
    ax.set_ylabel("Relative frequency (%)")

    save_figure(fig, output_path, dpi)


def plot_transition_probabilities(
    transitions: list[dict],
    output_path: Path,
    half_width: float,
    unit: str,
    dpi: int,
) -> None:
    """Plot the four conditional state-transition probabilities."""
    labels = ["SLOW→SLOW", "SLOW→FAST", "FAST→SLOW", "FAST→FAST"]
    probabilities = [row["probability"] for row in transitions]
    fig, ax = make_figure(FIGSIZE_WIDE)
    ax.bar(labels, probabilities, color=HISTOGRAM_FACE, edgecolor=HISTOGRAM_EDGE)
    ax.set_ylim(0.0, 1.0)
    ax.set_title(f"State transitions; hysteresis ±{half_width:g} {unit}/s")
    ax.set_ylabel("Probability per step")
    ax.tick_params(axis="x", rotation=25)
    save_figure(fig, output_path, dpi)


def plot_sensitivity_lines(
    summary_rows: list[dict],
    output_dir: Path,
    unit: str,
    dpi: int,
) -> None:
    """Create cross-width sensitivity plots."""

    selected_total_width = 50.0
    selected_half_width = selected_total_width / 2.0

    widths = np.asarray(
        [row["hysteresis_half_width"] for row in summary_rows]
    )

    specifications = [
        (
            "median_episode_duration.png",
            "Median episode duration",
            "Duration (s)",
            "median_slow_duration_s",
            "median_fast_duration_s",
        ),
        (
            "median_episode_length.png",
            "Median episode length",
            f"Length ({unit})",
            f"median_slow_length_{unit}",
            f"median_fast_length_{unit}",
        ),
        (
            "one_step_episode_fraction.png",
            "One-step episode fraction",
            "Episodes with one step (%)",
            "slow_one_step_percent",
            "fast_one_step_percent",
        ),
        (
            "state_occupancy.png",
            "State occupancy",
            "Observations (%)",
            "slow_occupancy_percent",
            "fast_occupancy_percent",
        ),
        (
            "episode_count.png",
            "Number of episodes",
            "Episode count",
            "n_slow_episodes",
            "n_fast_episodes",
        ),
    ]

    for filename, title, ylabel, slow_key, fast_key in specifications:
        fig, ax = make_figure()

        ax.plot(
            widths,
            [row[slow_key] for row in summary_rows],
            marker="o",
            linewidth=1.8,
            label="SLOW",
        )

        ax.plot(
            widths,
            [row[fast_key] for row in summary_rows],
            marker="o",
            linewidth=1.8,
            label="FAST",
        )

        # Selected total hysteresis width = 25 µm/s,
        # corresponding to a half-width of 12.5 µm/s.
        ax.axvline(
            selected_half_width,
            color="0.35",
            linestyle="--",
            linewidth=1.2,
            zorder=1,
        )

        ax.set_title(title)
        ax.set_xlabel(f"Hysteresis half-width ({unit}/s)")
        ax.set_ylabel(ylabel)
        ax.legend(frameon=False)

        save_figure(
            fig,
            output_dir / filename,
            dpi,
        )

    transition_specs = [
        ("p_slow_slow", "SLOW→SLOW"),
        ("p_slow_fast", "SLOW→FAST"),
        ("p_fast_slow", "FAST→SLOW"),
        ("p_fast_fast", "FAST→FAST"),
    ]

    fig, ax = make_figure(FIGSIZE_WIDE)

    for key, label in transition_specs:
        ax.plot(
            widths,
            [row[key] for row in summary_rows],
            marker="o",
            linewidth=1.6,
            label=label,
        )

    ax.axvline(
        selected_half_width,
        color="0.35",
        linestyle="--",
        linewidth=1.2,
        zorder=1,
    )

    ax.set_ylim(0.0, 1.0)
    ax.set_title("Transition-probability sensitivity")
    ax.set_xlabel(f"Hysteresis half-width ({unit}/s)")
    ax.set_ylabel("Probability per step")
    ax.legend(frameon=False, ncol=2)

    save_figure(
        fig,
        output_dir / "transition_probability_sensitivity.png",
        dpi,
    )

def safe_median(values: Sequence[float]) -> float:
    """Return a median, or NaN for an empty sequence."""
    return float(np.median(values)) if values else math.nan


def summarise_segmentation(
    half_width: float,
    threshold: float,
    episodes: list[dict],
    state_counts: dict[str, int],
    transitions: list[dict],
    unit: str,
) -> dict:
    """Summarise one hysteresis segmentation for sensitivity analysis."""
    fast = [row for row in episodes if row["state"] == "FAST"]
    slow = [row for row in episodes if row["state"] == "SLOW"]
    total_states = state_counts["FAST"] + state_counts["SLOW"]
    probability = {
        f"p_{row['from_state'].lower()}_{row['to_state'].lower()}": row[
            "probability"
        ]
        for row in transitions
    }

    return {
        "otsu_threshold": threshold,
        "hysteresis_half_width": half_width,
        "lower_threshold": threshold - half_width,
        "upper_threshold": threshold + half_width,
        "n_episodes": len(episodes),
        "n_slow_episodes": len(slow),
        "n_fast_episodes": len(fast),
        "slow_one_step_percent": (
            100.0 * sum(row["n_steps"] == 1 for row in slow) / len(slow)
            if slow
            else math.nan
        ),
        "fast_one_step_percent": (
            100.0 * sum(row["n_steps"] == 1 for row in fast) / len(fast)
            if fast
            else math.nan
        ),
        "median_slow_duration_s": safe_median(
            [float(row["duration_s"]) for row in slow]
        ),
        "median_fast_duration_s": safe_median(
            [float(row["duration_s"]) for row in fast]
        ),
        f"median_slow_length_{unit}": safe_median(
            [float(row[f"length_{unit}"]) for row in slow]
        ),
        f"median_fast_length_{unit}": safe_median(
            [float(row[f"length_{unit}"]) for row in fast]
        ),
        "slow_occupancy_percent": (
            100.0 * state_counts["SLOW"] / total_states if total_states else math.nan
        ),
        "fast_occupancy_percent": (
            100.0 * state_counts["FAST"] / total_states if total_states else math.nan
        ),
        **probability,
    }


# -----------------------------------------------------------------------------
# Command-line interface
# -----------------------------------------------------------------------------


def parse_widths(text: str) -> list[float]:
    """Parse comma-separated non-negative hysteresis half-widths."""
    try:
        widths = [float(item.strip()) for item in text.split(",") if item.strip()]
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            "Hysteresis widths must be comma-separated numbers."
        ) from error
    if not widths:
        raise argparse.ArgumentTypeError("At least one hysteresis width is required.")
    if any(width < 0 for width in widths):
        raise argparse.ArgumentTypeError("Hysteresis widths must be non-negative.")
    return sorted(set(widths))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "metrics_dir",
        type=Path,
        help="Directory containing step_metrics.csv.",
    )
    parser.add_argument(
        "-o",
        "--outdir",
        type=Path,
        default=None,
        help=(
            "Output directory. Default: "
            "METRICS_DIR/fast_slow_hysteresis_sensitivity"
        ),
    )
    parser.add_argument(
        "--hysteresis-widths",
        type=parse_widths,
        default=parse_widths("0,5,10,15,20,30,40"),
        help=(
            "Comma-separated symmetric half-widths in speed units. "
            "Default: 0,5,10,15,20,30,40"
        ),
    )
    parser.add_argument(
        "--otsu-bins",
        type=int,
        default=256,
        help="Number of histogram bins used by Otsu. Default: 256",
    )
    parser.add_argument(
        "--bins",
        type=int,
        default=50,
        help="Number of bins in duration/length histograms. Default: 50",
    )
    parser.add_argument(
        "--dpi",
        type=int,
        default=300,
        help="Output resolution in dots per inch. Default: 300",
    )
    args = parser.parse_args()
    if args.otsu_bins < 2:
        parser.error("--otsu-bins must be >= 2")
    if args.bins < 1:
        parser.error("--bins must be >= 1")
    if args.dpi < 1:
        parser.error("--dpi must be >= 1")
    return args


def width_directory_name(width: float) -> str:
    """Return a filesystem-friendly label for a hysteresis half-width."""
    return f"hysteresis_{width:g}".replace(".", "p")


def main() -> int:
    args = parse_args()
    output_root = args.outdir or (
        args.metrics_dir / "fast_slow_hysteresis_sensitivity"
    )
    output_root.mkdir(parents=True, exist_ok=True)

    step_rows = read_csv(args.metrics_dir / "step_metrics.csv")
    if not step_rows:
        raise ValueError("step_metrics.csv is empty.")

    columns = step_rows[0].keys()
    speed_column = find_column(columns, "speed_")
    distance_column = find_column(columns, "distance_")
    unit = distance_column.removeprefix("distance_")
    grouped_steps = group_steps_by_track(step_rows)
    speeds = finite(numeric(row, speed_column) for row in step_rows)
    threshold = otsu_threshold(speeds, bins=args.otsu_bins)

    write_csv(
        output_root / "otsu_threshold.csv",
        [
            {
                "threshold": threshold,
                "method": "Otsu",
                "otsu_bins": args.otsu_bins,
                "unit": f"{unit}/s",
            }
        ],
    )

    summary_rows: list[dict] = []

    for half_width in args.hysteresis_widths:
        case_dir = output_root / width_directory_name(half_width)
        case_dir.mkdir(parents=True, exist_ok=True)

        episodes, state_rows, counts, state_counts = segment_tracks(
            grouped_steps=grouped_steps,
            speed_column=speed_column,
            distance_column=distance_column,
            unit=unit,
            threshold=threshold,
            half_width=half_width,
        )
        transitions = transition_table(counts)
        fast = [row for row in episodes if row["state"] == "FAST"]
        slow = [row for row in episodes if row["state"] == "SLOW"]

        write_csv(case_dir / "step_states.csv", state_rows)
        write_csv(case_dir / "motion_episodes.csv", episodes)
        write_csv(case_dir / "transition_probabilities.csv", transitions)
        write_csv(
            case_dir / "thresholds.csv",
            [
                {
                    "otsu_threshold": threshold,
                    "hysteresis_half_width": half_width,
                    "lower_threshold": threshold - half_width,
                    "upper_threshold": threshold + half_width,
                    "unit": f"{unit}/s",
                }
            ],
        )

        plot_threshold_band(
            speeds,
            threshold,
            half_width,
            unit,
            args.bins,
            case_dir / "01_threshold_and_hysteresis.png",
            args.dpi,
        )
        plot_transition_probabilities(
            transitions,
            case_dir / "02_transition_probabilities.png",
            half_width,
            unit,
            args.dpi,
        )
        plot_histogram(
            (row["duration_s"] for row in fast),
            case_dir / "03_fast_duration.png",
            f"FAST episode duration; hysteresis ±{half_width:g} {unit}/s",
            "Duration (s)",
            args.bins,
            args.dpi,
            FAST_COLOR,
        )
        plot_histogram(
            (row["duration_s"] for row in slow),
            case_dir / "04_slow_duration.png",
            f"SLOW episode duration; hysteresis ±{half_width:g} {unit}/s",
            "Duration (s)",
            args.bins,
            args.dpi,
            SLOW_COLOR,
        )
        plot_histogram(
            (row[f"length_{unit}"] for row in fast),
            case_dir / "05_fast_length.png",
            f"FAST episode length; hysteresis ±{half_width:g} {unit}/s",
            f"Length ({unit})",
            args.bins,
            args.dpi,
            FAST_COLOR,
        )
        plot_histogram(
            (row[f"length_{unit}"] for row in slow),
            case_dir / "06_slow_length.png",
            f"SLOW episode length; hysteresis ±{half_width:g} {unit}/s",
            f"Length ({unit})",
            args.bins,
            args.dpi,
            SLOW_COLOR,
        )

        summary_rows.append(
            summarise_segmentation(
                half_width,
                threshold,
                episodes,
                state_counts,
                transitions,
                unit,
            )
        )

    write_csv(output_root / "hysteresis_sensitivity_summary.csv", summary_rows)
    plot_sensitivity_lines(
        summary_rows,
        output_root / "comparison_plots",
        unit,
        args.dpi,
    )

    print(f"Otsu threshold: {threshold:.6g} {unit}/s")
    print(
        "Hysteresis half-widths: "
        + ", ".join(f"{width:g}" for width in args.hysteresis_widths)
        + f" {unit}/s"
    )
    print(f"Results written to: {output_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
