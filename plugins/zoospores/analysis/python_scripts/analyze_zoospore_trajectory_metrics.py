#!/usr/bin/env python3
"""Analyse zoospore trajectory metrics and generate publication-ready figures.

The script expects the following CSV files in ``metrics_dir``:

- ``step_metrics.csv``
- ``turn_metrics.csv``
- ``track_metrics.csv``
- ``msd.csv``
- ``direction_autocorrelation.csv``

All figures use the same typography as ``plot_trajectory_overview.py`` and a
fixed height of 6.0 inches. Figures are saved without content-dependent
cropping so their exported dimensions remain predictable.
"""

from __future__ import annotations

import argparse
import csv
import math
from collections import defaultdict
from collections.abc import Iterable, Sequence
from pathlib import Path

import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
from scipy import stats


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
FIGSIZE_WIDE = (10.0, FIGURE_HEIGHT)
FIGSIZE_COMPACT = (7.0, FIGURE_HEIGHT)

HISTOGRAM_FACE = "0.82"
HISTOGRAM_EDGE = "0.30"
LINE_COLOR = "0.10"
REFERENCE_COLOR = "0.50"
SCATTER_COLOR = "0.72"
BAND_COLOR = "0.82"


# -----------------------------------------------------------------------------
# Generic I/O and numerical helpers
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
    resolved_fields = list(fieldnames) if fieldnames is not None else (
        list(rows[0].keys()) if rows else []
    )

    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=resolved_fields,
            extrasaction="ignore",
        )
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
            f"Expected exactly one column beginning with {prefix!r}; "
            f"found {matches}"
        )
    return matches[0]


def save_figure(fig: mpl.figure.Figure, path: Path, dpi: int) -> None:
    """Save a figure without content-dependent cropping."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=dpi)
    plt.close(fig)


def make_figure(
    figsize: tuple[float, float] = FIGSIZE_STANDARD,
) -> tuple[mpl.figure.Figure, mpl.axes.Axes]:
    """Create a figure using a consistent publication layout."""
    fig, ax = plt.subplots(figsize=figsize)
    fig.subplots_adjust(left=0.14, right=0.97, bottom=0.15, top=0.88)
    return fig, ax


# -----------------------------------------------------------------------------
# Plotting helpers
# -----------------------------------------------------------------------------


def plot_histogram(
    values: Iterable[float],
    output_path: Path,
    title: str,
    xlabel: str,
    bins: int,
    dpi: int,
    vertical_reference: float | None = None,
    legend_pos_x : float = 0.98,
    legend_pos_y : float = 0.95,
    horizontal_alignment : string = "right",
) -> None:
    """Plot a percentage histogram with a median line and compact summary."""
    data = finite(values)
    if data.size == 0:
        return

    median = float(np.median(data))
    fig, ax = make_figure()
    # Express each histogram bin as a percentage of all finite
    # observations. The bar heights therefore sum to 100%, which makes
    # distributions directly comparable across datasets and simulations
    # with different sample sizes.
    weights = np.full(data.shape, 100.0 / data.size, dtype=float)
    ax.hist(
        data,
        bins=bins,
        weights=weights,
        color=HISTOGRAM_FACE,
        edgecolor=HISTOGRAM_EDGE,
        linewidth=0.6,
    )
    ax.axvline(median, color=LINE_COLOR, linestyle="--", linewidth=1.2)

    if vertical_reference is not None:
        ax.axvline(
            vertical_reference,
            color=LINE_COLOR,
            linestyle=":",
            linewidth=1.6,
        )

    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel("Relative frequency (%)")
    ax.text(
        legend_pos_x,
        legend_pos_y,
        f"n = {data.size}\nmedian = {median:.3g}",
        transform=ax.transAxes,
        ha=horizontal_alignment,
        va="top",
    )
    save_figure(fig, output_path, dpi)


def plot_lag_curve(
    x: Sequence[float],
    y: Sequence[float],
    output_path: Path,
    title: str,
    xlabel: str,
    ylabel: str,
    dpi: int,
    horizontal_zero: bool = True,
) -> None:
    """Plot a lag-dependent metric using a consistent line style."""
    fig, ax = make_figure()
    ax.plot(x, y, color=LINE_COLOR, marker="o", markersize=4, linewidth=1.5)
    if horizontal_zero:
        ax.axhline(0.0, color=REFERENCE_COLOR, linewidth=0.8)
    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    save_figure(fig, output_path, dpi)


def plot_lag_curve_with_band(
    x: Sequence[float],
    y: Sequence[float],
    y_lower: Sequence[float],
    y_upper: Sequence[float],
    output_path: Path,
    title: str,
    xlabel: str,
    ylabel: str,
    dpi: int,
    line_label: str = "Mean",
    band_label: str = "25th–75th percentile",
    horizontal_zero: bool = False,
) -> None:
    """Plot a lag-dependent mean with a shaded interquartile envelope."""
    x_array = np.asarray(x, dtype=float)
    y_array = np.asarray(y, dtype=float)
    lower_array = np.asarray(y_lower, dtype=float)
    upper_array = np.asarray(y_upper, dtype=float)

    valid = (
        np.isfinite(x_array)
        & np.isfinite(y_array)
        & np.isfinite(lower_array)
        & np.isfinite(upper_array)
    )
    x_array = x_array[valid]
    y_array = y_array[valid]
    lower_array = lower_array[valid]
    upper_array = upper_array[valid]

    if x_array.size == 0:
        return

    fig, ax = make_figure()
    ax.fill_between(
        x_array,
        lower_array,
        upper_array,
        color="0.88",
        alpha=0.7,
        linewidth=0.0,
        label=band_label,
        zorder=1,
    )
    ax.plot(
        x_array,
        y_array,
        color=LINE_COLOR,
        linewidth=1.8,
        label=line_label,
        zorder=2,
    )
    if horizontal_zero:
        ax.axhline(0.0, color=REFERENCE_COLOR, linewidth=0.8, zorder=0)

    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.legend(frameon=False)
    save_figure(fig, output_path, dpi)


def plot_relationship(
    x: np.ndarray,
    y: np.ndarray,
    output_path: Path,
    title: str,
    xlabel: str,
    ylabel: str,
    dpi: int,
    smooth_fraction: float,
    horizontal_zero: bool = False,
    point_size: float = 4.0,
    point_alpha: float = 0.12,
) -> None:
    """Plot observations and a robust LOWESS curve."""
    fig, ax = make_figure()
    scatter_with_lowess(
        ax,
        x,
        y,
        fraction=smooth_fraction,
        point_size=point_size,
        point_alpha=point_alpha,
    )
    if horizontal_zero:
        ax.axhline(0.0, color=REFERENCE_COLOR, linewidth=0.8)
    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    save_figure(fig, output_path, dpi)


# -----------------------------------------------------------------------------
# Statistical helpers
# -----------------------------------------------------------------------------


def otsu_threshold(values: np.ndarray, bins: int = 256) -> float:
    """Estimate a binary threshold using Otsu's between-class variance."""
    data = values[np.isfinite(values)]
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
    mean_right[valid] = (
        total_sum - sum_left[valid]
    ) / weight_right[valid]

    score = weight_left * weight_right * (mean_left - mean_right) ** 2
    score[~valid] = -np.inf
    return float(centres[int(np.argmax(score))])


