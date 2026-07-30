#!/usr/bin/env python3
"""
compare_zoospore_models.py

Quantitatively compare two zoospore simulation models against experimental data.

Metrics
-------
Net-displacement distributions:
    - first-order Wasserstein distance
    - two-sample Kolmogorov-Smirnov statistic D
    - absolute and relative median error

MSD curves:
    - RMSE
    - normalized RMSE (RMSE divided by the experimental MSD range)
    - MAE
    - mean absolute percentage error (MAPE; zero experimental values ignored)

The script supports multiple independent simulations through a simulation-ID
column. Statistics are calculated separately for every simulation and then
summarised by their median and 95% percentile interval.

Expected input tables
---------------------
Experimental displacement CSV:
    one row per trajectory, with a column such as "net_displacement_um"

Simulation displacement CSV:
    one row per simulated trajectory, with:
        - a displacement column
        - optionally a simulation-ID column

Experimental MSD CSV:
    columns for lag and MSD, e.g. "lag_s" and "msd_um2"

Simulation MSD CSV:
    columns for lag, MSD, and optionally simulation ID

If no simulation-ID column is supplied, each simulation file is treated as one
single simulation.

Example
-------
python compare_zoospore_models.py \
    --experimental-displacement experimental_displacement.csv \
    --empirical-displacement "analyses/empirical/trajectory_analysis_%03d/grouped_analysis/V_spatial_exploration" \
    --hmm-displacement "analyses/hmm/trajectory_analysis_%03d/grouped_analysis/V_spatial_exploration" \
    --experimental-msd experimental_msd.csv \
    --empirical-msd "analyses/empirical/trajectory_analysis_%03d/grouped_analysis/VI_mean_squared_displacement" \
    --hmm-msd "analyses/hmm/trajectory_analysis_%03d/grouped_analysis/VI_mean_squared_displacement" \
    --from 1 --to 100 \
    --displacement-column net_displacement_um \
    --lag-column lag_s \
    --msd-column msd_um2 \
    --simulation-id-column simulation_id \
    --output-prefix model_comparison
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd
from scipy.stats import ks_2samp, wasserstein_distance


SUMMARY_COLUMNS = [
    "model",
    "metric_group",
    "metric",
    "unit",
    "estimate",
    "ci95_low",
    "ci95_high",
    "n_simulations",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare empirical SLOW/FAST and two-state HMM simulations "
                    "against experimental zoospore data."
    )

    parser.add_argument("--experimental-displacement", required=True, type=Path)
    parser.add_argument("--empirical-displacement", required=True, type=Path)
    parser.add_argument("--hmm-displacement", required=True, type=Path)

    parser.add_argument("--experimental-msd", required=True, type=Path)
    parser.add_argument("--empirical-msd", required=True, type=Path)
    parser.add_argument("--hmm-msd", required=True, type=Path)

    parser.add_argument(
        "--displacement-column",
        default="net_displacement_um",
        help="Net-displacement column in all displacement tables.",
    )
    parser.add_argument(
        "--lag-column",
        default="lag_s",
        help="Time-lag column in all MSD tables.",
    )
    parser.add_argument(
        "--msd-column",
        default="msd_um2",
        help="MSD column in all MSD tables.",
    )
    parser.add_argument(
        "--simulation-id-column",
        default="simulation_id",
        help="Simulation identifier column. If absent, the file is treated as one simulation.",
    )
    parser.add_argument(
        "--delimiter",
        default=",",
        help=r"Input delimiter. Use '\t' for TSV files. Default: ','.",
    )
    parser.add_argument(
        "--output-prefix",
        default="zoospore_model_comparison",
        help="Prefix for output CSV and Markdown files.",
    )
    parser.add_argument(
        "--from",
        dest="simulation_from",
        type=int,
        default=1,
        help="First simulation index used to expand paths containing a printf placeholder such as %%03d.",
    )
    parser.add_argument(
        "--to",
        dest="simulation_to",
        type=int,
        default=100,
        help="Last simulation index used to expand paths containing a printf placeholder such as %%03d.",
    )
    parser.add_argument(
        "--displacement-filename",
        default="track_spatial_metrics.csv",
        help="Filename appended when a model displacement path expands to a directory.",
    )
    parser.add_argument(
        "--msd-filename",
        default="mean_squared_displacement.csv",
        help="Filename appended when a model MSD path expands to a directory.",
    )
    parser.add_argument(
        "--allow-missing-simulations",
        action="store_true",
        help="Skip missing indexed files instead of stopping with an error.",
    )
    parser.add_argument(
        "--ci",
        type=float,
        default=95.0,
        help="Percentile interval reported across simulations. Default: 95.",
    )

    return parser.parse_args()


def resolve_delimiter(value: str) -> str:
    return "\t" if value == r"\t" else value


def expand_indexed_paths(
    specification: Path,
    simulation_from: int,
    simulation_to: int,
    filename_if_directory: str,
    allow_missing: bool,
) -> list[tuple[int, Path]]:
    """
    Expand a printf-style path specification such as
    trajectory_analysis_%03d/grouped_analysis/V_spatial_exploration.

    If an expanded path is a directory, filename_if_directory is appended.
    A specification without a '%' placeholder is returned as a single path.
    """
    spec = str(specification)

    if simulation_to < simulation_from:
        raise ValueError("--to must be greater than or equal to --from.")

    if "%" not in spec:
        candidate = Path(spec)
        if candidate.is_dir():
            candidate = candidate / filename_if_directory
        return [(1, candidate)]

    expanded: list[tuple[int, Path]] = []
    missing: list[Path] = []

    for simulation_id in range(simulation_from, simulation_to + 1):
        try:
            candidate = Path(spec % simulation_id)
        except (TypeError, ValueError) as exc:
            raise ValueError(
                f"Invalid printf-style path template: {spec!r}. "
                "Use a placeholder such as %03d."
            ) from exc

        if candidate.is_dir():
            candidate = candidate / filename_if_directory

        if candidate.exists():
            expanded.append((simulation_id, candidate))
        else:
            missing.append(candidate)

    if missing and not allow_missing:
        preview = "\n".join(f"  {p}" for p in missing[:10])
        more = (
            f"\n  ... and {len(missing) - 10} more"
            if len(missing) > 10
            else ""
        )
        raise FileNotFoundError(
            "Missing indexed simulation file(s):\n"
            f"{preview}{more}\n"
            "Use --allow-missing-simulations to skip them."
        )

    if not expanded:
        raise FileNotFoundError(
            f"No simulation files were found for template: {spec}"
        )

    return expanded


def read_table(path: Path, delimiter: str) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f"Input file not found: {path}")
    df = pd.read_csv(path, sep=delimiter)
    if df.empty:
        raise ValueError(f"Input table is empty: {path}")
    return df


def read_indexed_tables(
    specification: Path,
    delimiter: str,
    simulation_from: int,
    simulation_to: int,
    filename_if_directory: str,
    simulation_id_column: str,
    allow_missing: bool,
) -> pd.DataFrame:
    paths = expand_indexed_paths(
        specification=specification,
        simulation_from=simulation_from,
        simulation_to=simulation_to,
        filename_if_directory=filename_if_directory,
        allow_missing=allow_missing,
    )

    frames: list[pd.DataFrame] = []
    for simulation_id, path in paths:
        frame = read_table(path, delimiter)
        frame = frame.copy()
        frame[simulation_id_column] = simulation_id
        frame["_source_file"] = str(path)
        frames.append(frame)

    return pd.concat(frames, ignore_index=True)


def require_columns(df: pd.DataFrame, columns: Iterable[str], path: Path) -> None:
    missing = [column for column in columns if column not in df.columns]
    if missing:
        available = ", ".join(map(str, df.columns))
        raise ValueError(
            f"Missing column(s) {missing} in {path}. Available columns: {available}"
        )


def finite_numeric(series: pd.Series, label: str) -> np.ndarray:
    values = pd.to_numeric(series, errors="coerce").to_numpy(dtype=float)
    values = values[np.isfinite(values)]
    if values.size == 0:
        raise ValueError(f"No finite numerical values found for {label}.")
    return values


def add_simulation_id(df: pd.DataFrame, id_column: str) -> pd.DataFrame:
    result = df.copy()
    if id_column not in result.columns:
        result[id_column] = 1
    return result


def percentile_interval(values: np.ndarray, level: float) -> tuple[float, float, float]:
    values = np.asarray(values, dtype=float)
    values = values[np.isfinite(values)]
    if values.size == 0:
        return math.nan, math.nan, math.nan

    alpha = (100.0 - level) / 2.0
    estimate = float(np.median(values))
    low = float(np.percentile(values, alpha))
    high = float(np.percentile(values, 100.0 - alpha))
    return estimate, low, high


def displacement_metrics(
    experimental: np.ndarray,
    simulated: np.ndarray,
) -> dict[str, float]:
    exp_median = float(np.median(experimental))
    sim_median = float(np.median(simulated))

    relative_median_error = (
        abs(sim_median - exp_median) / abs(exp_median)
        if exp_median != 0
        else math.nan
    )

    ks_result = ks_2samp(
        experimental,
        simulated,
        alternative="two-sided",
        method="auto",
    )

    return {
        "wasserstein_distance": float(
            wasserstein_distance(experimental, simulated)
        ),
        "ks_statistic": float(ks_result.statistic),
        "ks_pvalue": float(ks_result.pvalue),
        "absolute_median_error": abs(sim_median - exp_median),
        "relative_median_error": relative_median_error,
        "simulated_median": sim_median,
    }


def prepare_msd_curve(
    df: pd.DataFrame,
    lag_column: str,
    msd_column: str,
    label: str,
) -> pd.DataFrame:
    curve = df[[lag_column, msd_column]].copy()
    curve[lag_column] = pd.to_numeric(curve[lag_column], errors="coerce")
    curve[msd_column] = pd.to_numeric(curve[msd_column], errors="coerce")
    curve = curve.replace([np.inf, -np.inf], np.nan).dropna()

    if curve.empty:
        raise ValueError(f"No finite MSD points found for {label}.")

    # If repeated values exist at one lag, use their mean.
    curve = (
        curve.groupby(lag_column, as_index=False)[msd_column]
        .mean()
        .sort_values(lag_column)
    )
    return curve


def compare_msd_curves(
    experimental_curve: pd.DataFrame,
    simulated_curve: pd.DataFrame,
    lag_column: str,
    msd_column: str,
) -> dict[str, float]:
    exp_lag = experimental_curve[lag_column].to_numpy(dtype=float)
    exp_msd = experimental_curve[msd_column].to_numpy(dtype=float)

    sim_lag = simulated_curve[lag_column].to_numpy(dtype=float)
    sim_msd = simulated_curve[msd_column].to_numpy(dtype=float)

    lower = max(float(exp_lag.min()), float(sim_lag.min()))
    upper = min(float(exp_lag.max()), float(sim_lag.max()))
    mask = (exp_lag >= lower) & (exp_lag <= upper)

    comparison_lag = exp_lag[mask]
    comparison_exp = exp_msd[mask]

    if comparison_lag.size < 2:
        raise ValueError(
            "Experimental and simulated MSD curves have fewer than two "
            "overlapping lag values."
        )

    comparison_sim = np.interp(comparison_lag, sim_lag, sim_msd)
    residual = comparison_sim - comparison_exp

    rmse = float(np.sqrt(np.mean(residual**2)))
    mae = float(np.mean(np.abs(residual)))

    exp_range = float(np.max(comparison_exp) - np.min(comparison_exp))
    nrmse = rmse / exp_range if exp_range > 0 else math.nan

    nonzero = comparison_exp != 0
    mape = (
        float(np.mean(np.abs(residual[nonzero] / comparison_exp[nonzero])))
        if np.any(nonzero)
        else math.nan
    )

    return {
        "msd_rmse": rmse,
        "msd_nrmse": nrmse,
        "msd_mae": mae,
        "msd_mape": mape,
        "n_common_lags": float(comparison_lag.size),
    }


def evaluate_displacement_model(
    model_name: str,
    experimental_df: pd.DataFrame,
    simulation_df: pd.DataFrame,
    displacement_column: str,
    simulation_id_column: str,
) -> pd.DataFrame:
    experimental = finite_numeric(
        experimental_df[displacement_column],
        "experimental displacement",
    )

    simulation_df = add_simulation_id(simulation_df, simulation_id_column)
    records: list[dict[str, object]] = []

    for simulation_id, group in simulation_df.groupby(
        simulation_id_column,
        sort=True,
        dropna=False,
    ):
        simulated = finite_numeric(
            group[displacement_column],
            f"{model_name}, simulation {simulation_id}",
        )
        metrics = displacement_metrics(experimental, simulated)

        for metric, value in metrics.items():
            records.append(
                {
                    "model": model_name,
                    "simulation_id": simulation_id,
                    "metric_group": "net_displacement",
                    "metric": metric,
                    "value": value,
                }
            )

    return pd.DataFrame.from_records(records)


def evaluate_msd_model(
    model_name: str,
    experimental_df: pd.DataFrame,
    simulation_df: pd.DataFrame,
    lag_column: str,
    msd_column: str,
    simulation_id_column: str,
) -> pd.DataFrame:
    experimental_curve = prepare_msd_curve(
        experimental_df,
        lag_column,
        msd_column,
        "experimental MSD",
    )

    simulation_df = add_simulation_id(simulation_df, simulation_id_column)
    records: list[dict[str, object]] = []

    for simulation_id, group in simulation_df.groupby(
        simulation_id_column,
        sort=True,
        dropna=False,
    ):
        simulated_curve = prepare_msd_curve(
            group,
            lag_column,
            msd_column,
            f"{model_name}, simulation {simulation_id}",
        )
        metrics = compare_msd_curves(
            experimental_curve,
            simulated_curve,
            lag_column,
            msd_column,
        )

        for metric, value in metrics.items():
            records.append(
                {
                    "model": model_name,
                    "simulation_id": simulation_id,
                    "metric_group": "msd",
                    "metric": metric,
                    "value": value,
                }
            )

    return pd.DataFrame.from_records(records)


def metric_unit(metric: str) -> str:
    units = {
        "wasserstein_distance": "µm",
        "ks_statistic": "dimensionless",
        "ks_pvalue": "dimensionless",
        "absolute_median_error": "µm",
        "relative_median_error": "fraction",
        "simulated_median": "µm",
        "msd_rmse": "µm²",
        "msd_nrmse": "fraction",
        "msd_mae": "µm²",
        "msd_mape": "fraction",
        "n_common_lags": "count",
    }
    return units.get(metric, "")


def summarise_metrics(
    per_simulation: pd.DataFrame,
    ci_level: float,
) -> pd.DataFrame:
    rows: list[dict[str, object]] = []

    grouping = per_simulation.groupby(
        ["model", "metric_group", "metric"],
        sort=False,
    )
    for (model, metric_group, metric), group in grouping:
        values = pd.to_numeric(group["value"], errors="coerce").to_numpy(float)
        estimate, low, high = percentile_interval(values, ci_level)
        rows.append(
            {
                "model": model,
                "metric_group": metric_group,
                "metric": metric,
                "unit": metric_unit(metric),
                "estimate": estimate,
                "ci95_low": low,
                "ci95_high": high,
                "n_simulations": int(np.isfinite(values).sum()),
            }
        )

    return pd.DataFrame(rows, columns=SUMMARY_COLUMNS)


def add_best_model(summary: pd.DataFrame) -> pd.DataFrame:
    result = summary.copy()
    result["best_model"] = ""

    lower_is_better = {
        "wasserstein_distance",
        "ks_statistic",
        "absolute_median_error",
        "relative_median_error",
        "msd_rmse",
        "msd_nrmse",
        "msd_mae",
        "msd_mape",
    }

    for metric in lower_is_better:
        mask = result["metric"] == metric
        subset = result.loc[mask]
        if subset.empty:
            continue
        best_index = subset["estimate"].astype(float).idxmin()
        result.loc[mask, "best_model"] = result.loc[best_index, "model"]

    return result


def publication_table(summary: pd.DataFrame) -> pd.DataFrame:
    selected_metrics = [
        "wasserstein_distance",
        "ks_statistic",
        "absolute_median_error",
        "relative_median_error",
        "msd_rmse",
        "msd_nrmse",
        "msd_mae",
    ]
    table = summary[summary["metric"].isin(selected_metrics)].copy()

    def format_value(row: pd.Series) -> str:
        estimate = float(row["estimate"])
        low = float(row["ci95_low"])
        high = float(row["ci95_high"])
        unit = row["unit"]

        if unit == "fraction":
            return f"{estimate:.4f} [{low:.4f}–{high:.4f}]"
        if unit == "dimensionless":
            return f"{estimate:.4f} [{low:.4f}–{high:.4f}]"
        if unit in {"µm", "µm²"}:
            return f"{estimate:.2f} [{low:.2f}–{high:.2f}]"
        return f"{estimate:.3g} [{low:.3g}–{high:.3g}]"

    table["estimate [95% interval]"] = table.apply(format_value, axis=1)
    table = table[
        [
            "metric_group",
            "metric",
            "unit",
            "model",
            "estimate [95% interval]",
            "best_model",
        ]
    ]
    return table


def write_markdown_table(table: pd.DataFrame, path: Path) -> None:
    try:
        markdown = table.to_markdown(index=False)
    except ImportError:
        # Avoid failing solely because the optional "tabulate" package is absent.
        markdown = table.to_csv(index=False)
    path.write_text(markdown + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    delimiter = resolve_delimiter(args.delimiter)

    try:
        experimental_displacement = read_table(
            args.experimental_displacement,
            delimiter,
        )
        empirical_displacement = read_indexed_tables(
            args.empirical_displacement,
            delimiter,
            args.simulation_from,
            args.simulation_to,
            args.displacement_filename,
            args.simulation_id_column,
            args.allow_missing_simulations,
        )
        hmm_displacement = read_indexed_tables(
            args.hmm_displacement,
            delimiter,
            args.simulation_from,
            args.simulation_to,
            args.displacement_filename,
            args.simulation_id_column,
            args.allow_missing_simulations,
        )

        experimental_msd = read_table(args.experimental_msd, delimiter)
        empirical_msd = read_indexed_tables(
            args.empirical_msd,
            delimiter,
            args.simulation_from,
            args.simulation_to,
            args.msd_filename,
            args.simulation_id_column,
            args.allow_missing_simulations,
        )
        hmm_msd = read_indexed_tables(
            args.hmm_msd,
            delimiter,
            args.simulation_from,
            args.simulation_to,
            args.msd_filename,
            args.simulation_id_column,
            args.allow_missing_simulations,
        )

        require_columns(
            experimental_displacement,
            [args.displacement_column],
            args.experimental_displacement,
        )
        require_columns(
            empirical_displacement,
            [args.displacement_column],
            args.empirical_displacement,
        )
        require_columns(
            hmm_displacement,
            [args.displacement_column],
            args.hmm_displacement,
        )

        require_columns(
            experimental_msd,
            [args.lag_column, args.msd_column],
            args.experimental_msd,
        )
        require_columns(
            empirical_msd,
            [args.lag_column, args.msd_column],
            args.empirical_msd,
        )
        require_columns(
            hmm_msd,
            [args.lag_column, args.msd_column],
            args.hmm_msd,
        )

        displacement_results = pd.concat(
            [
                evaluate_displacement_model(
                    "Empirical SLOW/FAST",
                    experimental_displacement,
                    empirical_displacement,
                    args.displacement_column,
                    args.simulation_id_column,
                ),
                evaluate_displacement_model(
                    "Two-state HMM",
                    experimental_displacement,
                    hmm_displacement,
                    args.displacement_column,
                    args.simulation_id_column,
                ),
            ],
            ignore_index=True,
        )

        msd_results = pd.concat(
            [
                evaluate_msd_model(
                    "Empirical SLOW/FAST",
                    experimental_msd,
                    empirical_msd,
                    args.lag_column,
                    args.msd_column,
                    args.simulation_id_column,
                ),
                evaluate_msd_model(
                    "Two-state HMM",
                    experimental_msd,
                    hmm_msd,
                    args.lag_column,
                    args.msd_column,
                    args.simulation_id_column,
                ),
            ],
            ignore_index=True,
        )

        per_simulation = pd.concat(
            [displacement_results, msd_results],
            ignore_index=True,
        )
        summary = summarise_metrics(per_simulation, args.ci)
        summary = add_best_model(summary)
        compact_table = publication_table(summary)

        prefix = Path(args.output_prefix)
        per_simulation_path = prefix.with_name(
            prefix.name + "_per_simulation.csv"
        )
        summary_path = prefix.with_name(prefix.name + "_summary.csv")
        table_csv_path = prefix.with_name(
            prefix.name + "_publication_table.csv"
        )
        table_md_path = prefix.with_name(
            prefix.name + "_publication_table.md"
        )

        per_simulation.to_csv(per_simulation_path, index=False)
        summary.to_csv(summary_path, index=False)
        compact_table.to_csv(table_csv_path, index=False)
        write_markdown_table(compact_table, table_md_path)

        print("\nModel-comparison summary")
        print("========================")
        print(compact_table.to_string(index=False))
        print("\nFiles written:")
        print(f"  {per_simulation_path}")
        print(f"  {summary_path}")
        print(f"  {table_csv_path}")
        print(f"  {table_md_path}")

    except (FileNotFoundError, ValueError, pd.errors.ParserError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
