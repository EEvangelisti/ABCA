#!/usr/bin/env python3
"""Compare numerical metrics stored in two analysis directories.

The script recursively matches CSV files by relative path, compares every
shared numeric column, writes a summary table, and optionally produces ECDF
plots.

Dependencies: numpy, scipy, matplotlib
"""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from scipy.stats import ks_2samp, wasserstein_distance


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def as_float(value: object) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return math.nan


def finite_column(rows: list[dict[str, str]], column: str) -> np.ndarray:
    values = np.asarray([as_float(row.get(column)) for row in rows], dtype=float)
    return values[np.isfinite(values)]


def numeric_columns(rows: list[dict[str, str]]) -> set[str]:
    if not rows:
        return set()
    return {column for column in rows[0] if finite_column(rows, column).size}


def summary(values: np.ndarray) -> dict[str, float | int]:
    q25, median, q75 = np.quantile(values, [0.25, 0.5, 0.75])
    return {
        "n": int(values.size),
        "mean": float(np.mean(values)),
        "sd": float(np.std(values, ddof=1)) if values.size > 1 else math.nan,
        "median": float(median),
        "q25": float(q25),
        "q75": float(q75),
        "iqr": float(q75 - q25),
    }


def hedges_g(x: np.ndarray, y: np.ndarray) -> float:
    nx, ny = x.size, y.size
    if nx < 2 or ny < 2:
        return math.nan
    vx, vy = np.var(x, ddof=1), np.var(y, ddof=1)
    pooled_var = ((nx - 1) * vx + (ny - 1) * vy) / (nx + ny - 2)
    if pooled_var <= 0:
        return 0.0 if np.mean(x) == np.mean(y) else math.nan
    d = (np.mean(y) - np.mean(x)) / math.sqrt(pooled_var)
    correction = 1.0 - 3.0 / (4.0 * (nx + ny) - 9.0)
    return float(correction * d)


def overlap_coefficient(x: np.ndarray, y: np.ndarray, bins: int) -> float:
    low = min(float(np.min(x)), float(np.min(y)))
    high = max(float(np.max(x)), float(np.max(y)))
    if low == high:
        return 1.0
    edges = np.linspace(low, high, bins + 1)
    hx, _ = np.histogram(x, bins=edges, density=True)
    hy, _ = np.histogram(y, bins=edges, density=True)
    return float(np.sum(np.minimum(hx, hy) * np.diff(edges)))


def relative_difference(reference: float, comparison: float) -> float:
    return math.nan if reference == 0 else float((comparison - reference) / abs(reference))


def normalized_wasserstein(x: np.ndarray, y: np.ndarray, sx: dict, sy: dict) -> tuple[float, float]:
    raw = float(wasserstein_distance(x, y))
    scale = 0.5 * (float(sx["iqr"]) + float(sy["iqr"]))
    if scale <= 0:
        scale = 0.5 * (
            (float(sx["sd"]) if np.isfinite(sx["sd"]) else 0.0)
            + (float(sy["sd"]) if np.isfinite(sy["sd"]) else 0.0)
        )
    normalized = raw / scale if scale > 0 else (0.0 if raw == 0 else math.inf)
    return raw, float(normalized)


def similarity_score(ks: float, normalized_w: float, overlap: float) -> float:
    """Descriptive score in [0,1], intended for ranking rather than testing."""
    return float(((1.0 - ks) + math.exp(-max(0.0, normalized_w)) + overlap) / 3.0)