def group_steps_by_track(
    rows: list[dict[str, str]],
) -> dict[int, list[dict[str, str]]]:
    """Group step rows by track and sort each group by step index."""
    grouped: dict[int, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        grouped[int(float(row["track_id"]))].append(row)

    for track_rows in grouped.values():
        track_rows.sort(key=lambda row: int(float(row["step_index"])))

    return dict(grouped)


def pearson_correlation(x: np.ndarray, y: np.ndarray) -> float:
    """Return Pearson's r for finite paired values."""
    valid = np.isfinite(x) & np.isfinite(y)
    x_valid = x[valid]
    y_valid = y[valid]

    if (
        x_valid.size < 3
        or np.std(x_valid) == 0
        or np.std(y_valid) == 0
    ):
        return math.nan

    return float(np.corrcoef(x_valid, y_valid)[0, 1])


def benjamini_hochberg(p_values: Sequence[float]) -> np.ndarray:
    """Return Benjamini–Hochberg adjusted P values."""
    p = np.asarray(p_values, dtype=float)
    adjusted = np.full(p.shape, np.nan, dtype=float)
    valid_indices = np.flatnonzero(np.isfinite(p))
    if valid_indices.size == 0:
        return adjusted

    order = valid_indices[np.argsort(p[valid_indices])]
    ranked = p[order]
    m = ranked.size
    corrected = ranked * m / np.arange(1, m + 1)
    corrected = np.minimum.accumulate(corrected[::-1])[::-1]
    adjusted[order] = np.clip(corrected, 0.0, 1.0)
    return adjusted


def format_p_value(value: float) -> str:
    """Format a P value for compact CSV and figure reporting."""
    if not np.isfinite(value):
        return "NA"
    if value < 1e-300:
        return "<1e-300"
    if value < 0.001:
        return f"{value:.2e}"
    return f"{value:.3f}"


def relationship_statistics(
    x: np.ndarray,
    y: np.ndarray,
    n_quantile_bins: int = 10,
) -> dict:
    """Test linear, monotonic and general binned dependence between variables."""
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    valid = np.isfinite(x) & np.isfinite(y)
    x = x[valid]
    y = y[valid]

    result = {
        "n": int(x.size),
        "pearson_r": math.nan,
        "pearson_p": math.nan,
        "spearman_rho": math.nan,
        "spearman_p": math.nan,
        "kruskal_h": math.nan,
        "kruskal_p": math.nan,
        "kruskal_epsilon_squared": math.nan,
        "n_quantile_bins": 0,
    }
    if x.size < 3 or np.std(x) == 0 or np.std(y) == 0:
        return result

    pearson = stats.pearsonr(x, y)
    spearman = stats.spearmanr(x, y)
    result.update(
        {
            "pearson_r": float(pearson.statistic),
            "pearson_p": float(pearson.pvalue),
            "spearman_rho": float(spearman.statistic),
            "spearman_p": float(spearman.pvalue),
        }
    )

    # A Kruskal–Wallis test across equal-frequency x bins detects dependence
    # that is non-monotonic (for example the U-shaped speed–turn relation).
    quantile_edges = np.unique(
        np.quantile(x, np.linspace(0.0, 1.0, n_quantile_bins + 1))
    )
    if quantile_edges.size >= 3:
        bin_ids = np.digitize(x, quantile_edges[1:-1], right=False)
        groups = [y[bin_ids == i] for i in range(quantile_edges.size - 1)]
        groups = [group for group in groups if group.size > 0]
        if len(groups) >= 2:
            test = stats.kruskal(*groups)
            h = float(test.statistic)
            k = len(groups)
            n = x.size
            epsilon_squared = max(0.0, (h - k + 1) / (n - k)) if n > k else math.nan
            result.update(
                {
                    "kruskal_h": h,
                    "kruskal_p": float(test.pvalue),
                    "kruskal_epsilon_squared": float(epsilon_squared),
                    "n_quantile_bins": k,
                }
            )
    return result


def summarise_lag_values(
    lag: int,
    lag_s: float,
    values: Sequence[float],
    value_name: str,
) -> dict:
    """Summarise per-trajectory lag values and test them against zero."""
    data = finite(values)
    if data.size == 0:
        return {
            "lag_steps": lag,
            "lag_s": lag_s,
            f"mean_{value_name}": math.nan,
            f"median_{value_name}": math.nan,
            f"q25_{value_name}": math.nan,
            f"q75_{value_name}": math.nan,
            f"sd_{value_name}": math.nan,
            "n_tracks": 0,
            "wilcoxon_statistic": math.nan,
            "wilcoxon_p": math.nan,
        }

    nonzero = data[data != 0]
    if nonzero.size:
        try:
            wilcoxon = stats.wilcoxon(
                nonzero,
                alternative="two-sided",
                zero_method="wilcox",
                method="auto",
            )
            statistic = float(wilcoxon.statistic)
            p_value = float(wilcoxon.pvalue)
        except ValueError:
            statistic = math.nan
            p_value = math.nan
    else:
        statistic = math.nan
        p_value = math.nan

    return {
        "lag_steps": lag,
        "lag_s": lag_s,
        f"mean_{value_name}": float(np.mean(data)),
        f"median_{value_name}": float(np.median(data)),
        f"q25_{value_name}": float(np.percentile(data, 25)),
        f"q75_{value_name}": float(np.percentile(data, 75)),
        f"sd_{value_name}": float(np.std(data, ddof=1)) if data.size > 1 else math.nan,
        "n_tracks": int(data.size),
        "wilcoxon_statistic": statistic,
        "wilcoxon_p": p_value,
    }


def calculate_speed_autocorrelation_by_track(
    grouped_steps: dict[int, list[dict[str, str]]],
    speed_column: str,
    time_step: float,
    max_lag: int,
) -> list[dict]:
    """Calculate per-trajectory speed autocorrelation and cross-track summaries."""
    output: list[dict] = []
    for lag in range(1, max_lag + 1):
        correlations: list[float] = []
        for rows in grouped_steps.values():
            values = np.asarray([numeric(row, speed_column) for row in rows], dtype=float)
            if values.size <= lag:
                continue
            previous = values[:-lag]
            following = values[lag:]
            correlation = pearson_correlation(previous, following)
            if np.isfinite(correlation):
                correlations.append(correlation)
        output.append(
            summarise_lag_values(
                lag,
                lag * time_step,
                correlations,
                "speed_autocorrelation",
            )
        )

    adjusted = benjamini_hochberg([row["wilcoxon_p"] for row in output])
    for row, q_value in zip(output, adjusted):
        row["wilcoxon_q_bh"] = float(q_value) if np.isfinite(q_value) else math.nan
    return output


def calculate_direction_autocorrelation_by_track(
    grouped_steps: dict[int, list[dict[str, str]]],
    heading_column: str,
    time_step: float,
    max_lag: int,
) -> list[dict]:
    """Calculate per-trajectory directional persistence as mean cos(Δheading)."""
    output: list[dict] = []
    for lag in range(1, max_lag + 1):
        persistence_values: list[float] = []
        for rows in grouped_steps.values():
            headings = np.asarray([numeric(row, heading_column) for row in rows], dtype=float)
            if headings.size <= lag:
                continue
            previous = headings[:-lag]
            following = headings[lag:]
            valid = np.isfinite(previous) & np.isfinite(following)
            if not np.any(valid):
                continue
            delta = np.deg2rad(following[valid] - previous[valid])
            persistence_values.append(float(np.mean(np.cos(delta))))
        output.append(
            summarise_lag_values(
                lag,
                lag * time_step,
                persistence_values,
                "direction_autocorrelation",
            )
        )

    adjusted = benjamini_hochberg([row["wilcoxon_p"] for row in output])
    for row, q_value in zip(output, adjusted):
        row["wilcoxon_q_bh"] = float(q_value) if np.isfinite(q_value) else math.nan
    return output


def binned_summary(x: np.ndarray, y: np.ndarray, n_bins: int) -> list[dict]:
    """Summarise y within equally spaced bins of x."""
    valid = np.isfinite(x) & np.isfinite(y)
    x_valid = x[valid]
    y_valid = y[valid]
    if x_valid.size == 0:
        return []

    edges = np.linspace(x_valid.min(), x_valid.max(), n_bins + 1)
    bin_index = np.digitize(x_valid, edges[1:-1])
    output: list[dict] = []

    for index in range(n_bins):
        values = y_valid[bin_index == index]
        if values.size == 0:
            continue
        output.append(
            {
                "x_bin_start": float(edges[index]),
                "x_bin_end": float(edges[index + 1]),
                "x_bin_center": float(
                    (edges[index] + edges[index + 1]) / 2.0
                ),
                "n": int(values.size),
                "mean_y": float(np.mean(values)),
                "median_y": float(np.median(values)),
                "q25_y": float(np.percentile(values, 25)),
                "q75_y": float(np.percentile(values, 75)),
            }
        )

    return output


def robust_lowess(
    x: np.ndarray,
    y: np.ndarray,
    fraction: float = 0.20,
    n_points: int = 250,
    robust_iterations: int = 2,
) -> tuple[np.ndarray, np.ndarray]:
    """Return a robust LOWESS curve without depending on statsmodels."""
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    valid = np.isfinite(x) & np.isfinite(y)
    x = x[valid]
    y = y[valid]

    if x.size < 3:
        return np.asarray([]), np.asarray([])

    order = np.argsort(x)
    x = x[order]
    y = y[order]
    grid = np.linspace(x.min(), x.max(), n_points)
    span = max(3, min(x.size, int(math.ceil(fraction * x.size))))
    robust_weights = np.ones(x.size, dtype=float)

    def fit_at(x0: float, weights_robust: np.ndarray) -> float:
        distances = np.abs(x - x0)
        neighbours = np.argpartition(distances, span - 1)[:span]
        max_distance = distances[neighbours].max()

        if max_distance <= 0:
            return float(
                np.average(y[neighbours], weights=weights_robust[neighbours])
            )

        u = distances[neighbours] / max_distance
        tricube = (1.0 - u**3) ** 3
        weights = tricube * weights_robust[neighbours]
        design = np.column_stack(
            (np.ones(neighbours.size), x[neighbours] - x0)
        )
        sqrt_weights = np.sqrt(weights)
        beta = np.linalg.lstsq(
            design * sqrt_weights[:, None],
            y[neighbours] * sqrt_weights,
            rcond=None,
        )[0]
        return float(beta[0])

    for iteration in range(max(0, robust_iterations) + 1):
        fitted = np.asarray([fit_at(x0, robust_weights) for x0 in x])
        if iteration == robust_iterations:
            break

        residuals = y - fitted
        scale = np.median(np.abs(residuals))
        if not np.isfinite(scale) or scale <= 0:
            break

        u = np.clip(residuals / (6.0 * scale), -1.0, 1.0)
        robust_weights = (1.0 - u**2) ** 2
        robust_weights[np.abs(residuals) >= 6.0 * scale] = 0.0

    smooth = np.asarray([fit_at(x0, robust_weights) for x0 in grid])
    return grid, smooth


def scatter_with_lowess(
    ax: mpl.axes.Axes,
    x: np.ndarray,
    y: np.ndarray,
    fraction: float = 0.20,
    max_points: int = 50_000,
    max_fit_points: int = 5_000,
    seed: int = 42,
    point_size: float = 4.0,
    point_alpha: float = 0.12,
) -> None:
    """Draw light-gray observations and a black robust LOWESS curve."""
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    valid = np.isfinite(x) & np.isfinite(y)
    x = x[valid]
    y = y[valid]

    if x.size == 0:
        return

    rng = np.random.default_rng(seed)

    if x.size > max_points:
        plot_indices = rng.choice(x.size, max_points, replace=False)
        x_plot = x[plot_indices]
        y_plot = y[plot_indices]
    else:
        x_plot = x
        y_plot = y

    ax.scatter(
        x_plot,
        y_plot,
        s=point_size,
        alpha=point_alpha,
        color=SCATTER_COLOR,
        edgecolors="none",
        rasterized=True,
        zorder=1,
    )

    # The in-house LOWESS implementation scales quadratically with the
    # number of fitted observations. Fitting millions of points would be
    # prohibitively slow and does not materially improve a visual smoother.
    # Use a fixed-seed subsample for a reproducible approximation while
    # retaining up to ``max_points`` observations in the displayed scatter.
    if x.size > max_fit_points:
        fit_indices = rng.choice(x.size, max_fit_points, replace=False)
        x_fit = x[fit_indices]
        y_fit = y[fit_indices]
    else:
        x_fit = x
        y_fit = y

    smooth_x, smooth_y = robust_lowess(
        x_fit,
        y_fit,
        fraction=fraction,
        robust_iterations=1,
    )
    if smooth_x.size:
        ax.plot(smooth_x, smooth_y, color="black", linewidth=2.2, zorder=3)


def find_optional_column(columns: Iterable[str], prefixes: Sequence[str]) -> str | None:
    """Return the first uniquely matching column among candidate prefixes."""
    column_list = list(columns)
    for prefix in prefixes:
        matches = [column for column in column_list if column.startswith(prefix)]
        if len(matches) == 1:
            return matches[0]
    return None


def reconstruct_track_positions(
    rows: list[dict[str, str]],
    unit: str,
) -> np.ndarray:
    """Reconstruct relative 2-D positions from step-level coordinate data."""
    if not rows:
        return np.empty((0, 2), dtype=float)

    columns = rows[0].keys()
    dx_column = find_optional_column(columns, (f"dx_{unit}", "dx_", "delta_x_"))
    dy_column = find_optional_column(columns, (f"dy_{unit}", "dy_", "delta_y_"))

    if dx_column is not None and dy_column is not None:
        increments = np.asarray(
            [
                [numeric(row, dx_column), numeric(row, dy_column)]
                for row in rows
            ],
            dtype=float,
        )
        if not np.all(np.isfinite(increments)):
            return np.empty((0, 2), dtype=float)
        return np.vstack((np.zeros((1, 2)), np.cumsum(increments, axis=0)))

    x_start = find_optional_column(columns, (f"x_start_{unit}", "x_start_"))
    y_start = find_optional_column(columns, (f"y_start_{unit}", "y_start_"))
    x_end = find_optional_column(columns, (f"x_end_{unit}", "x_end_"))
    y_end = find_optional_column(columns, (f"y_end_{unit}", "y_end_"))

    if None not in (x_start, y_start, x_end, y_end):
        positions = [
            [numeric(row, x_start), numeric(row, y_start)]
            for row in rows
        ]
        positions.append(
            [numeric(rows[-1], x_end), numeric(rows[-1], y_end)]
        )
        array = np.asarray(positions, dtype=float)
        if np.all(np.isfinite(array)):
            return array - array[0]

    raise ValueError(
        "Cannot calculate trajectory-level MSD variability because step_metrics.csv "
        "contains neither dx/dy columns nor x_start/y_start/x_end/y_end columns."
    )


def calculate_trajectory_averaged_msd(
    grouped_steps: dict[int, list[dict[str, str]]],
    unit: str,
    time_step: float,
    max_lag: int,
    msd_column: str,
) -> list[dict]:
    """Calculate trajectory-averaged MSD and its interquartile range."""
    positions_by_track = {
        track_id: reconstruct_track_positions(rows, unit)
        for track_id, rows in grouped_steps.items()
    }

    output: list[dict] = []
    for lag in range(1, max_lag + 1):
        track_msd_values: list[float] = []
        for positions in positions_by_track.values():
            if positions.shape[0] <= lag:
                continue
            displacement = positions[lag:] - positions[:-lag]
            squared_displacement = np.sum(displacement**2, axis=1)
            squared_displacement = squared_displacement[
                np.isfinite(squared_displacement)
            ]
            if squared_displacement.size:
                track_msd_values.append(float(np.mean(squared_displacement)))

        values = np.asarray(track_msd_values, dtype=float)
        output.append(
            {
                "lag_steps": lag,
                "lag_s": lag * time_step,
                msd_column: (
                    float(np.mean(values))
                    if values.size
                    else math.nan
                ),
                f"median_{msd_column}": (
                    float(np.median(values))
                    if values.size
                    else math.nan
                ),
                f"q25_{msd_column}": (
                    float(np.percentile(values, 25))
                    if values.size
                    else math.nan
                ),
                f"q75_{msd_column}": (
                    float(np.percentile(values, 75))
                    if values.size
                    else math.nan
                ),
                f"sd_{msd_column}": (
                    float(np.std(values, ddof=1))
                    if values.size > 1
                    else math.nan
                ),
                "n_tracks": int(values.size),
            }
        )

    return output


# -----------------------------------------------------------------------------
# Analysis sections
# -----------------------------------------------------------------------------


def analyse_motion_states(
    step_rows: list[dict[str, str]],
    grouped_steps: dict[int, list[dict[str, str]]],
    speed_column: str,
    distance_column: str,
    unit: str,
    output_dir: Path,
    bins: int,
    dpi: int,
    manual_threshold: float | None,
) -> tuple[float, str, list[dict], list[dict], list[dict]]:
    """Identify FAST/SLOW states and export episode-level descriptors."""
    speeds = finite(numeric(row, speed_column) for row in step_rows)
    threshold = (
        manual_threshold
        if manual_threshold is not None
        else otsu_threshold(speeds)
    )
    threshold_method = "manual" if manual_threshold is not None else "Otsu"

    plot_histogram(
        speeds,
        output_dir / "01_fast_slow_threshold.png",
        "Instantaneous speed and FAST/SLOW threshold",
        f"Speed ({unit}/s)",
        bins,
        dpi,
        vertical_reference=threshold,
    )
    write_csv(
        output_dir / "01_fast_slow_threshold.csv",
        [
            {
                "threshold": threshold,
                "method": threshold_method,
                "unit": f"{unit}/s",
            }
        ],
    )

    transition_counts = {
        "SLOW_SLOW": 0,
        "SLOW_FAST": 0,
        "FAST_SLOW": 0,
        "FAST_FAST": 0,
    }
    episodes: list[dict] = []
    episode_id = 1

    for track_id, rows in grouped_steps.items():
        usable_rows = [
            row for row in rows if np.isfinite(numeric(row, speed_column))
        ]
        states = [
            "FAST" if numeric(row, speed_column) >= threshold else "SLOW"
            for row in usable_rows
        ]

        for current, following in zip(states[:-1], states[1:]):
            transition_counts[f"{current}_{following}"] += 1

        start_index = 0
        while start_index < len(usable_rows):
            state = states[start_index]
            end_index = start_index + 1
            while end_index < len(usable_rows) and states[end_index] == state:
                end_index += 1

            episode_rows = usable_rows[start_index:end_index]
            episodes.append(
                {
                    "episode_id": episode_id,
                    "track_id": track_id,
                    "state": state,
                    "start_frame": int(float(episode_rows[0]["frame_start"])),
                    "end_frame": int(float(episode_rows[-1]["frame_end"])),
                    "n_steps": len(episode_rows),
                    "duration_s": sum(
                        numeric(row, "dt_s") for row in episode_rows
                    ),
                    f"length_{unit}": sum(
                        numeric(row, distance_column) for row in episode_rows
                    ),
                    f"mean_speed_{unit}_per_s": float(
                        np.mean(
                            [
                                numeric(row, speed_column)
                                for row in episode_rows
                            ]
                        )
                    ),
                }
            )
            episode_id += 1
            start_index = end_index

    write_csv(output_dir / "motion_episodes.csv", episodes)

    slow_slow = transition_counts["SLOW_SLOW"]
    slow_fast = transition_counts["SLOW_FAST"]
    fast_slow = transition_counts["FAST_SLOW"]
    fast_fast = transition_counts["FAST_FAST"]

    transitions = [
        {
            "from_state": "SLOW",
            "to_state": "SLOW",
            "count": slow_slow,
            "probability": (
                slow_slow / (slow_slow + slow_fast)
                if slow_slow + slow_fast
                else math.nan
            ),
        },
        {
            "from_state": "SLOW",
            "to_state": "FAST",
            "count": slow_fast,
            "probability": (
                slow_fast / (slow_slow + slow_fast)
                if slow_slow + slow_fast
                else math.nan
            ),
        },
        {
            "from_state": "FAST",
            "to_state": "SLOW",
            "count": fast_slow,
            "probability": (
                fast_slow / (fast_slow + fast_fast)
                if fast_slow + fast_fast
                else math.nan
            ),
        },
        {
            "from_state": "FAST",
            "to_state": "FAST",
            "count": fast_fast,
            "probability": (
                fast_fast / (fast_slow + fast_fast)
                if fast_slow + fast_fast
                else math.nan
            ),
        },
    ]
    write_csv(output_dir / "02_transition_probabilities.csv", transitions)

    fig, ax = make_figure(FIGSIZE_WIDE)
    labels = ["SLOW→SLOW", "SLOW→FAST", "FAST→SLOW", "FAST→FAST"]
    probabilities = [row["probability"] for row in transitions]
    ax.bar(
        labels,
        probabilities,
        color=HISTOGRAM_FACE,
        edgecolor=HISTOGRAM_EDGE,
    )
    ax.set_ylim(0.0, 1.0)
    ax.set_title("Motion-state transition probabilities")
    ax.set_ylabel("Probability per step")
    ax.tick_params(axis="x", rotation=25)
    save_figure(fig, output_dir / "02_transition_probabilities.png", dpi)

    fast_episodes = [row for row in episodes if row["state"] == "FAST"]
    slow_episodes = [row for row in episodes if row["state"] == "SLOW"]

    plot_histogram(
        (row["duration_s"] for row in fast_episodes),
        output_dir / "03_fast_duration.png",
        "FAST episode duration",
        "Duration (s)",
        bins,
        dpi,
    )
    plot_histogram(
        (row["duration_s"] for row in slow_episodes),
        output_dir / "04_slow_duration.png",
        "SLOW episode duration",
        "Duration (s)",
        bins,
        dpi,
    )
    plot_histogram(
        (row[f"length_{unit}"] for row in fast_episodes),
        output_dir / "05_fast_length.png",
        "FAST episode length",
        f"Length ({unit})",
        bins,
        dpi,
    )
    plot_histogram(
        (row[f"length_{unit}"] for row in slow_episodes),
        output_dir / "06_slow_length.png",
        "SLOW episode length",
        f"Length ({unit})",
        bins,
        dpi,
    )

    return (
        threshold,
        threshold_method,
        episodes,
        fast_episodes,
        slow_episodes,
    )


def analyse_kinematics(
    step_rows: list[dict[str, str]],
    turn_rows: list[dict[str, str]],
    grouped_steps: dict[int, list[dict[str, str]]],
    direction_autocorrelation_rows: list[dict[str, str]],
    speed_column: str,
    acceleration_column: str,
    absolute_acceleration_column: str,
    unit: str,
    output_dir: Path,
    bins: int,
    dpi: int,
) -> None:
    """Analyse speed, acceleration and speed autocorrelation."""
    speeds = finite(numeric(row, speed_column) for row in step_rows)
    plot_histogram(
        speeds,
        output_dir / "01_speed_distribution.png",
        "Instantaneous speed distribution",
        f"Speed ({unit}/s)",
        bins,
        dpi,
    )
    write_csv(
        output_dir / "01_speed_distribution.csv",
        [{speed_column: value} for value in speeds],
    )

    signed_acceleration = finite(
        numeric(row, acceleration_column) for row in turn_rows
    )
    absolute_acceleration = finite(
        numeric(row, absolute_acceleration_column) for row in turn_rows
    )
    plot_histogram(
        signed_acceleration,
        output_dir / "02_signed_acceleration.png",
        "Signed acceleration distribution",
        f"Acceleration ({unit}/s²)",
        bins,
        dpi,
    )
    plot_histogram(
        absolute_acceleration,
        output_dir / "03_absolute_acceleration.png",
        "Absolute acceleration distribution",
        f"Absolute acceleration ({unit}/s²)",
        bins,
        dpi,
    )
    write_csv(
        output_dir / "accelerations.csv",
        [
            {
                "track_id": row["track_id"],
                "frame": row["frame"],
                acceleration_column: numeric(row, acceleration_column),
                absolute_acceleration_column: numeric(
                    row,
                    absolute_acceleration_column,
                ),
            }
            for row in turn_rows
        ],
    )

    max_lag = (
        max(int(float(row["lag_steps"])) for row in direction_autocorrelation_rows)
        if direction_autocorrelation_rows
        else 25
    )
    time_step = float(step_rows[0]["dt_s"])
    autocorrelation_rows = calculate_speed_autocorrelation_by_track(
        grouped_steps=grouped_steps,
        speed_column=speed_column,
        time_step=time_step,
        max_lag=max_lag,
    )

    write_csv(
        output_dir / "04_speed_autocorrelation.csv",
        autocorrelation_rows,
    )
    plot_lag_curve_with_band(
        [row["lag_s"] for row in autocorrelation_rows],
        [row["mean_speed_autocorrelation"] for row in autocorrelation_rows],
        [row["q25_speed_autocorrelation"] for row in autocorrelation_rows],
        [row["q75_speed_autocorrelation"] for row in autocorrelation_rows],
        output_dir / "04_speed_autocorrelation.png",
        "Swimming speed autocorrelation",
        "Lag (s)",
        "Pearson correlation",
        dpi,
        line_label="Mean autocorrelation",
        band_label="25th–75th percentile",
        horizontal_zero=True,
    )



def analyse_steering(
    turn_rows: list[dict[str, str]],
    grouped_steps: dict[int, list[dict[str, str]]],
    direction_autocorrelation_rows: list[dict[str, str]],
    heading_column: str,
    speed_before_column: str,
    unit: str,
    output_dir: Path,
    coupling_bins: int,
    smooth_fraction: float,
    dpi: int,
) -> tuple[np.ndarray, np.ndarray, list[dict]]:
    """Analyse turning angles and speed-turn coupling."""
    signed_angles = finite(numeric(row, "turn_angle_deg") for row in turn_rows)
    absolute_angles = finite(
        numeric(row, "abs_turn_angle_deg") for row in turn_rows
    )

    plot_histogram(
        signed_angles,
        output_dir / "01_signed_turn_angle.png",
        "Signed turning-angle distribution",
        "Turning angle (degrees)",
        72,
        dpi,
    )
    plot_histogram(
        absolute_angles,
        output_dir / "02_absolute_turn_angle.png",
        "Absolute turning-angle distribution",
        "Absolute turning angle (degrees)",
        36,
        dpi,
    )
    write_csv(
        output_dir / "turning_angles.csv",
        [
            {
                "track_id": row["track_id"],
                "frame": row["frame"],
                "turn_angle_deg": numeric(row, "turn_angle_deg"),
                "abs_turn_angle_deg": numeric(row, "abs_turn_angle_deg"),
            }
            for row in turn_rows
        ],
    )

    speed_before = np.asarray(
        [numeric(row, speed_before_column) for row in turn_rows],
        dtype=float,
    )
    absolute_turn = np.asarray(
        [numeric(row, "abs_turn_angle_deg") for row in turn_rows],
        dtype=float,
    )
    binned_rows = binned_summary(speed_before, absolute_turn, coupling_bins)
    write_csv(
        output_dir / "03_speed_vs_turn_angle_binned.csv",
        binned_rows,
    )
    plot_relationship(
        speed_before,
        absolute_turn,
        output_dir / "03_speed_vs_turn_angle.png",
        "Speed versus turning angle",
        f"Speed before turn ({unit}/s)",
        "Absolute turning angle (degrees)",
        dpi,
        smooth_fraction,
    )

    max_lag = (
        max(int(float(row["lag_steps"])) for row in direction_autocorrelation_rows)
        if direction_autocorrelation_rows
        else 25
    )
    time_step = numeric(next(iter(grouped_steps.values()))[0], "dt_s")
    direction_rows = calculate_direction_autocorrelation_by_track(
        grouped_steps=grouped_steps,
        heading_column=heading_column,
        time_step=time_step,
        max_lag=max_lag,
    )
    write_csv(
        output_dir / "04_direction_autocorrelation.csv",
        direction_rows,
    )
    plot_lag_curve_with_band(
        [row["lag_s"] for row in direction_rows],
        [row["mean_direction_autocorrelation"] for row in direction_rows],
        [row["q25_direction_autocorrelation"] for row in direction_rows],
        [row["q75_direction_autocorrelation"] for row in direction_rows],
        output_dir / "04_direction_autocorrelation.png",
        "Direction autocorrelation",
        "Lag (s)",
        "Mean cos(Δheading)",
        dpi,
        line_label="Mean directional persistence",
        band_label="25th–75th percentile",
        horizontal_zero=True,
    )

    return speed_before, absolute_turn, binned_rows


def analyse_variable_coupling(
    turn_rows: list[dict[str, str]],
    track_rows: list[dict[str, str]],
    speed_before_column: str,
    acceleration_column: str,
    mean_speed_column: str,
    unit: str,
    speed_before: np.ndarray,
    absolute_turn: np.ndarray,
    speed_turn_binned: list[dict],
    output_dir: Path,
    coupling_bins: int,
    smooth_fraction: float,
    dpi: int,
) -> None:
    """Analyse pairwise relationships among trajectory variables."""
    write_csv(
        output_dir / "01_speed_turn_pairs.csv",
        [
            {
                speed_before_column: numeric(row, speed_before_column),
                "abs_turn_angle_deg": numeric(row, "abs_turn_angle_deg"),
            }
            for row in turn_rows
        ],
    )
    write_csv(
        output_dir / "01_speed_turn_binned.csv",
        speed_turn_binned,
    )

    acceleration = np.asarray(
        [numeric(row, acceleration_column) for row in turn_rows],
        dtype=float,
    )
    speed_acceleration_binned = binned_summary(
        speed_before,
        acceleration,
        coupling_bins,
    )
    write_csv(
        output_dir / "02_speed_acceleration_pairs.csv",
        [
            {
                speed_before_column: numeric(row, speed_before_column),
                acceleration_column: numeric(row, acceleration_column),
            }
            for row in turn_rows
        ],
    )
    write_csv(
        output_dir / "02_speed_acceleration_binned.csv",
        speed_acceleration_binned,
    )
    plot_relationship(
        speed_before,
        acceleration,
        output_dir / "02_speed_acceleration.png",
        "Speed versus acceleration",
        f"Speed before transition ({unit}/s)",
        f"Acceleration ({unit}/s²)",
        dpi,
        smooth_fraction,
        horizontal_zero=True,
    )

    mean_speed = np.asarray(
        [numeric(row, mean_speed_column) for row in track_rows],
        dtype=float,
    )
    straightness = np.asarray(
        [numeric(row, "straightness") for row in track_rows],
        dtype=float,
    )
    persistence_speed_binned = binned_summary(
        mean_speed,
        straightness,
        coupling_bins,
    )
    write_csv(
        output_dir / "03_persistence_speed_pairs.csv",
        [
            {
                mean_speed_column: numeric(row, mean_speed_column),
                "straightness": numeric(row, "straightness"),
            }
            for row in track_rows
        ],
    )
    write_csv(
        output_dir / "03_persistence_speed_binned.csv",
        persistence_speed_binned,
    )
    plot_relationship(
        mean_speed,
        straightness,
        output_dir / "03_persistence_speed.png",
        "Straightness versus mean speed",
        f"Mean speed ({unit}/s)",
        "Straightness",
        dpi,
        smooth_fraction,
        point_size=6.0,
        point_alpha=0.18,
    )

    relationships = [
        (
            "speed_vs_abs_turn",
            relationship_statistics(speed_before, absolute_turn),
        ),
        (
            "speed_vs_acceleration",
            relationship_statistics(speed_before, acceleration),
        ),
        (
            "mean_speed_vs_straightness",
            relationship_statistics(mean_speed, straightness),
        ),
    ]
    summary_rows = []
    for relationship, result in relationships:
        summary_rows.append({"relationship": relationship, **result})
    write_csv(output_dir / "coupling_summary.csv", summary_rows)



def analyse_spatial_exploration(
    track_rows: list[dict[str, str]],
    grouped_steps: dict[int, list[dict[str, str]]],
    msd_rows: list[dict[str, str]],
    path_length_column: str,
    net_displacement_column: str,
    msd_column: str,
    unit: str,
    output_dir: Path,
    bins: int,
    dpi: int,
) -> None:
    """Analyse MSD, straightness, tortuosity and net displacement."""
    first_track = next(iter(grouped_steps.values()), [])
    if not first_track:
        raise ValueError("No step-level data available for MSD calculation.")
    time_step = numeric(first_track[0], "dt_s")
    if not np.isfinite(time_step) or time_step <= 0:
        raise ValueError("Invalid dt_s value in step_metrics.csv.")

    # Determine the maximum lag from whatever lag information is available
    # in msd.csv. Older files may contain only ``lag_s`` and not
    # ``lag_steps``. Falling back to the number of rows preserves the lag
    # range of the precomputed MSD file.
    if msd_rows:
        msd_fields = set(msd_rows[0].keys())
        if "lag_steps" in msd_fields:
            lag_candidates = [
                int(float(row["lag_steps"]))
                for row in msd_rows
                if row.get("lag_steps") not in (None, "")
            ]
            max_lag = max(lag_candidates) if lag_candidates else len(msd_rows)
        elif "lag_s" in msd_fields:
            lag_candidates = [
                max(1, int(round(float(row["lag_s"]) / time_step)))
                for row in msd_rows
                if row.get("lag_s") not in (None, "")
            ]
            max_lag = max(lag_candidates) if lag_candidates else len(msd_rows)
        else:
            max_lag = len(msd_rows)
    else:
        max_lag = 25

    # A lag cannot exceed the number of steps in the longest trajectory.
    longest_track_steps = max(len(rows) for rows in grouped_steps.values())
    max_lag = min(max_lag, longest_track_steps)

    # Calculate the time-averaged MSD within each trajectory first, then
    # summarise those per-trajectory values across tracks. Each trajectory
    # therefore contributes equally at a given lag, rather than long tracks
    # dominating because they contain more displacement pairs.
    trajectory_msd_rows = calculate_trajectory_averaged_msd(
        grouped_steps=grouped_steps,
        unit=unit,
        time_step=time_step,
        max_lag=max_lag,
        msd_column=msd_column,
    )
    q25_column = f"q25_{msd_column}"
    q75_column = f"q75_{msd_column}"
    write_csv(output_dir / "01_msd.csv", trajectory_msd_rows)
    plot_lag_curve_with_band(
        [numeric(row, "lag_s") for row in trajectory_msd_rows],
        [numeric(row, msd_column) for row in trajectory_msd_rows],
        [numeric(row, q25_column) for row in trajectory_msd_rows],
        [numeric(row, q75_column) for row in trajectory_msd_rows],
        output_dir / "01_msd.png",
        "Mean squared displacement",
        "Lag (s)",
        f"MSD ({unit}²)",
        dpi,
        line_label="Mean MSD",
        band_label="25th–75th percentile",
        horizontal_zero=False,
    )

    # Trajectory straightness.
    straightness = finite(numeric(row, "straightness") for row in track_rows)
    plot_histogram(
        straightness,
        output_dir / "02_straightness.png",
        "Trajectory straightness",
        "Net displacement / path length",
        40,
        dpi,
        legend_pos_x = 0.05,
        horizontal_alignment = "left",
    )


    # Trajectory tortuosity.
    tortuosity = finite(numeric(row, "tortuosity") for row in track_rows)
    plot_histogram(
        tortuosity,
        output_dir / "03_tortuosity.png",
        "Trajectory tortuosity",
        "Path length / net displacement",
        bins,
        dpi,
    )

    # Net displacement.
    net_displacement = finite(
        numeric(row, net_displacement_column) for row in track_rows
    )
    plot_histogram(
        net_displacement,
        output_dir / "04_net_displacement.png",
        "Net displacement",
        f"Net displacement ({unit})",
        bins,
        dpi,
    )

    write_csv(
        output_dir / "track_spatial_metrics.csv",
        [
            {
                "track_id": row["track_id"],
                path_length_column: numeric(row, path_length_column),
                net_displacement_column: numeric(
                    row,
                    net_displacement_column,
                ),
                "straightness": numeric(row, "straightness"),
                "tortuosity": numeric(row, "tortuosity"),
            }
            for row in track_rows
        ],
    )


# -----------------------------------------------------------------------------
# Command-line interface and orchestration
# -----------------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "metrics_dir",
        type=Path,
        help="Directory containing trajectory metric CSV files.",
    )
    parser.add_argument(
        "-o",
        "--outdir",
        type=Path,
        default=None,
        help="Output directory. Default: METRICS_DIR/grouped_analysis",
    )
    parser.add_argument(
        "--state-speed-threshold",
        type=float,
        default=None,
        help="Manual FAST/SLOW speed threshold. Default: Otsu threshold.",
    )
    parser.add_argument(
        "--bins",
        type=int,
        default=50,
        help="Default number of histogram bins.",
    )
    parser.add_argument(
        "--coupling-bins",
        type=int,
        default=20,
        help="Number of bins used for binned variable relationships.",
    )
    parser.add_argument(
        "--smooth-frac",
        type=float,
        default=0.20,
        help="LOWESS smoothing fraction for relationship plots.",
    )
    parser.add_argument(
        "--dpi",
        type=int,
        default=300,
        help="Output resolution in dots per inch.",
    )

    args = parser.parse_args()
    if args.bins < 1:
        parser.error("--bins must be >= 1")
    if args.coupling_bins < 1:
        parser.error("--coupling-bins must be >= 1")
    if not 0.0 < args.smooth_frac <= 1.0:
        parser.error("--smooth-frac must be in ]0, 1]")
    if args.dpi < 1:
        parser.error("--dpi must be >= 1")
    return args


