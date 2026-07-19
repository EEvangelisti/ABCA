#!/usr/bin/env python3
"""
Fit and interpret Gaussian HMMs for zoospore local dynamics.

Outputs:
- complete BIC table for all state counts and initializations;
- best BIC per state count and BIC plot;
- transition matrix and transition graph;
- state emission centres and empirical state statistics in biological units;
- decoded state and posterior probabilities for every observation;
- state occupancy and sojourn-time tables/plots;
- representative trajectories coloured by decoded HMM state;
- serialized model and scaler;
- ABCA-ready state quantile table (hmm_state_quantiles.tsv).

Input:
    METRICS_DIR/step_metrics.csv or step_metrics.tsv
    METRICS_DIR/turn_metrics.csv or turn_metrics.tsv

Each TrackMate trajectory remains an independent sequence through `lengths`.
"""

from __future__ import annotations

import argparse
import json
import math
import pickle
import sys
import warnings
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from hmmlearn.hmm import GaussianHMM
from matplotlib.collections import LineCollection
from sklearn.preprocessing import StandardScaler


# -----------------------------------------------------------------------------
# Data structures and utilities
# -----------------------------------------------------------------------------


@dataclass
class PreparedData:
    X_raw: np.ndarray
    X_transformed: np.ndarray
    X_scaled: np.ndarray
    lengths: list[int]
    observations: pd.DataFrame
    scaler: StandardScaler
    speed_col: str
    unit: str


def find_column(columns: Iterable[str], prefix: str) -> str:
    matches = [c for c in columns if c.startswith(prefix)]
    if not matches:
        raise KeyError(f"No column starts with {prefix!r}.")
    return matches[0]


