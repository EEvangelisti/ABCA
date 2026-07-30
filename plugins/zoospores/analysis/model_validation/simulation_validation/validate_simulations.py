#!/usr/bin/env python3
"""Compare experimental zoospore metrics with an ensemble of simulations.

The experimental input is one trajectory-analysis directory. The simulation
input is a parent directory containing independent analyses such as
``trajectory_analysis_001``, ``trajectory_analysis_002``, etc.

For distribution-valued descriptors, the experimental percentage histogram is
shown in grey. Each simulation is converted to a percentage histogram using
common bin edges; the median frequency across simulations is shown in blue and
the 25th–75th percentile across simulations is shaded.

For MSD, the experimental mean and within-experiment IQR are shown in grey. The
blue curve is the median of the independent simulation mean-MSD curves, with an
inter-simulation IQR. Heading isotropy is compared as experimental R versus the
simulation median and IQR.
"""
from __future__ import annotations

import argparse
import csv
import math
import re
import sys
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np

mpl.rcParams.update({
    "font.size": 17,
    "axes.labelsize": 18,
    "axes.titlesize": 18,
    "xtick.labelsize": 16,
    "ytick.labelsize": 16,
    "legend.fontsize": 15,
})

FIGSIZE = (8.0, 6.0)
EXP_LINE = "0.15"
EXP_FILL = "0.82"
SIM_LINE = "#2166AC"
SIM_FILL = "#9ECAE1"


@dataclass(frozen=True)
class MetricSpec:
    key: str
    title: str
    xlabel_template: str
    file_candidates: tuple[str, ...]
    exact_columns: tuple[str, ...] = ()
    column_prefixes: tuple[str, ...] = ()
    signed_symmetric: bool = False
    bounded_range: tuple[float, float] | None = None


DISTRIBUTION_METRICS = (
    MetricSpec(
        "speed", "Instantaneous speed", "Speed ({unit}/s)",
        (
            "grouped_analysis/II_kinematics/01_speed_distribution.csv",
            "II_kinematics/01_speed_distribution.csv",
            "01_speed_distribution.csv",
        ),
        column_prefixes=("speed_",), bounded_range=(0.0, math.inf),
    ),
    MetricSpec(
        "signed_turn_angle", "Signed turning angle", "Turning angle (degrees)",
        (
            "grouped_analysis/III_steering_behaviour/turning_angles.csv",
            "III_steering_behaviour/turning_angles.csv",
            "turning_angles.csv",
        ),
        exact_columns=("turn_angle_deg",), signed_symmetric=True,
    ),
    MetricSpec(
        "absolute_turn_angle", "Absolute turning angle",
        "Absolute turning angle (degrees)",
        (
            "grouped_analysis/III_steering_behaviour/turning_angles.csv",
            "III_steering_behaviour/turning_angles.csv",
            "turning_angles.csv",
        ),
        exact_columns=("abs_turn_angle_deg",), bounded_range=(0.0, 180.0),
    ),
    MetricSpec(
        "signed_acceleration", "Signed acceleration", "Acceleration ({unit}/s²)",
        (
            "grouped_analysis/II_kinematics/accelerations.csv",
            "II_kinematics/accelerations.csv",
            "accelerations.csv",
        ),
        column_prefixes=("acceleration_",), signed_symmetric=True,
    ),
    MetricSpec(
        "absolute_acceleration", "Absolute acceleration",
        "Absolute acceleration ({unit}/s²)",
        (
            "grouped_analysis/II_kinematics/accelerations.csv",
            "II_kinematics/accelerations.csv",
            "accelerations.csv",
        ),
        column_prefixes=("absolute_acceleration_",), bounded_range=(0.0, math.inf),
    ),
    MetricSpec(
        "net_displacement", "Net displacement", "Net displacement ({unit})",
        (
            "grouped_analysis/V_spatial_exploration/track_spatial_metrics.csv",
            "V_spatial_exploration/track_spatial_metrics.csv",
            "track_spatial_metrics.csv",
        ),
        column_prefixes=("net_displacement_",), bounded_range=(0.0, math.inf),
    ),
    MetricSpec(
        "trajectory_length", "Trajectory length",
        "Trajectory length (number of points)",
        (
            "trajectory_overview/03_trajectory_lengths_filtered.csv",
            "03_trajectory_lengths_filtered.csv",
            "trajectory_overview/03_trajectory_lengths.csv",
            "03_trajectory_lengths.csv",
        ),
        exact_columns=("n_points", "trajectory_length"),
        bounded_range=(0.0, math.inf),
    ),
)