def main() -> int:
    args = parse_args()
    output_root = args.outdir or args.metrics_dir / "grouped_analysis"

    directories = {
        "motion_states": output_root / "I_motion_states",
        "kinematics": output_root / "II_kinematics",
        "steering": output_root / "III_steering_behaviour",
        "coupling": output_root / "IV_variable_coupling",
        "spatial": output_root / "V_spatial_exploration",
    }
    for directory in directories.values():
        directory.mkdir(parents=True, exist_ok=True)

    step_rows = read_csv(args.metrics_dir / "step_metrics.csv")
    turn_rows = read_csv(args.metrics_dir / "turn_metrics.csv")
    track_rows = read_csv(args.metrics_dir / "track_metrics.csv")
    msd_rows = read_csv(args.metrics_dir / "msd.csv")
    direction_autocorrelation_rows = read_csv(
        args.metrics_dir / "direction_autocorrelation.csv"
    )

    if not step_rows:
        raise ValueError("step_metrics.csv is empty.")
    if not turn_rows:
        raise ValueError("turn_metrics.csv is empty.")
    if not track_rows:
        raise ValueError("track_metrics.csv is empty.")

    step_columns = step_rows[0].keys()
    turn_columns = turn_rows[0].keys()
    track_columns = track_rows[0].keys()
    msd_columns = msd_rows[0].keys() if msd_rows else []

    speed_column = find_column(step_columns, "speed_")
    distance_column = find_column(step_columns, "distance_")
    heading_column = find_optional_column(
        step_columns,
        ("heading_deg", "heading_", "direction_deg", "direction_"),
    )
    if heading_column is None:
        raise ValueError(
            "Cannot calculate per-trajectory direction autocorrelation: "
            "no heading/direction column was found in step_metrics.csv."
        )
    acceleration_column = find_column(turn_columns, "acceleration_")
    absolute_acceleration_column = find_column(
        turn_columns,
        "absolute_acceleration_",
    )
    speed_before_column = find_column(turn_columns, "speed_before_")
    mean_speed_column = find_column(track_columns, "mean_speed_")
    path_length_column = find_column(track_columns, "path_length_")
    net_displacement_column = find_column(
        track_columns,
        "net_displacement_",
    )
    msd_column = find_column(msd_columns, "msd_")
    unit = distance_column.removeprefix("distance_")

    grouped_steps = group_steps_by_track(step_rows)

    (
        threshold,
        threshold_method,
        episodes,
        fast_episodes,
        slow_episodes,
    ) = analyse_motion_states(
        step_rows=step_rows,
        grouped_steps=grouped_steps,
        speed_column=speed_column,
        distance_column=distance_column,
        unit=unit,
        output_dir=directories["motion_states"],
        bins=args.bins,
        dpi=args.dpi,
        manual_threshold=args.state_speed_threshold,
    )

    analyse_kinematics(
        step_rows=step_rows,
        turn_rows=turn_rows,
        grouped_steps=grouped_steps,
        direction_autocorrelation_rows=direction_autocorrelation_rows,
        speed_column=speed_column,
        acceleration_column=acceleration_column,
        absolute_acceleration_column=absolute_acceleration_column,
        unit=unit,
        output_dir=directories["kinematics"],
        bins=args.bins,
        dpi=args.dpi,
    )

    speed_before, absolute_turn, speed_turn_binned = analyse_steering(
        turn_rows=turn_rows,
        grouped_steps=grouped_steps,
        direction_autocorrelation_rows=direction_autocorrelation_rows,
        heading_column=heading_column,
        speed_before_column=speed_before_column,
        unit=unit,
        output_dir=directories["steering"],
        coupling_bins=args.coupling_bins,
        smooth_fraction=args.smooth_frac,
        dpi=args.dpi,
    )

    analyse_variable_coupling(
        turn_rows=turn_rows,
        track_rows=track_rows,
        speed_before_column=speed_before_column,
        acceleration_column=acceleration_column,
        mean_speed_column=mean_speed_column,
        unit=unit,
        speed_before=speed_before,
        absolute_turn=absolute_turn,
        speed_turn_binned=speed_turn_binned,
        output_dir=directories["coupling"],
        coupling_bins=args.coupling_bins,
        smooth_fraction=args.smooth_frac,
        dpi=args.dpi,
    )

    analyse_spatial_exploration(
        track_rows=track_rows,
        grouped_steps=grouped_steps,
        msd_rows=msd_rows,
        path_length_column=path_length_column,
        net_displacement_column=net_displacement_column,
        msd_column=msd_column,
        unit=unit,
        output_dir=directories["spatial"],
        bins=args.bins,
        dpi=args.dpi,
    )

    write_csv(
        output_root / "analysis_summary.csv",
        [
            {
                "fast_slow_threshold": threshold,
                "threshold_method": threshold_method,
                "n_tracks": len(track_rows),
                "n_steps": len(step_rows),
                "n_turns": len(turn_rows),
                "n_episodes": len(episodes),
                "n_fast_episodes": len(fast_episodes),
                "n_slow_episodes": len(slow_episodes),
                "unit": unit,
            }
        ],
    )

    print(f"Grouped analysis written to: {output_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