def ecdf(values: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    x = np.sort(values)
    return x, np.arange(1, x.size + 1, dtype=float) / x.size


def safe_filename(text: str) -> str:
    return "".join(c if c.isalnum() or c in "._-" else "_" for c in text)


def plot_ecdf(x: np.ndarray, y: np.ndarray, labels: tuple[str, str], title: str, path: Path, dpi: int) -> None:
    xx, fx = ecdf(x)
    yy, fy = ecdf(y)
    fig, ax = plt.subplots(figsize=(6.5, 4.5))
    ax.step(xx, fx, where="post", label=labels[0])
    ax.step(yy, fy, where="post", label=labels[1])
    ax.set(title=title, xlabel="Value", ylabel="Empirical cumulative probability")
    ax.legend()
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=dpi, bbox_inches="tight")
    plt.close(fig)


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference_dir", type=Path, help="Experimental metrics directory")
    parser.add_argument("comparison_dir", type=Path, help="Simulated metrics directory")
    parser.add_argument("-o", "--outdir", type=Path, default=Path("metric_comparison"))
    parser.add_argument("--reference-label", default="Experiment")
    parser.add_argument("--comparison-label", default="Simulation")
    parser.add_argument("--min-n", type=int, default=5)
    parser.add_argument("--hist-bins", type=int, default=100)
    parser.add_argument("--no-plots", action="store_true")
    parser.add_argument("--dpi", type=int, default=200)
    args = parser.parse_args()

    if not args.reference_dir.is_dir() or not args.comparison_dir.is_dir():
        parser.error("Both inputs must be directories")

    results: list[dict[str, object]] = []
    skipped: list[dict[str, object]] = []
    matched_files = 0

    for reference_file in sorted(args.reference_dir.rglob("*.csv")):
        relative = reference_file.relative_to(args.reference_dir)
        comparison_file = args.comparison_dir / relative
        if not comparison_file.exists():
            continue
        matched_files += 1
        reference_rows = read_csv(reference_file)
        comparison_rows = read_csv(comparison_file)
        columns = sorted(numeric_columns(reference_rows) & numeric_columns(comparison_rows))

        for column in columns:
            x = finite_column(reference_rows, column)
            y = finite_column(comparison_rows, column)
            if x.size < args.min_n or y.size < args.min_n:
                skipped.append({
                    "file": str(relative), "metric": column,
                    "n_reference": int(x.size), "n_comparison": int(y.size),
                    "reason": "insufficient finite values",
                })
                continue

            sx, sy = summary(x), summary(y)
            ks = ks_2samp(x, y, alternative="two-sided", method="auto")
            raw_w, norm_w = normalized_wasserstein(x, y, sx, sy)
            overlap = overlap_coefficient(x, y, args.hist_bins)
            score = similarity_score(float(ks.statistic), norm_w, overlap)

            results.append({
                "file": str(relative),
                "metric": column,
                "n_reference": sx["n"],
                "n_comparison": sy["n"],
                "mean_reference": sx["mean"],
                "mean_comparison": sy["mean"],
                "mean_relative_difference": relative_difference(float(sx["mean"]), float(sy["mean"])),
                "median_reference": sx["median"],
                "median_comparison": sy["median"],
                "median_relative_difference": relative_difference(float(sx["median"]), float(sy["median"])),
                "sd_reference": sx["sd"],
                "sd_comparison": sy["sd"],
                "q25_reference": sx["q25"],
                "q25_comparison": sy["q25"],
                "q75_reference": sx["q75"],
                "q75_comparison": sy["q75"],
                "hedges_g": hedges_g(x, y),
                "ks_statistic": float(ks.statistic),
                "ks_pvalue": float(ks.pvalue),
                "wasserstein_distance": raw_w,
                "wasserstein_normalized_by_pooled_iqr": norm_w,
                "distribution_overlap": overlap,
                "similarity_score": score,
            })

            if not args.no_plots:
                name = safe_filename(f"{relative}__{column}.png")
                plot_ecdf(
                    x, y,
                    (args.reference_label, args.comparison_label),
                    f"{relative} — {column}",
                    args.outdir / "ecdf" / name,
                    args.dpi,
                )

    if matched_files == 0:
        raise FileNotFoundError("No CSV files with matching relative paths were found")

    results.sort(key=lambda row: float(row["similarity_score"]))
    write_csv(args.outdir / "metric_comparison.csv", results)
    write_csv(args.outdir / "skipped_metrics.csv", skipped)

    ranking = [
        {
            "rank": i + 1,
            "file": row["file"],
            "metric": row["metric"],
            "similarity_score": row["similarity_score"],
            "ks_statistic": row["ks_statistic"],
            "wasserstein_normalized_by_pooled_iqr": row["wasserstein_normalized_by_pooled_iqr"],
            "distribution_overlap": row["distribution_overlap"],
            "median_relative_difference": row["median_relative_difference"],
        }
        for i, row in enumerate(results)
    ]
    write_csv(args.outdir / "metric_ranking.csv", ranking)

    print(f"Compared {len(results)} numeric metrics across {matched_files} matched CSV files")
    print(f"Results written to: {args.outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