def natural_key(path: Path) -> list[object]:
    return [int(x) if x.isdigit() else x.lower() for x in re.split(r"(\d+)", path.name)]


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        raise FileNotFoundError(f"Missing required file: {path}")
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ValueError(f"CSV file is empty: {path}")
    return rows


def write_csv(path: Path, rows: Sequence[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = list(rows[0].keys()) if rows else []
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def numeric(row: dict[str, str], column: str) -> float:
    try:
        return float(row[column])
    except (KeyError, TypeError, ValueError):
        return math.nan


def finite(values: Iterable[float]) -> np.ndarray:
    array = np.asarray(list(values), dtype=float)
    return array[np.isfinite(array)]


def locate_file(root: Path, candidates: Sequence[str]) -> Path:
    for relative in candidates:
        path = root / relative
        if path.is_file():
            return path
    basenames = list(dict.fromkeys(Path(x).name for x in candidates))
    matches: list[Path] = []
    for basename in basenames:
        matches.extend(root.rglob(basename))
    matches = sorted(set(matches))
    if len(matches) == 1:
        return matches[0]
    if not matches:
        raise FileNotFoundError(f"Could not locate any of {list(candidates)} beneath {root}")
    raise ValueError(f"Ambiguous search beneath {root}: {[str(x) for x in matches]}")


def find_unique_column(
    columns: Sequence[str], *, exact_candidates: Sequence[str] = (),
    prefixes: Sequence[str] = (), description: str,
) -> str:
    for candidate in exact_candidates:
        if candidate in columns:
            return candidate
    for prefix in prefixes:
        matches = [x for x in columns if x.startswith(prefix)]
        if len(matches) == 1:
            return matches[0]
    raise ValueError(f"Could not identify {description}. Columns: {list(columns)}")


def infer_unit(column: str, prefixes: Sequence[str]) -> str:
    for prefix in prefixes:
        if column.startswith(prefix):
            unit = column.removeprefix(prefix)
            return unit.removesuffix("_per_s2").removesuffix("_per_s")
    return ""


def make_figure():
    fig, ax = plt.subplots(figsize=FIGSIZE)
    fig.subplots_adjust(left=0.14, right=0.97, bottom=0.15, top=0.88)
    return fig, ax


def save_figure(fig, path: Path, dpi: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=dpi)
    plt.close(fig)


def discover_simulations(root: Path, pattern: str) -> list[Path]:
    directories = sorted([x for x in root.glob(pattern) if x.is_dir()], key=natural_key)
    if not directories:
        raise FileNotFoundError(f"No directory matching {pattern!r} in {root}")
    return directories


def load_metric_values(root: Path, spec: MetricSpec) -> tuple[np.ndarray, str, Path]:
    path = locate_file(root, spec.file_candidates)
    rows = read_csv(path)
    column = find_unique_column(
        list(rows[0]), exact_candidates=spec.exact_columns,
        prefixes=spec.column_prefixes, description=spec.key,
    )
    values = finite(numeric(row, column) for row in rows)
    if values.size == 0:
        raise ValueError(f"No finite {spec.key} values in {path}")
    return values, infer_unit(column, spec.column_prefixes), path


def histogram_range(
    experimental: np.ndarray, simulations: Sequence[np.ndarray], spec: MetricSpec,
    percentile: float | None,
) -> tuple[float, float]:
    pooled = np.concatenate([experimental, *simulations])
    if spec.signed_symmetric:
        limit = float(np.max(np.abs(pooled)) if percentile is None
                      else np.percentile(np.abs(pooled), percentile))
        lower, upper = -limit, limit
    else:
        lower = float(np.min(pooled))
        upper = float(np.max(pooled) if percentile is None
                      else np.percentile(pooled, percentile))
    if spec.bounded_range is not None:
        lo, hi = spec.bounded_range
        if np.isfinite(lo):
            lower = max(lower, lo)
        if np.isfinite(hi):
            upper = min(upper, hi)
    if not np.isfinite(lower) or not np.isfinite(upper) or upper <= lower:
        raise ValueError(f"Invalid range for {spec.key}: [{lower}, {upper}]")
    return lower, upper


def percentage_histogram(values: np.ndarray, edges: np.ndarray) -> np.ndarray:
    counts, _ = np.histogram(values, bins=edges)
    return counts.astype(float) * 100.0 / values.size


def plot_distribution(
    experimental: np.ndarray, simulations: Sequence[np.ndarray], spec: MetricSpec,
    unit: str, png: Path, csv_path: Path, bins: int, dpi: int,
    percentile: float | None,
) -> dict[str, object]:
    lower, upper = histogram_range(experimental, simulations, spec, percentile)
    if spec.key == "trajectory_length":
        lo, hi = math.floor(lower), math.ceil(upper)
        edges = (np.arange(lo - 0.5, hi + 1.5, 1.0)
                 if hi - lo + 1 <= 250 else np.linspace(lower, upper, bins + 1))
    else:
        edges = np.linspace(lower, upper, bins + 1)
    centres = (edges[:-1] + edges[1:]) / 2.0

    exp_frequency = percentage_histogram(experimental, edges)
    sim_matrix = np.vstack([percentage_histogram(x, edges) for x in simulations])
    sim_median = np.median(sim_matrix, axis=0)
    sim_q25 = np.percentile(sim_matrix, 25, axis=0)
    sim_q75 = np.percentile(sim_matrix, 75, axis=0)

    exp_median = float(np.median(experimental))
    sim_dataset_medians = np.asarray([np.median(x) for x in simulations])
    median = float(np.median(sim_dataset_medians))
    q25 = float(np.percentile(sim_dataset_medians, 25))
    q75 = float(np.percentile(sim_dataset_medians, 75))

    fig, ax = make_figure()
    ax.fill_between(centres, sim_q25, sim_q75, color=SIM_FILL, alpha=0.50,
                    linewidth=0, label="Simulations: 25th–75th percentile", zorder=1)
    ax.step(centres, exp_frequency, where="mid", color=EXP_LINE, linewidth=2.0,
            label="Experimental", zorder=3)
    ax.step(centres, sim_median, where="mid", color=SIM_LINE, linewidth=2.0,
            label="Simulations: median", zorder=4)
    ax.axvline(exp_median, color=EXP_LINE, linestyle="--", linewidth=1.1)
    ax.axvline(median, color=SIM_LINE, linestyle="--", linewidth=1.1)
    ax.set_title(spec.title)
    ax.set_xlabel(spec.xlabel_template.format(unit=unit))
    ax.set_ylabel("Relative frequency (%)")
    ax.set_xlim(edges[0], edges[-1])
    save_figure(fig, png.with_stem(png.stem + "_nolegend"), dpi)
    ax.legend(frameon=False)
    ax.text(0.98, 0.95,
            f"Experimental: n = {experimental.size:,}, median = {exp_median:.3g}\n"
            f"Simulations: n = {len(simulations)}, median = {median:.3g}\n"
            f"simulation IQR = [{q25:.3g}, {q75:.3g}]",
            transform=ax.transAxes, ha="right", va="top", fontsize=13)
    save_figure(fig, png, dpi)

    rows = [{
        "bin_index": i,
        "bin_left": float(edges[i]),
        "bin_right": float(edges[i + 1]),
        "bin_center": float(centres[i]),
        "experimental_frequency_percent": float(exp_frequency[i]),
        "simulated_median_frequency_percent": float(sim_median[i]),
        "simulated_q25_frequency_percent": float(sim_q25[i]),
        "simulated_q75_frequency_percent": float(sim_q75[i]),
    } for i in range(len(centres))]
    write_csv(csv_path, rows)
    return {
        "metric": spec.key,
        "experimental_n": int(experimental.size),
        "experimental_value": exp_median,
        "simulation_count": len(simulations),
        "simulated_median": median,
        "simulated_q25": q25,
        "simulated_q75": q75,
        "unit": unit,
    }


def parse_msd(root: Path):
    path = locate_file(root, (
        "grouped_analysis/V_spatial_exploration/01_msd.csv",
        "V_spatial_exploration/01_msd.csv", "01_msd.csv",
    ))
    rows = read_csv(path)
    columns = list(rows[0])
    lag_col = find_unique_column(columns, exact_candidates=("lag_s",),
                                 prefixes=("lag_s",), description="MSD lag")
    msd_col = find_unique_column(columns, prefixes=("msd_",), description="mean MSD")
    q25_col, q75_col = f"q25_{msd_col}", f"q75_{msd_col}"
    if q25_col not in columns or q75_col not in columns:
        raise ValueError(f"Expected {q25_col!r} and {q75_col!r} in {path}")
    lag = np.asarray([numeric(r, lag_col) for r in rows])
    mean = np.asarray([numeric(r, msd_col) for r in rows])
    q25 = np.asarray([numeric(r, q25_col) for r in rows])
    q75 = np.asarray([numeric(r, q75_col) for r in rows])
    valid = np.isfinite(lag) & np.isfinite(mean) & np.isfinite(q25) & np.isfinite(q75)
    lag, mean, q25, q75 = lag[valid], mean[valid], q25[valid], q75[valid]
    order = np.argsort(lag)
    return lag[order], mean[order], q25[order], q75[order], msd_col.removeprefix("msd_")


def interpolate_no_extrapolation(x, y, target):
    out = np.full(target.shape, np.nan)
    valid = (target >= x.min()) & (target <= x.max())
    out[valid] = np.interp(target[valid], x, y)
    return out


def plot_msd(experimental_root: Path, simulation_roots: Sequence[Path],
             png: Path, csv_path: Path, dpi: int) -> dict[str, object]:
    exp_lag, exp_mean, exp_q25, exp_q75, unit = parse_msd(experimental_root)
    curves = []
    for root in simulation_roots:
        lag, mean, _, _, sim_unit = parse_msd(root)
        if sim_unit != unit:
            raise ValueError(f"MSD units differ in {root}: {sim_unit} vs {unit}")
        curves.append(interpolate_no_extrapolation(lag, mean, exp_lag))
    matrix = np.vstack(curves)
    available = np.sum(np.isfinite(matrix), axis=0)
    median = np.nanmedian(matrix, axis=0)
    q25 = np.nanpercentile(matrix, 25, axis=0)
    q75 = np.nanpercentile(matrix, 75, axis=0)
    valid = available > 0

    fig, ax = make_figure()
    ax.fill_between(exp_lag, exp_q25, exp_q75, color=EXP_FILL, alpha=0.45,
                    linewidth=0, label="Experimental: 25th–75th percentile")
    ax.plot(exp_lag, exp_mean, color=EXP_LINE, linewidth=2.0,
            label="Experimental: mean")
    ax.fill_between(exp_lag[valid], q25[valid], q75[valid], color=SIM_FILL,
                    alpha=0.50, linewidth=0,
                    label="Simulations: 25th–75th percentile")
    ax.plot(exp_lag[valid], median[valid], color=SIM_LINE, linewidth=2.0,
            label="Simulations: median")
    ax.set_title("Mean squared displacement")
    ax.set_xlabel("Lag (s)")
    ax.set_ylabel(f"MSD ({unit}²)")
    save_figure(fig, png.with_stem(png.stem + "_nolegend"), dpi)
    ax.legend(frameon=False, loc="upper left")
    save_figure(fig, png, dpi)

    rows = [{
        "lag_s": float(exp_lag[i]),
        "experimental_mean_msd": float(exp_mean[i]),
        "experimental_q25_msd": float(exp_q25[i]),
        "experimental_q75_msd": float(exp_q75[i]),
        "simulated_median_mean_msd": float(median[i]),
        "simulated_q25_mean_msd": float(q25[i]),
        "simulated_q75_mean_msd": float(q75[i]),
        "n_simulations": int(available[i]),
    } for i in range(len(exp_lag))]
    write_csv(csv_path, rows)
    return {"metric": "msd", "experimental_n": "", "experimental_value": "",
            "simulation_count": len(simulation_roots), "simulated_median": "",
            "simulated_q25": "", "simulated_q75": "", "unit": f"{unit}²"}


def load_isotropy(root: Path) -> tuple[float, int | None]:
    path = locate_file(root, (
        "trajectory_overview/01_heading_isotropy_summary.csv",
        "01_heading_isotropy_summary.csv",
    ))
    row = read_csv(path)[0]
    value = numeric(row, "mean_resultant_length_R")
    if not np.isfinite(value):
        raise ValueError(f"No finite isotropy R in {path}")
    n = numeric(row, "n_headings")
    return float(value), int(n) if np.isfinite(n) else None


def plot_isotropy(experimental_root: Path, simulation_roots: Sequence[Path],
                   png: Path, csv_path: Path, dpi: int) -> dict[str, object]:
    experimental, exp_n = load_isotropy(experimental_root)
    values = np.asarray([load_isotropy(x)[0] for x in simulation_roots])
    median = float(np.median(values))
    q25, q75 = map(float, np.percentile(values, [25, 75]))

    fig, ax = make_figure()
    ax.scatter([0], [experimental], s=90, color=EXP_LINE, label="Experimental", zorder=3)
    ax.errorbar([1], [median], yerr=np.asarray([[median - q25], [q75 - median]]),
                fmt="o", markersize=8, color=SIM_LINE, ecolor=SIM_LINE,
                elinewidth=2.0, capsize=6,
                label="Simulations: median and IQR", zorder=4)
    rng = np.random.default_rng(42)
    ax.scatter(1 + rng.normal(0, 0.035, values.size), values, s=18,
               color=SIM_FILL, alpha=0.45, edgecolors="none", rasterized=True)
    ax.set_xticks([0, 1], ["Experimental", "Simulations"])
    ax.set_xlim(-0.55, 1.55)
    ax.set_ylim(bottom=0.0)
    ax.set_ylabel("Mean resultant length, R")
    ax.set_title("Heading isotropy")
    save_figure(fig, png.with_stem(png.stem + "_nolegend"), dpi)
    ax.legend(frameon=False)
    save_figure(fig, png, dpi)

    rows = [{"dataset": "experimental", "replicate": "experimental",
             "mean_resultant_length_R": experimental}]
    rows.extend({"dataset": "simulation", "replicate": root.name,
                 "mean_resultant_length_R": float(value)}
                for root, value in zip(simulation_roots, values))
    write_csv(csv_path, rows)
    return {"metric": "heading_isotropy_R", "experimental_n": exp_n or "",
            "experimental_value": experimental,
            "simulation_count": len(simulation_roots), "simulated_median": median,
            "simulated_q25": q25, "simulated_q75": q75, "unit": "R"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("experimental_dir", type=Path)
    parser.add_argument("simulations_root", type=Path)
    parser.add_argument("-o", "--outdir", type=Path,
                        default=Path("experimental_vs_simulation_ensemble"))
    parser.add_argument("--simulation-pattern", default="trajectory_analysis_*")
    parser.add_argument("--bins", type=int, default=50)
    parser.add_argument("--upper-percentile", type=float, default=None,
                        help="Optional display percentile, e.g. 99.5.")
    parser.add_argument("--dpi", type=int, default=300)
    args = parser.parse_args()
    if args.bins < 2:
        parser.error("--bins must be >= 2")
    if args.dpi < 1:
        parser.error("--dpi must be >= 1")
    if args.upper_percentile is not None and not 0 < args.upper_percentile <= 100:
        parser.error("--upper-percentile must be in ]0, 100]")
    return args


def main() -> int:
    args = parse_args()
    experimental_root = args.experimental_dir.resolve()
    simulation_roots = discover_simulations(args.simulations_root.resolve(),
                                             args.simulation_pattern)
    outdir = args.outdir.resolve()
    outdir.mkdir(parents=True, exist_ok=True)
    print(f"Found {len(simulation_roots)} independent simulation analyses.", flush=True)

    write_csv(outdir / "simulation_manifest.csv", [{
        "simulation_index": i,
        "simulation_name": root.name,
        "simulation_directory": str(root),
    } for i, root in enumerate(simulation_roots, 1)])

    summary: list[dict[str, object]] = []
    total = len(DISTRIBUTION_METRICS) + 2
    for index, spec in enumerate(DISTRIBUTION_METRICS, 1):
        print(f"[{index}/{total}] {spec.key}", flush=True)
        experimental, exp_unit, _ = load_metric_values(experimental_root, spec)
        simulations, units = [], []
        for root in simulation_roots:
            values, unit, _ = load_metric_values(root, spec)
            simulations.append(values)
            units.append(unit)
        unit_set = {x for x in [exp_unit, *units] if x}
        if len(unit_set) > 1:
            raise ValueError(f"Units differ for {spec.key}: {sorted(unit_set)}")
        unit = exp_unit or (units[0] if units else "")
        stem = f"{index:02d}_{spec.key}_experimental_vs_simulations"
        summary.append(plot_distribution(
            experimental, simulations, spec, unit,
            outdir / f"{stem}.png", outdir / f"{stem}.csv",
            args.bins, args.dpi, args.upper_percentile,
        ))

    index = len(DISTRIBUTION_METRICS) + 1
    print(f"[{index}/{total}] msd", flush=True)
    summary.append(plot_msd(
        experimental_root, simulation_roots,
        outdir / f"{index:02d}_msd_experimental_vs_simulations.png",
        outdir / f"{index:02d}_msd_experimental_vs_simulations.csv",
        args.dpi,
    ))

    index += 1
    print(f"[{index}/{total}] heading isotropy", flush=True)
    summary.append(plot_isotropy(
        experimental_root, simulation_roots,
        outdir / f"{index:02d}_heading_isotropy_experimental_vs_simulations.png",
        outdir / f"{index:02d}_heading_isotropy_experimental_vs_simulations.csv",
        args.dpi,
    ))

    write_csv(outdir / "comparison_summary.csv", summary)
    write_csv(outdir / "comparison_metadata.csv", [{
        "experimental_directory": str(experimental_root),
        "simulations_root": str(args.simulations_root.resolve()),
        "simulation_pattern": args.simulation_pattern,
        "simulation_count": len(simulation_roots),
        "histogram_bins": args.bins,
        "upper_display_percentile": args.upper_percentile or "none",
        "simulation_curve": "median across independent simulations",
        "simulation_interval": "25th–75th percentile across simulations",
    }])
    print(f"Comparison completed: {outdir}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(1)