def write_tsv(path: Path, dataframe: pd.DataFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    dataframe.to_csv(path, sep="\t", index=False)


def savefig(fig: mpl.figure.Figure, outdir: Path, stem: str, dpi: int) -> None:
    fig.savefig(outdir / f"{stem}.png", dpi=dpi, bbox_inches="tight")
    plt.close(fig)


def state_colour_mapping(n_states: int) -> tuple[mpl.colors.ListedColormap, mpl.colors.BoundaryNorm]:
    """Return one discrete colour mapping shared by all HMM-state figures."""
    base = plt.get_cmap("tab10")
    colours = [base(i % base.N) for i in range(n_states)]
    cmap = mpl.colors.ListedColormap(colours, name=f"hmm_states_{n_states}")
    norm = mpl.colors.BoundaryNorm(
        np.arange(-0.5, n_states + 0.5),
        cmap.N,
    )
    return cmap, norm


def transform_features(raw: np.ndarray, acceleration_scale: float) -> np.ndarray:
    """Robustify long-tailed variables before Gaussian HMM fitting."""
    result = np.empty_like(raw, dtype=float)
    result[:, 0] = np.log1p(np.clip(raw[:, 0], 0, None))
    result[:, 1] = np.log1p(np.clip(raw[:, 1], 0, None))
    result[:, 2] = np.arcsinh(raw[:, 2] / acceleration_scale)
    return result


def inverse_feature_centres(
    transformed: np.ndarray,
    acceleration_scale: float,
) -> np.ndarray:
    result = np.empty_like(transformed, dtype=float)
    result[:, 0] = np.expm1(transformed[:, 0])
    result[:, 1] = np.expm1(transformed[:, 1])
    result[:, 2] = np.sinh(transformed[:, 2]) * acceleration_scale
    return result


def parameter_count(n_states: int, n_features: int, covariance_type: str) -> int:
    """
    Number of free parameters used in BIC.

    start probabilities: K-1
    transition matrix: K(K-1)
    means: KD
    covariance parameters depend on covariance type
    """
    start = n_states - 1
    transition = n_states * (n_states - 1)
    means = n_states * n_features

    if covariance_type == "diag":
        covariance = n_states * n_features
    elif covariance_type == "spherical":
        covariance = n_states
    elif covariance_type == "full":
        covariance = n_states * n_features * (n_features + 1) // 2
    elif covariance_type == "tied":
        covariance = n_features * (n_features + 1) // 2
    else:
        raise ValueError(f"Unsupported covariance type: {covariance_type}")

    return start + transition + means + covariance


def model_bic(
    model: GaussianHMM,
    X: np.ndarray,
    lengths: list[int],
    covariance_type: str,
) -> tuple[float, float]:
    log_likelihood = float(model.score(X, lengths))
    p = parameter_count(model.n_components, X.shape[1], covariance_type)
    bic = -2.0 * log_likelihood + p * math.log(X.shape[0])
    return bic, log_likelihood


# -----------------------------------------------------------------------------
# Input preparation
# -----------------------------------------------------------------------------

def read_metric_table(directory: Path, stem: str) -> pd.DataFrame:
    """Read a metric table from CSV or TSV format."""
    csv_path = directory / f"{stem}.csv"
    tsv_path = directory / f"{stem}.tsv"

    if csv_path.exists():
        return pd.read_csv(csv_path)

    if tsv_path.exists():
        return pd.read_csv(tsv_path, sep="\t")

    raise FileNotFoundError(
        f"Neither {csv_path.name} nor {tsv_path.name} "
        f"was found in {directory}."
    )


def infer_unit_from_speed_column(speed_col: str) -> str:
    if speed_col.startswith("speed_") and speed_col.endswith("_per_s"):
        return speed_col[len("speed_") : -len("_per_s")]

    if speed_col.startswith("speed_") and speed_col.endswith("/s"):
        return speed_col[len("speed_") : -len("/s")]

    raise ValueError(
        f"Cannot infer spatial unit from speed column: {speed_col}"
    )


def find_signed_acceleration_column(columns: Iterable[str]) -> str:
    matches = [
        c for c in columns
        if c.startswith("acceleration_")
        and not c.startswith("absolute_acceleration_")
    ]

    if len(matches) != 1:
        raise KeyError(
            "Expected exactly one signed acceleration column, "
            f"found: {matches}"
        )

    return matches[0]


def prepare_data(
    global_dir: Path,
    min_track_observations: int,
    dt: float,
    acceleration_scale: float,
) -> PreparedData:
    steps = read_metric_table(global_dir, "step_metrics")
    turns = read_metric_table(global_dir, "turn_metrics")

    speed_col = find_column(steps.columns, "speed_")
    unit = infer_unit_from_speed_column(speed_col)

    required_step = {"track_id", "step_index", "frame_start", "frame_end", speed_col}
    missing = required_step - set(steps.columns)
    if missing:
        raise KeyError(f"Missing step columns: {sorted(missing)}")

    required_turn = {"track_id", "turn_index", "abs_turn_angle_deg"}
    missing = required_turn - set(turns.columns)
    if missing:
        raise KeyError(f"Missing turn columns: {sorted(missing)}")

    acceleration_col = find_signed_acceleration_column(turns.columns)

    turn_small = turns[
        [
            "track_id",
            "turn_index",
            "abs_turn_angle_deg",
            acceleration_col,
        ]
    ].copy()

    turn_small = turn_small.rename(
        columns={
            "turn_index": "step_index",
            acceleration_col: "acceleration",
        }
    )

    merged = steps.merge(
        turn_small,
        on=["track_id", "step_index"],
        how="inner",
        validate="one_to_one",
    )
    merged = merged.sort_values(["track_id", "step_index"]).reset_index(drop=True)

    coordinate_columns = [
        c for c in (
            f"x_start_{unit}",
            f"y_start_{unit}",
            f"x_end_{unit}",
            f"y_end_{unit}",
        )
        if c in merged.columns
    ]

    numeric_columns = [speed_col, "abs_turn_angle_deg", "acceleration"] + coordinate_columns
    for col in numeric_columns:
        merged[col] = pd.to_numeric(merged[col], errors="coerce")

    merged = merged.replace([np.inf, -np.inf], np.nan)
    merged = merged.dropna(subset=[speed_col, "abs_turn_angle_deg", "acceleration"])

    kept_groups: list[pd.DataFrame] = []
    lengths: list[int] = []

    for _, group in merged.groupby("track_id", sort=False):
        group = group.sort_values("step_index").copy()
        if len(group) < min_track_observations:
            continue
        kept_groups.append(group)
        lengths.append(len(group))

    if not kept_groups:
        raise ValueError(
            "No usable trajectory remained after filtering. "
            "Reduce --min-track-observations or inspect the input tables."
        )

    observations = pd.concat(kept_groups, ignore_index=True)
    raw = observations[[speed_col, "abs_turn_angle_deg", "acceleration"]].to_numpy(float)
    transformed = transform_features(raw, acceleration_scale)

    scaler = StandardScaler()
    scaled = scaler.fit_transform(transformed)

    return PreparedData(
        X_raw=raw,
        X_transformed=transformed,
        X_scaled=scaled,
        lengths=lengths,
        observations=observations,
        scaler=scaler,
        speed_col=speed_col,
        unit=unit,
    )


# -----------------------------------------------------------------------------
# Model fitting and selection
# -----------------------------------------------------------------------------


def fit_one_model(
    X: np.ndarray,
    lengths: list[int],
    n_states: int,
    seed: int,
    covariance_type: str,
    n_iter: int,
    tol: float,
) -> tuple[GaussianHMM, dict]:
    model = GaussianHMM(
        n_components=n_states,
        covariance_type=covariance_type,
        n_iter=n_iter,
        tol=tol,
        random_state=seed,
        min_covar=1e-4,
    )

    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        model.fit(X, lengths)

    converged = bool(getattr(model.monitor_, "converged", False))
    iterations = int(getattr(model.monitor_, "iter", -1))
    bic, log_likelihood = model_bic(model, X, lengths, covariance_type)

    row = {
        "n_states": n_states,
        "seed": seed,
        "bic": bic,
        "log_likelihood": log_likelihood,
        "converged": int(converged),
        "iterations": iterations,
        "warning_count": len(caught),
    }
    return model, row


def fit_grid(
    data: PreparedData,
    min_states: int,
    max_states: int,
    n_initializations: int,
    covariance_type: str,
    n_iter: int,
    tol: float,
) -> tuple[GaussianHMM, pd.DataFrame, pd.DataFrame]:
    all_rows: list[dict] = []
    best_models: dict[int, GaussianHMM] = {}
    best_rows: dict[int, dict] = {}

    total = (max_states - min_states + 1) * n_initializations
    done = 0

    for n_states in range(min_states, max_states + 1):
        for seed in range(n_initializations):
            done += 1
            print(
                f"[{done:>3}/{total}] Fitting {n_states} states, seed {seed}...",
                flush=True,
            )
            try:
                model, row = fit_one_model(
                    data.X_scaled,
                    data.lengths,
                    n_states,
                    seed,
                    covariance_type,
                    n_iter,
                    tol,
                )
            except Exception as exc:
                row = {
                    "n_states": n_states,
                    "seed": seed,
                    "bic": math.nan,
                    "log_likelihood": math.nan,
                    "converged": 0,
                    "iterations": -1,
                    "warning_count": -1,
                    "error": str(exc),
                }
                all_rows.append(row)
                print(f"    failed: {exc}", file=sys.stderr)
                continue

            all_rows.append(row)
            print(
                f"    BIC={row['bic']:.3f}; "
                f"converged={bool(row['converged'])}; "
                f"iterations={row['iterations']}",
                flush=True,
            )

            if n_states not in best_rows or row["bic"] < best_rows[n_states]["bic"]:
                best_rows[n_states] = row
                best_models[n_states] = model

    if not best_rows:
        raise RuntimeError("All HMM fits failed.")

    all_df = pd.DataFrame(all_rows)
    best_df = pd.DataFrame([best_rows[k] for k in sorted(best_rows)])
    selected_row = best_df.loc[best_df["bic"].idxmin()]
    selected_states = int(selected_row["n_states"])
    return best_models[selected_states], all_df, best_df


# -----------------------------------------------------------------------------
# Interpretation
# -----------------------------------------------------------------------------


def decode_observations(
    model: GaussianHMM,
    data: PreparedData,
) -> tuple[pd.DataFrame, np.ndarray]:
    states = model.predict(data.X_scaled, data.lengths)
    posterior = model.predict_proba(data.X_scaled, data.lengths)

    decoded = data.observations.copy()
    decoded["hmm_state"] = states
    decoded["state_posterior_max"] = posterior.max(axis=1)

    for state in range(model.n_components):
        decoded[f"posterior_state_{state}"] = posterior[:, state]

    return decoded, posterior


def state_statistics(
    model: GaussianHMM,
    data: PreparedData,
    decoded: pd.DataFrame,
    acceleration_scale: float,
) -> pd.DataFrame:
    transformed_centres = data.scaler.inverse_transform(model.means_)
    biological_centres = inverse_feature_centres(transformed_centres, acceleration_scale)

    rows: list[dict] = []
    for state in range(model.n_components):
        subset = decoded[decoded["hmm_state"] == state]
        rows.append(
            {
                "state": state,
                "n_observations": len(subset),
                "occupancy_fraction": len(subset) / len(decoded),
                f"emission_centre_speed_{data.unit}_per_s": biological_centres[state, 0],
                "emission_centre_abs_turn_angle_deg": biological_centres[state, 1],
                f"emission_centre_acceleration_{data.unit}_per_s2": biological_centres[state, 2],
                f"empirical_mean_speed_{data.unit}_per_s": subset[data.speed_col].mean(),
                f"empirical_median_speed_{data.unit}_per_s": subset[data.speed_col].median(),
                "empirical_mean_abs_turn_angle_deg": subset["abs_turn_angle_deg"].mean(),
                "empirical_median_abs_turn_angle_deg": subset["abs_turn_angle_deg"].median(),
                f"empirical_mean_acceleration_{data.unit}_per_s2": subset["acceleration"].mean(),
                f"empirical_median_acceleration_{data.unit}_per_s2": subset["acceleration"].median(),
                "mean_max_posterior_probability": subset["state_posterior_max"].mean(),
            }
        )

    result = pd.DataFrame(rows)
    return result.sort_values(f"empirical_median_speed_{data.unit}_per_s").reset_index(drop=True)


def sojourn_table(decoded: pd.DataFrame, dt: float, unit: str) -> pd.DataFrame:
    rows: list[dict] = []

    for track_id, group in decoded.groupby("track_id", sort=False):
        group = group.sort_values("step_index")
        states = group["hmm_state"].to_numpy(int)
        speeds = group[group.columns[group.columns.str.startswith("speed_")][0]].to_numpy(float)

        start = 0
        episode = 0
        for i in range(1, len(states) + 1):
            if i == len(states) or states[i] != states[start]:
                episode += 1
                segment_speeds = speeds[start:i]
                rows.append(
                    {
                        "track_id": track_id,
                        "episode_index": episode,
                        "state": int(states[start]),
                        "start_step_index": int(group.iloc[start]["step_index"]),
                        "end_step_index": int(group.iloc[i - 1]["step_index"]),
                        "n_observations": i - start,
                        "duration_s": (i - start) * dt,
                        f"mean_speed_{unit}_per_s": float(np.mean(segment_speeds)),
                        f"median_speed_{unit}_per_s": float(np.median(segment_speeds)),
                    }
                )
                start = i

    return pd.DataFrame(rows)



def find_signed_turn_column(columns: Iterable[str]) -> str | None:
    """Return the signed turn-angle column when available."""
    preferred = ["turn_angle_deg", "signed_turn_angle_deg"]
    for name in preferred:
        if name in columns:
            return name

    matches = [
        c for c in columns
        if "turn_angle" in c
        and "abs_" not in c
        and "absolute_" not in c
    ]
    if len(matches) == 1:
        return matches[0]
    return None


def state_quantile_table(
    decoded: pd.DataFrame,
    speed_col: str,
    n_states: int,
    quantile_count: int,
) -> tuple[pd.DataFrame, bool]:
    """Build empirical state-specific quantiles for the ABCA HMM plugin."""
    probabilities = np.linspace(0.001, 0.999, quantile_count)
    signed_turn_col = find_signed_turn_column(decoded.columns)
    rows: list[dict] = []

    for state in range(n_states):
        subset = decoded.loc[decoded["hmm_state"] == state].copy()
        if subset.empty:
            raise ValueError(f"No decoded observations found for HMM state {state}.")

        speed_values = pd.to_numeric(
            subset[speed_col], errors="coerce"
        ).to_numpy(float)
        turn_values = pd.to_numeric(
            subset["abs_turn_angle_deg"], errors="coerce"
        ).to_numpy(float)

        speed_values = speed_values[np.isfinite(speed_values)]
        turn_values = turn_values[np.isfinite(turn_values)]

        if speed_values.size == 0 or turn_values.size == 0:
            raise ValueError(
                f"State {state} has no finite speed or turn observations."
            )

        if signed_turn_col is not None:
            signed_values = pd.to_numeric(
                subset[signed_turn_col], errors="coerce"
            ).to_numpy(float)
            signed_values = signed_values[np.isfinite(signed_values)]
            positive_probability = (
                float(np.mean(signed_values > 0.0))
                if signed_values.size
                else 0.5
            )
        else:
            positive_probability = 0.5

        speed_quantiles = np.quantile(speed_values, probabilities)
        turn_quantiles = np.quantile(turn_values, probabilities)

        for probability, speed, angle in zip(
            probabilities, speed_quantiles, turn_quantiles
        ):
            rows.append(
                {
                    "state": state,
                    "probability": float(probability),
                    "speed_micron_per_s": float(speed),
                    "abs_turn_angle_deg": float(angle),
                    "positive_turn_probability": positive_probability,
                    "n_observations": int(len(subset)),
                }
            )

    return pd.DataFrame(rows), signed_turn_col is not None


# -----------------------------------------------------------------------------
# Figures
# -----------------------------------------------------------------------------


def plot_bic(best_df: pd.DataFrame, outdir: Path, dpi: int) -> None:
    fig, ax = plt.subplots(figsize=(6.5, 4.5))
    ax.plot(best_df["n_states"], best_df["bic"], marker="o")
    best = best_df.loc[best_df["bic"].idxmin()]
    ax.scatter([best["n_states"]], [best["bic"]], s=70)
    ax.set_xlabel("Number of hidden states")
    ax.set_ylabel("Best BIC")
    ax.set_title("HMM model selection")
    ax.text(
        0.98,
        0.95,
        f"selected: {int(best['n_states'])} states",
        transform=ax.transAxes,
        ha="right",
        va="top",
    )
    savefig(fig, outdir, "01_hmm_bic_model_selection", dpi)


def plot_transition_matrix(model: GaussianHMM, outdir: Path, dpi: int) -> None:
    fig, ax = plt.subplots(figsize=(6.2, 5.4))
    image = ax.imshow(model.transmat_, vmin=0, vmax=1, interpolation="nearest")
    for i in range(model.n_components):
        for j in range(model.n_components):
            value = model.transmat_[i, j]
            ax.text(j, i, f"{value:.2f}", ha="center", va="center")
    ax.set_xlabel("State at t+1")
    ax.set_ylabel("State at t")
    ax.set_title("HMM transition matrix")
    ax.set_xticks(range(model.n_components))
    ax.set_yticks(range(model.n_components))
    fig.colorbar(image, ax=ax, label="Transition probability")
    savefig(fig, outdir, "02_hmm_transition_matrix", dpi)


def plot_transition_graph(
    model: GaussianHMM,
    outdir: Path,
    dpi: int,
    minimum_probability: float,
) -> None:
    """Plot a colour-consistent transition graph with separated reciprocal edges."""
    n = model.n_components
    theta = np.linspace(0, 2 * np.pi, n, endpoint=False)
    xy = np.column_stack([np.cos(theta), np.sin(theta)])
    cmap, _ = state_colour_mapping(n)

    fig, ax = plt.subplots(figsize=(8.2, 8.2))
    ax.set_aspect("equal")
    ax.axis("off")

    node_radius = 0.14
    for state, (x, y) in enumerate(xy):
        circle = plt.Circle(
            (x, y),
            node_radius,
            facecolor=cmap(state),
            edgecolor="black",
            linewidth=1.8,
            zorder=4,
        )
        ax.add_patch(circle)
        ax.text(
            x,
            y,
            str(state),
            ha="center",
            va="center",
            fontsize=13,
            fontweight="bold",
            color="black",
            zorder=5,
        )

    for i in range(n):
        for j in range(n):
            p = float(model.transmat_[i, j])
            if i == j or p < minimum_probability:
                continue

            start_node = xy[i]
            end_node = xy[j]
            vector = end_node - start_node
            length = float(np.linalg.norm(vector))
            unit_vector = vector / length
            normal = np.array([-unit_vector[1], unit_vector[0]])

            start_point = start_node + (node_radius + 0.015) * unit_vector
            end_point = end_node - (node_radius + 0.015) * unit_vector

            # Reciprocal transitions follow opposite arcs, which prevents both
            # arrows and probability labels from lying on top of one another.
            radial_sign = 1.0 if i < j else -1.0
            curvature = radial_sign * (0.16 + 0.015 * abs(i - j))

            arrow = mpl.patches.FancyArrowPatch(
                start_point,
                end_point,
                arrowstyle="-|>",
                mutation_scale=11 + 7 * p,
                linewidth=0.9 + 5.0 * p,
                color="0.20",
                alpha=min(1.0, 0.45 + p),
                connectionstyle=f"arc3,rad={curvature}",
                shrinkA=0,
                shrinkB=0,
                zorder=2,
            )
            ax.add_patch(arrow)

            midpoint = (start_point + end_point) / 2.0
            # Approximate the displaced midpoint of the circular arc. The
            # additional direction-dependent offset keeps reciprocal labels
            # visually separate even for strong bidirectional transitions.
            label_offset = radial_sign * (0.11 + 0.20 * abs(curvature))
            label_position = midpoint + label_offset * normal
            ax.text(
                label_position[0],
                label_position[1],
                f"{p:.2f}",
                fontsize=8.5,
                ha="center",
                va="center",
                bbox={
                    "boxstyle": "round,pad=0.18",
                    "facecolor": "white",
                    "edgecolor": "none",
                    "alpha": 0.88,
                },
                zorder=3,
            )

    ax.set_xlim(-1.45, 1.45)
    ax.set_ylim(-1.45, 1.45)
    ax.set_title(
        f"Transitions with probability ≥ {minimum_probability:g}\n"
        "(self-transitions omitted)"
    )
    savefig(fig, outdir, "03_hmm_transition_graph", dpi)


def plot_state_profiles(
    stats: pd.DataFrame,
    unit: str,
    outdir: Path,
    dpi: int,
) -> None:
    speed_col = f"empirical_median_speed_{unit}_per_s"
    accel_col = f"empirical_median_acceleration_{unit}_per_s2"

    metrics = [
        (speed_col, f"Median speed ({unit}/s)"),
        ("empirical_median_abs_turn_angle_deg", "Median absolute turn (degrees)"),
        (accel_col, f"Median acceleration ({unit}/s²)"),
        ("occupancy_fraction", "Occupancy fraction"),
    ]

    for index, (column, ylabel) in enumerate(metrics, start=4):
        fig, ax = plt.subplots(figsize=(6.5, 4.5))
        ax.bar(stats["state"].astype(str), stats[column])
        ax.set_xlabel("HMM state")
        ax.set_ylabel(ylabel)
        ax.set_title(ylabel + " by decoded state")
        savefig(fig, outdir, f"{index:02d}_hmm_state_{column}", dpi)


def plot_sojourns(
    sojourns: pd.DataFrame,
    n_states: int,
    outdir: Path,
    dpi: int,
) -> None:
    fig, ax = plt.subplots(figsize=(7.2, 4.8))
    data = [
        sojourns.loc[sojourns["state"] == state, "duration_s"].to_numpy(float)
        for state in range(n_states)
    ]

    boxplot_kwargs = dict(showfliers=False)
    major, minor = map(int, mpl.__version__.split(".")[:2])
    if (major, minor) >= (3, 9):
        boxplot_kwargs["tick_labels"] = [str(i) for i in range(n_states)]
    else:
        boxplot_kwargs["labels"] = [str(i) for i in range(n_states)]
    ax.boxplot(data, **boxplot_kwargs)
    ax.set_xlabel("HMM state")
    ax.set_ylabel("Episode duration (s)")
    ax.set_title("State sojourn durations")
    savefig(fig, outdir, "08_hmm_state_sojourn_boxplot", dpi)

    for state in range(n_states):
        values = sojourns.loc[sojourns["state"] == state, "duration_s"].to_numpy(float)
        if values.size == 0:
            continue
        fig, ax = plt.subplots(figsize=(6.5, 4.4))
        ax.hist(values, bins=50)
        ax.axvline(np.median(values), linestyle="--", linewidth=1)
        ax.set_xlabel("Episode duration (s)")
        ax.set_ylabel("Count")
        ax.set_title(f"State {state} sojourn duration")
        savefig(fig, outdir, f"09_state_{state}_sojourn_distribution", dpi)


def plot_coloured_trajectories(
    decoded: pd.DataFrame,
    unit: str,
    outdir: Path,
    dpi: int,
    max_tracks: int,
) -> None:
    x_start = f"x_start_{unit}"
    y_start = f"y_start_{unit}"
    x_end = f"x_end_{unit}"
    y_end = f"y_end_{unit}"

    required = {x_start, y_start, x_end, y_end}
    if not required.issubset(decoded.columns):
        print(
            "Trajectory-state plots skipped: coordinate columns were not found.",
            file=sys.stderr,
        )
        return

    track_lengths = decoded.groupby("track_id").size().sort_values(ascending=False)
    selected_ids = track_lengths.head(max_tracks).index
    subset = decoded[decoded["track_id"].isin(selected_ids)]

    n_states = int(decoded["hmm_state"].max()) + 1
    cmap, norm = state_colour_mapping(n_states)

    # Combined centred trajectories.
    fig, ax = plt.subplots(figsize=(7.5, 7.5))
    for _, group in subset.groupby("track_id", sort=False):
        group = group.sort_values("step_index")
        x0 = float(group.iloc[0][x_start])
        y0 = float(group.iloc[0][y_start])
        segments = np.stack(
            [
                np.column_stack([group[x_start] - x0, group[y_start] - y0]),
                np.column_stack([group[x_end] - x0, group[y_end] - y0]),
            ],
            axis=1,
        )
        collection = LineCollection(
            segments,
            cmap=cmap,
            norm=norm,
            linewidths=0.8,
        )
        collection.set_array(group["hmm_state"].to_numpy(float))
        ax.add_collection(collection)

    ax.autoscale()
    ax.set_aspect("equal", adjustable="box")
    ax.set_xlabel(f"Δx ({unit})")
    ax.set_ylabel(f"Δy ({unit})")
    ax.set_title(f"Longest trajectories coloured by HMM state (n={len(selected_ids)})")
    scalar = mpl.cm.ScalarMappable(cmap=cmap, norm=norm)
    scalar.set_array([])
    fig.colorbar(
        scalar,
        ax=ax,
        ticks=range(int(decoded["hmm_state"].max()) + 1),
        label="HMM state",
    )
    savefig(fig, outdir, "10_centered_trajectories_by_hmm_state", dpi)

    # Individual representative trajectories.
    representative_dir = outdir / "representative_trajectories"
    representative_dir.mkdir(exist_ok=True)

    for rank, track_id in enumerate(selected_ids[: min(20, max_tracks)], start=1):
        group = decoded[decoded["track_id"] == track_id].sort_values("step_index")
        segments = np.stack(
            [
                np.column_stack([group[x_start], group[y_start]]),
                np.column_stack([group[x_end], group[y_end]]),
            ],
            axis=1,
        )
        fig, ax = plt.subplots(figsize=(6.5, 6.0))
        collection = LineCollection(
            segments,
            cmap=cmap,
            norm=norm,
            linewidths=2,
        )
        collection.set_array(group["hmm_state"].to_numpy(float))
        ax.add_collection(collection)
        ax.autoscale()
        ax.set_aspect("equal", adjustable="box")
        ax.set_xlabel(f"x ({unit})")
        ax.set_ylabel(f"y ({unit})")
        ax.set_title(f"Track {track_id} coloured by HMM state")
        scalar = mpl.cm.ScalarMappable(cmap=cmap, norm=norm)
        scalar.set_array([])
        fig.colorbar(
            scalar,
            ax=ax,
            ticks=range(int(decoded["hmm_state"].max()) + 1),
            label="HMM state",
        )
        savefig(
            fig,
            representative_dir,
            f"track_{rank:02d}_id_{track_id}_hmm_states",
            dpi,
        )


# -----------------------------------------------------------------------------
# CLI
# -----------------------------------------------------------------------------


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fit, select and interpret local-dynamics HMMs."
    )
    parser.add_argument("global_dir", type=Path)
    parser.add_argument("-o", "--outdir", type=Path, default=None)
    parser.add_argument("--dt", type=float, default=0.22)
    parser.add_argument("--min-states", type=int, default=2)
    parser.add_argument("--max-states", type=int, default=7)
    parser.add_argument("--initializations", type=int, default=10)
    parser.add_argument("--n-iter", type=int, default=500)
    parser.add_argument("--tol", type=float, default=1e-4)
    parser.add_argument(
        "--covariance-type",
        choices=("diag", "spherical", "full", "tied"),
        default="diag",
    )
    parser.add_argument("--min-track-observations", type=int, default=10)
    parser.add_argument(
        "--acceleration-scale",
        type=float,
        default=100.0,
        help="Scale used in asinh(acceleration / scale).",
    )
    parser.add_argument("--transition-graph-threshold", type=float, default=0.02)
    parser.add_argument("--max-tracks-plot", type=int, default=200)
    parser.add_argument("--dpi", type=int, default=300)
    parser.add_argument(
        "--quantile-count",
        type=int,
        default=1001,
        help="Number of empirical quantile points exported per HMM state.",
    )
    args = parser.parse_args(argv)

    if args.dt <= 0:
        parser.error("--dt must be > 0")
    if args.min_states < 2 or args.max_states < args.min_states:
        parser.error("Invalid state range.")
    if args.initializations < 1:
        parser.error("--initializations must be >= 1")
    if args.min_track_observations < 3:
        parser.error("--min-track-observations must be >= 3")
    if args.quantile_count < 2:
        parser.error("--quantile-count must be >= 2")

    return args


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv)
    global_dir = args.global_dir.resolve()
    outdir = (args.outdir or global_dir / "hmm_analysis").resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    data = prepare_data(
        global_dir,
        args.min_track_observations,
        args.dt,
        args.acceleration_scale,
    )

    print(
        f"Prepared {len(data.lengths)} independent trajectories "
        f"and {len(data.X_scaled)} local observations.",
        flush=True,
    )

    model, all_fits, best_by_state = fit_grid(
        data,
        args.min_states,
        args.max_states,
        args.initializations,
        args.covariance_type,
        args.n_iter,
        args.tol,
    )

    write_tsv(outdir / "hmm_all_fits.tsv", all_fits)
    write_tsv(outdir / "hmm_best_fit_per_state_count.tsv", best_by_state)

    decoded, _ = decode_observations(model, data)
    write_tsv(outdir / "hmm_decoded_observations.tsv", decoded)

    state_quantiles, signed_turn_available = state_quantile_table(
        decoded,
        data.speed_col,
        model.n_components,
        args.quantile_count,
    )
    write_tsv(outdir / "hmm_state_quantiles.tsv", state_quantiles)

    stats = state_statistics(
        model,
        data,
        decoded,
        args.acceleration_scale,
    )
    write_tsv(outdir / "hmm_state_statistics_biological_units.tsv", stats)

    transition_df = pd.DataFrame(
        model.transmat_,
        columns=[f"to_state_{i}" for i in range(model.n_components)],
    )
    transition_df.insert(0, "from_state", range(model.n_components))
    write_tsv(outdir / "hmm_transition_matrix.tsv", transition_df)

    start_df = pd.DataFrame(
        {"state": range(model.n_components), "start_probability": model.startprob_}
    )
    write_tsv(outdir / "hmm_start_probabilities.tsv", start_df)

    sojourns = sojourn_table(decoded, args.dt, data.unit)
    write_tsv(outdir / "hmm_state_sojourns.tsv", sojourns)

    sojourn_summary = (
        sojourns.groupby("state")["duration_s"]
        .agg(["count", "mean", "median", "std", "min", "max"])
        .reset_index()
    )
    write_tsv(outdir / "hmm_state_sojourn_summary.tsv", sojourn_summary)

    with (outdir / "hmm_model.pkl").open("wb") as handle:
        pickle.dump(model, handle)
    with (outdir / "hmm_scaler.pkl").open("wb") as handle:
        pickle.dump(data.scaler, handle)

    metadata = {
        "selected_n_states": model.n_components,
        "features_raw": [
            f"speed_{data.unit}_per_s",
            "absolute_turn_angle_deg",
            f"signed_acceleration_{data.unit}_per_s2",
        ],
        "feature_transformations": [
            "log1p(speed)",
            "log1p(abs_turn_angle)",
            f"asinh(acceleration/{args.acceleration_scale})",
        ],
        "dt_s": args.dt,
        "sequence_count": len(data.lengths),
        "observation_count": len(data.X_scaled),
        "covariance_type": args.covariance_type,
        "quantile_count": args.quantile_count,
        "signed_turn_available": signed_turn_available,
        "hmm_state_quantiles_file": "hmm_state_quantiles.tsv",
    }
    (outdir / "hmm_metadata.json").write_text(
        json.dumps(metadata, indent=2),
        encoding="utf-8",
    )

    plot_bic(best_by_state, outdir, args.dpi)
    plot_transition_matrix(model, outdir, args.dpi)
    plot_transition_graph(
        model,
        outdir,
        args.dpi,
        args.transition_graph_threshold,
    )
    plot_state_profiles(stats, data.unit, outdir, args.dpi)
    plot_sojourns(sojourns, model.n_components, outdir, args.dpi)
    plot_coloured_trajectories(
        decoded,
        data.unit,
        outdir,
        args.dpi,
        args.max_tracks_plot,
    )

    selected = best_by_state.loc[best_by_state["bic"].idxmin()]
    print("")
    print(f"Selected states: {model.n_components}")
    print(f"BIC: {selected['bic']}")
    print("Start probabilities:")
    print(model.startprob_)
    print("Transition matrix:")
    print(model.transmat_)
    print(f"Results written to: {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
