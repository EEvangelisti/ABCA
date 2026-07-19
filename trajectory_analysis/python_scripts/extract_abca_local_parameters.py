#!/usr/bin/env python3
"""
Extract the local empirical parameters required by the zoospore ABCA model.

The script implements the statistical specification described in the laboratory
notebook:

1. RUN/STOP is represented by an empirical two-state Markov chain.
2. Speeds and turning angles are represented by empirical quantile functions.
3. Speed and turning magnitude are transformed to latent standard-normal
   scores using empirical ranks.
4. Their joint temporal dynamics are fitted as a stationary bivariate Gaussian
   VAR(1) process:
       Z_(t+1) = A Z_t + epsilon_t,  epsilon_t ~ N(0, Q)
   with a prescribed stationary covariance matrix R.
5. The contemporaneous speed-turn dependence is estimated with Spearman's rho
   and converted to the Gaussian-copula correlation:
       rho_gaussian = 2 * sin(pi * rho_spearman / 6)
6. Acceleration is derived from successive speeds and is used only to define a
   configurable numerical guard based on q90(|a|).
7. Global trajectory statistics are exported only as validation targets.

Only NumPy is required.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from collections import defaultdict
from pathlib import Path
from statistics import NormalDist
from typing import Iterable, Sequence

import numpy as np


# ---------------------------------------------------------------------------
# Generic utilities
# ---------------------------------------------------------------------------

def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def as_float(value: object) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return math.nan


def finite(values: Iterable[float]) -> np.ndarray:
    array = np.asarray(list(values), dtype=float)
    return array[np.isfinite(array)]


def first_existing(columns: Sequence[str], candidates: Sequence[str]) -> str | None:
    available = set(columns)
    return next((candidate for candidate in candidates if candidate in available), None)


def first_prefix(columns: Sequence[str], prefixes: Sequence[str]) -> str | None:
    for prefix in prefixes:
        matches = sorted(column for column in columns if column.startswith(prefix))
        if matches:
            return matches[0]
    return None


def summary(values: np.ndarray) -> dict[str, float | int]:
    values = np.asarray(values, dtype=float)
    values = values[np.isfinite(values)]
    keys = ("n", "mean", "sd", "median", "q10", "q25", "q75", "q90", "min", "max")
    if values.size == 0:
        return {key: math.nan for key in keys}

    return {
        "n": int(values.size),
        "mean": float(np.mean(values)),
        "sd": float(np.std(values, ddof=1)) if values.size > 1 else 0.0,
        "median": float(np.median(values)),
        "q10": float(np.quantile(values, 0.10)),
        "q25": float(np.quantile(values, 0.25)),
        "q75": float(np.quantile(values, 0.75)),
        "q90": float(np.quantile(values, 0.90)),
        "min": float(np.min(values)),
        "max": float(np.max(values)),
    }


def format_number(value: float) -> str:
    if not np.isfinite(value):
        return "NA"
    if abs(value) >= 1000:
        return f"{value:,.1f}"
    if abs(value) >= 100:
        return f"{value:.1f}"
    if abs(value) >= 10:
        return f"{value:.2f}"
    return f"{value:.3f}"


# ---------------------------------------------------------------------------
# Rank correlations and Gaussian-copula parameters
# ---------------------------------------------------------------------------

def rankdata(values: np.ndarray) -> np.ndarray:
    """Average ranks, including ties, using 1-based ranks."""
    values = np.asarray(values, dtype=float)
    order = np.argsort(values, kind="mergesort")
    sorted_values = values[order]
    ranks = np.empty(values.size, dtype=float)

    start = 0
    while start < values.size:
        end = start + 1
        while end < values.size and sorted_values[end] == sorted_values[start]:
            end += 1
        ranks[order[start:end]] = 0.5 * (start + end - 1) + 1.0
        start = end

    return ranks


def pearson(x: np.ndarray, y: np.ndarray) -> float:
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    mask = np.isfinite(x) & np.isfinite(y)
    x = x[mask]
    y = y[mask]

    if x.size < 3 or np.std(x) == 0.0 or np.std(y) == 0.0:
        return math.nan
    return float(np.corrcoef(x, y)[0, 1])


def spearman(x: np.ndarray, y: np.ndarray) -> tuple[float, int]:
    """Spearman correlation, i.e. Pearson correlation of average ranks."""
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    mask = np.isfinite(x) & np.isfinite(y)
    x = x[mask]
    y = y[mask]

    if x.size < 3:
        return math.nan, int(x.size)

    rho = pearson(rankdata(x), rankdata(y))
    return rho, int(x.size)


def gaussian_copula_rho(rho_spearman: float) -> float:
    """
    Convert Spearman's rho to the latent Gaussian correlation of a Gaussian
    copula: rho_G = 2 sin(pi rho_S / 6).
    """
    if not np.isfinite(rho_spearman):
        return math.nan
    rho = 2.0 * math.sin(math.pi * float(rho_spearman) / 6.0)
    return float(np.clip(rho, -1.0, 1.0))


def normal_scores(values: np.ndarray) -> np.ndarray:
    """
    Convert observations to latent standard-normal scores.

    The pseudo-observation associated with rank r among n observations is
        u = (r - 1/2) / n,
    followed by z = Phi^(-1)(u). Average ranks are used for ties.
    """
    values = np.asarray(values, dtype=float)
    if values.size == 0:
        return np.asarray([], dtype=float)

    ranks = rankdata(values)
    probabilities = (ranks - 0.5) / values.size
    normal = NormalDist()
    return np.asarray([normal.inv_cdf(float(u)) for u in probabilities], dtype=float)


def _stationary_covariance_valid(
    transition: np.ndarray,
    stationary_covariance: np.ndarray,
    tolerance: float = 1e-10,
) -> tuple[bool, np.ndarray]:
    innovation_covariance = (
        stationary_covariance
        - transition @ stationary_covariance @ transition.T
    )
    innovation_covariance = 0.5 * (
        innovation_covariance + innovation_covariance.T
    )
    eigenvalues = np.linalg.eigvalsh(innovation_covariance)
    spectral_radius = float(np.max(np.abs(np.linalg.eigvals(transition))))
    valid = bool(
        spectral_radius < 1.0 - tolerance
        and float(np.min(eigenvalues)) >= -tolerance
    )
    return valid, innovation_covariance


def fit_stationary_bivariate_var1(
    turns: list[dict[str, float | int]],
    contemporaneous_rho: float,
) -> dict[str, object]:
    """
    Fit the latent stationary bivariate Gaussian VAR(1)

        Z_(t+1) = A Z_t + epsilon_t,
        epsilon_t ~ N(0, Q),

    to the paired variables (speed, absolute turning angle).

    The stationary covariance is fixed to

        R = [[1, rho_vtheta],
             [rho_vtheta, 1]],

    so both latent marginals remain N(0, 1), as required by the Gaussian-copula
    transformation. A is estimated from the empirical lag-one cross-covariance
    through the multivariate Yule-Walker relation C_1 = A R. If finite-sample
    noise makes the resulting Q = R - A R A^T non-positive-semidefinite, A is
    uniformly shrunk by the smallest amount required to recover a valid
    stationary process. The shrinkage factor is exported explicitly.
    """
    if not np.isfinite(contemporaneous_rho):
        raise ValueError(
            "Cannot fit the latent VAR(1): the speed-turn Gaussian correlation "
            "is not finite."
        )

    # Keep only complete observations.
    complete = [
        turn
        for turn in turns
        if np.isfinite(float(turn["speed_before"]))
        and np.isfinite(float(turn["angle"]))
    ]
    if len(complete) < 4:
        raise ValueError(
            "At least four complete speed-turn observations are required to "
            "fit the latent bivariate VAR(1)."
        )

    speeds = np.asarray([float(turn["speed_before"]) for turn in complete], dtype=float)
    turn_magnitudes = np.asarray(
        [abs(float(turn["angle"])) for turn in complete],
        dtype=float,
    )

    z_speed = normal_scores(speeds)
    z_turn = normal_scores(turn_magnitudes)

    # Attach latent values to stable observation identities.
    latent_by_key: dict[tuple[int, int], np.ndarray] = {}
    explicit_by_key: dict[tuple[int, int], bool] = {}
    for turn, zv, ztheta in zip(complete, z_speed, z_turn):
        key = (int(turn["track_id"]), int(turn["turn_index"]))
        latent_by_key[key] = np.asarray([zv, ztheta], dtype=float)
        explicit_by_key[key] = bool(turn["explicit_index"])

    groups: dict[int, list[dict[str, float | int]]] = defaultdict(list)
    for turn in complete:
        groups[int(turn["track_id"])].append(turn)

    previous: list[np.ndarray] = []
    following: list[np.ndarray] = []

    for rows in groups.values():
        rows.sort(key=lambda row: int(row["turn_index"]))
        for current, nxt in zip(rows[:-1], rows[1:]):
            current_key = (int(current["track_id"]), int(current["turn_index"]))
            next_key = (int(nxt["track_id"]), int(nxt["turn_index"]))

            if explicit_by_key[current_key] and explicit_by_key[next_key]:
                if next_key[1] - current_key[1] != 1:
                    continue

            previous.append(latent_by_key[current_key])
            following.append(latent_by_key[next_key])

    if len(previous) < 3:
        raise ValueError(
            "At least three consecutive complete speed-turn pairs are required "
            "to fit the latent bivariate VAR(1)."
        )

    x = np.vstack(previous)
    y = np.vstack(following)

    # Numerical centring removes only negligible finite-sample offsets from the
    # rank-based normal scores; no intercept is retained in the simulator.
    x = x - np.mean(x, axis=0, keepdims=True)
    y = y - np.mean(y, axis=0, keepdims=True)

    rho = float(np.clip(contemporaneous_rho, -0.999999, 0.999999))
    stationary_covariance = np.asarray(
        [[1.0, rho], [rho, 1.0]],
        dtype=float,
    )

    # Multivariate Yule-Walker estimate: C_1 = A R.
    lag_one_cross_covariance = (y.T @ x) / x.shape[0]
    transition_raw = (
        lag_one_cross_covariance @ np.linalg.inv(stationary_covariance)
    )

    # The empirical estimate can be very slightly incompatible with a
    # stationary process because of finite-sample noise. Shrink A uniformly,
    # preserving all relative coefficients, until both stability and Q >= 0
    # are guaranteed.
    eigenvalues = np.linalg.eigvals(transition_raw)
    spectral_radius_raw = float(np.max(np.abs(eigenvalues)))
    upper = 1.0
    if spectral_radius_raw >= 0.999999:
        upper = min(upper, 0.999999 / spectral_radius_raw)

    valid, innovation_covariance = _stationary_covariance_valid(
        upper * transition_raw,
        stationary_covariance,
    )

    if not valid:
        low = 0.0
        high = upper
        for _ in range(100):
            middle = 0.5 * (low + high)
            middle_valid, _ = _stationary_covariance_valid(
                middle * transition_raw,
                stationary_covariance,
            )
            if middle_valid:
                low = middle
            else:
                high = middle
        upper = low
        valid, innovation_covariance = _stationary_covariance_valid(
            upper * transition_raw,
            stationary_covariance,
        )

    if not valid:
        raise RuntimeError(
            "Failed to construct a valid stationary bivariate Gaussian VAR(1), "
            "even after transparent uniform shrinkage of A."
        )

    transition = upper * transition_raw
    innovation_covariance = 0.5 * (
        innovation_covariance + innovation_covariance.T
    )

    # Clip only tiny negative eigenvalues caused by floating-point round-off.
    q_values, q_vectors = np.linalg.eigh(innovation_covariance)
    if float(np.min(q_values)) < -1e-8:
        raise RuntimeError(
            "The fitted innovation covariance is materially non-positive-semidefinite."
        )
    q_values = np.maximum(q_values, 0.0)
    innovation_covariance = (
        q_vectors @ np.diag(q_values) @ q_vectors.T
    )
    innovation_covariance = 0.5 * (
        innovation_covariance + innovation_covariance.T
    )

    spectral_radius = float(np.max(np.abs(np.linalg.eigvals(transition))))

    # Diagnostic empirical correlations in latent space.
    empirical_stationary_covariance = np.corrcoef(
        np.vstack([z_speed, z_turn])
    )
    predicted_cross_covariance = transition @ stationary_covariance

    return {
        "pair_count": int(x.shape[0]),
        "observation_count": int(len(complete)),
        "A": transition,
        "A_raw": transition_raw,
        "Q": innovation_covariance,
        "R": stationary_covariance,
        "C1_empirical": lag_one_cross_covariance,
        "C1_model": predicted_cross_covariance,
        "shrinkage_factor": float(upper),
        "spectral_radius_raw": spectral_radius_raw,
        "spectral_radius": spectral_radius,
        "latent_empirical_rho": float(empirical_stationary_covariance[0, 1]),
    }


# ---------------------------------------------------------------------------
# Threshold and input-column inference
# ---------------------------------------------------------------------------

def otsu_threshold(values: np.ndarray, bins: int = 256) -> float:
    counts, edges = np.histogram(values, bins=bins)
    centers = 0.5 * (edges[:-1] + edges[1:])
    probabilities = counts / counts.sum()
    weights = np.cumsum(probabilities)
    means = np.cumsum(probabilities * centers)
    total_mean = means[-1]

    denominator = weights * (1.0 - weights)
    score = np.zeros_like(denominator)
    valid = denominator > 0
    score[valid] = (total_mean * weights[valid] - means[valid]) ** 2 / denominator[valid]
    return float(centers[int(np.argmax(score))])


def infer_run_stop_threshold(values: np.ndarray, bins: int = 120) -> tuple[float, str]:
    low, high = np.quantile(values, [0.005, 0.995])
    clipped = values[(values >= low) & (values <= high)]
    counts, edges = np.histogram(clipped, bins=bins, range=(low, high))
    smoothed = np.convolve(counts, np.ones(7) / 7.0, mode="same")
    centers = 0.5 * (edges[:-1] + edges[1:])

    peaks = [
        index
        for index in range(1, len(smoothed) - 1)
        if smoothed[index] >= smoothed[index - 1]
        and smoothed[index] >= smoothed[index + 1]
    ]
    peaks = sorted(peaks, key=lambda index: smoothed[index], reverse=True)

    for left in peaks:
        for right in peaks:
            if right > left + max(4, bins // 12):
                valley = left + int(np.argmin(smoothed[left : right + 1]))
                return (
                    float(centers[valley]),
                    "histogram valley between two dominant speed modes",
                )

    return otsu_threshold(values), "Otsu fallback"


def infer_columns(
    step_rows: list[dict[str, str]],
    track_rows: list[dict[str, str]],
    turn_rows: list[dict[str, str]],
) -> dict[str, str | None]:
    step_columns = list(step_rows[0])
    track_columns = list(track_rows[0])
    turn_columns = list(turn_rows[0]) if turn_rows else []

    return {
        "step_track_id": first_existing(step_columns, ["track_id", "TRACK_ID"]),
        "step_index": first_existing(
            step_columns,
            ["step_index", "STEP_INDEX", "frame", "FRAME", "frame_index", "FRAME_INDEX"],
        ),
        "dt": first_existing(
            step_columns,
            ["dt_s", "delta_t_s", "time_interval_s", "frame_interval_s"],
        ),
        "speed": first_prefix(step_columns, ["speed_", "instantaneous_speed_"]),
        "step_length": first_prefix(step_columns, ["step_length_", "distance_"]),
        "heading": first_existing(
            step_columns,
            ["heading_deg", "direction_deg", "angle_deg"],
        ),
        "acceleration": first_prefix(
            step_columns,
            ["signed_acceleration_", "acceleration_"],
        ),
        "track_mean_speed": first_prefix(track_columns, ["mean_speed_"]),
        "straightness": first_existing(
            track_columns,
            ["straightness", "persistence", "net_displacement_over_path_length"],
        ),
        "tortuosity": first_existing(
            track_columns,
            ["tortuosity", "path_length_over_net_displacement"],
        ),
        "net_displacement": first_prefix(track_columns, ["net_displacement_"]),
        "path_length": first_prefix(track_columns, ["path_length_"]),
        "turn_track_id": first_existing(turn_columns, ["track_id", "TRACK_ID"]),
        "turn_index": first_existing(
            turn_columns,
            ["turn_index", "step_index", "STEP_INDEX", "frame", "FRAME", "frame_index"],
        ),
        "turn_angle": first_existing(
            turn_columns,
            ["turning_angle_deg", "signed_turning_angle_deg", "turn_angle_deg"],
        ),
        "speed_before_turn": first_prefix(
            turn_columns,
            ["speed_before_turn_", "speed_before_"],
        ),
    }


# ---------------------------------------------------------------------------
# Local records
# ---------------------------------------------------------------------------

def build_steps(
    rows: list[dict[str, str]],
    columns: dict[str, str | None],
) -> list[dict[str, float | int | str]]:
    track_column = columns["step_track_id"]
    speed_column = columns["speed"]

    if not track_column or not speed_column:
        raise ValueError("Required step columns (track ID and speed) were not found.")

    records: list[dict[str, float | int | str]] = []
    for row_number, row in enumerate(rows):
        track_id = as_float(row[track_column])
        speed = as_float(row[speed_column])
        if not (np.isfinite(track_id) and np.isfinite(speed)):
            continue

        index_column = columns["step_index"]
        index_value = as_float(row[index_column]) if index_column else math.nan

        records.append(
            {
                "track_id": int(track_id),
                "step_index": int(index_value) if np.isfinite(index_value) else row_number,
                "explicit_index": bool(index_column),
                "dt": as_float(row[columns["dt"]]) if columns["dt"] else math.nan,
                "speed": speed,
                "step_length": (
                    as_float(row[columns["step_length"]])
                    if columns["step_length"]
                    else math.nan
                ),
                "heading": (
                    as_float(row[columns["heading"]])
                    if columns["heading"]
                    else math.nan
                ),
                "acceleration": (
                    as_float(row[columns["acceleration"]])
                    if columns["acceleration"]
                    else math.nan
                ),
            }
        )

    records.sort(key=lambda record: (record["track_id"], record["step_index"]))
    return records


def infer_dt(records: list[dict[str, float | int | str]]) -> float:
    measured = finite(float(record["dt"]) for record in records)
    if measured.size:
        return float(np.median(measured))

    inferred = finite(
        float(record["step_length"]) / float(record["speed"])
        for record in records
        if np.isfinite(float(record["step_length"])) and float(record["speed"]) > 0
    )
    return float(np.median(inferred)) if inferred.size else math.nan


def group_by_track(
    records: list[dict[str, float | int | str]],
) -> dict[int, list[dict[str, float | int | str]]]:
    groups: dict[int, list[dict[str, float | int | str]]] = defaultdict(list)
    for record in records:
        groups[int(record["track_id"])].append(record)
    for rows in groups.values():
        rows.sort(key=lambda record: int(record["step_index"]))
    return groups


def adjacent(
    first: dict[str, float | int | str],
    second: dict[str, float | int | str],
) -> bool:
    """
    Require consecutive indices when an explicit frame/step index exists.
    Otherwise preserve row adjacency within each track.
    """
    if bool(first["explicit_index"]) and bool(second["explicit_index"]):
        return int(second["step_index"]) - int(first["step_index"]) == 1
    return True


def fill_accelerations(
    records: list[dict[str, float | int | str]],
    dt: float,
) -> None:
    """
    Derive acceleration exactly as specified by the model:
        a_t = (v_(t+1) - v_t) / dt.

    Any acceleration column present in the input is deliberately ignored here,
    because acceleration is not an independently sampled model variable.
    """
    if not (np.isfinite(dt) and dt > 0):
        return

    for record in records:
        record["acceleration"] = math.nan

    for rows in group_by_track(records).values():
        for current, following in zip(rows[:-1], rows[1:]):
            if not adjacent(current, following):
                continue
            current["acceleration"] = (
                float(following["speed"]) - float(current["speed"])
            ) / dt


def derive_turns_from_headings(
    records: list[dict[str, float | int | str]],
) -> list[dict[str, float | int]]:
    turns: list[dict[str, float | int]] = []

    for track_id, rows in group_by_track(records).items():
        for current, following in zip(rows[:-1], rows[1:]):
            if not adjacent(current, following):
                continue
            heading_0 = float(current["heading"])
            heading_1 = float(following["heading"])
            if not (np.isfinite(heading_0) and np.isfinite(heading_1)):
                continue

            angle = (heading_1 - heading_0 + 180.0) % 360.0 - 180.0
            turns.append(
                {
                    "track_id": track_id,
                    "turn_index": int(current["step_index"]),
                    "explicit_index": bool(current["explicit_index"]),
                    "angle": angle,
                    "speed_before": float(current["speed"]),
                }
            )

    return turns


def build_turns(
    turn_rows: list[dict[str, str]],
    columns: dict[str, str | None],
    step_records: list[dict[str, float | int | str]],
) -> list[dict[str, float | int]]:
    """
    Prefer turn_metrics.csv when it contains both angle and track identity.
    Otherwise derive turns from consecutive headings so that temporal memory can
    still be estimated without mixing independent trajectories.
    """
    angle_column = columns["turn_angle"]
    track_column = columns["turn_track_id"]

    if turn_rows and angle_column and track_column:
        turns: list[dict[str, float | int]] = []
        for row_number, row in enumerate(turn_rows):
            track_id = as_float(row[track_column])
            angle = as_float(row[angle_column])
            if not (np.isfinite(track_id) and np.isfinite(angle)):
                continue

            index_column = columns["turn_index"]
            index_value = as_float(row[index_column]) if index_column else math.nan
            speed_column = columns["speed_before_turn"]

            turns.append(
                {
                    "track_id": int(track_id),
                    "turn_index": int(index_value) if np.isfinite(index_value) else row_number,
                    "explicit_index": bool(index_column),
                    "angle": angle,
                    "speed_before": (
                        as_float(row[speed_column]) if speed_column else math.nan
                    ),
                }
            )

        turns.sort(key=lambda row: (int(row["track_id"]), int(row["turn_index"])))
        return turns

    return derive_turns_from_headings(step_records)


# ---------------------------------------------------------------------------
# Empirical model components
# ---------------------------------------------------------------------------

def transition_probabilities(
    records: list[dict[str, float | int | str]],
) -> dict[str, float]:
    counts = {
        (source, target): 0
        for source in ("RUN", "STOP")
        for target in ("RUN", "STOP")
    }

    for rows in group_by_track(records).values():
        for current, following in zip(rows[:-1], rows[1:]):
            if adjacent(current, following):
                counts[(str(current["state"]), str(following["state"]))] += 1

    probabilities: dict[str, float] = {}
    for source in ("RUN", "STOP"):
        total = counts[(source, "RUN")] + counts[(source, "STOP")]
        for target in ("RUN", "STOP"):
            probabilities[f"P_{source}_to_{target}"] = (
                counts[(source, target)] / total if total else math.nan
            )
    return probabilities


def episodes(
    records: list[dict[str, float | int | str]],
    dt: float,
) -> list[dict[str, float | str]]:
    output: list[dict[str, float | str]] = []

    for rows in group_by_track(records).values():
        current_episode: list[dict[str, float | int | str]] = []
        current_state: str | None = None

        def flush() -> None:
            nonlocal current_episode, current_state
            if not current_episode or current_state is None:
                return

            duration = sum(
                float(row["dt"]) if np.isfinite(float(row["dt"])) else dt
                for row in current_episode
            )
            lengths = finite(float(row["step_length"]) for row in current_episode)
            if lengths.size:
                distance = float(np.sum(lengths))
            else:
                distance = sum(
                    float(row["speed"])
                    * (float(row["dt"]) if np.isfinite(float(row["dt"])) else dt)
                    for row in current_episode
                )

            output.append(
                {"state": current_state, "duration": duration, "length": distance}
            )

        previous: dict[str, float | int | str] | None = None
        for row in rows:
            broken = previous is not None and not adjacent(previous, row)
            state_changed = current_state is not None and str(row["state"]) != current_state

            if broken or state_changed:
                flush()
                current_episode = []

            current_state = str(row["state"])
            current_episode.append(row)
            previous = row

        flush()

    return output


def speed_lag_pairs(
    records: list[dict[str, float | int | str]],
) -> tuple[np.ndarray, np.ndarray]:
    previous_values: list[float] = []
    following_values: list[float] = []

    for rows in group_by_track(records).values():
        for current, following in zip(rows[:-1], rows[1:]):
            if adjacent(current, following):
                previous_values.append(float(current["speed"]))
                following_values.append(float(following["speed"]))

    return np.asarray(previous_values), np.asarray(following_values)


def turn_lag_pairs(
    turns: list[dict[str, float | int]],
) -> tuple[np.ndarray, np.ndarray]:
    groups: dict[int, list[dict[str, float | int]]] = defaultdict(list)
    for turn in turns:
        groups[int(turn["track_id"])].append(turn)

    previous_values: list[float] = []
    following_values: list[float] = []

    for rows in groups.values():
        rows.sort(key=lambda row: int(row["turn_index"]))
        for current, following in zip(rows[:-1], rows[1:]):
            if bool(current["explicit_index"]) and bool(following["explicit_index"]):
                if int(following["turn_index"]) - int(current["turn_index"]) != 1:
                    continue
            previous_values.append(abs(float(current["angle"])))
            following_values.append(abs(float(following["angle"])))

    return np.asarray(previous_values), np.asarray(following_values)


def autocorrelation_speed(
    records: list[dict[str, float | int | str]],
    max_lag: int,
) -> list[tuple[int, float]]:
    groups = group_by_track(records)
    output: list[tuple[int, float]] = []

    for lag in range(1, max_lag + 1):
        x: list[float] = []
        y: list[float] = []

        for rows in groups.values():
            if len(rows) <= lag:
                continue
            for start in range(len(rows) - lag):
                end = start + lag
                valid_chain = all(adjacent(rows[k], rows[k + 1]) for k in range(start, end))
                if valid_chain:
                    x.append(float(rows[start]["speed"]))
                    y.append(float(rows[end]["speed"]))

        output.append((lag, pearson(np.asarray(x), np.asarray(y))))

    return output


def autocorrelation_direction(
    records: list[dict[str, float | int | str]],
    max_lag: int,
) -> list[tuple[int, float]]:
    groups = group_by_track(records)
    output: list[tuple[int, float]] = []

    for lag in range(1, max_lag + 1):
        cosine_differences: list[float] = []

        for rows in groups.values():
            if len(rows) <= lag:
                continue
            for start in range(len(rows) - lag):
                end = start + lag
                valid_chain = all(adjacent(rows[k], rows[k + 1]) for k in range(start, end))
                if not valid_chain:
                    continue

                heading_0 = float(rows[start]["heading"])
                heading_1 = float(rows[end]["heading"])
                if np.isfinite(heading_0) and np.isfinite(heading_1):
                    cosine_differences.append(
                        math.cos(math.radians(heading_1 - heading_0))
                    )

        values = finite(cosine_differences)
        output.append(
            (lag, float(np.mean(values)) if values.size else math.nan)
        )

    return output


def first_below(
    series: list[tuple[int, float]],
    threshold: float,
    dt: float,
) -> float:
    for lag, value in series:
        if np.isfinite(value) and value <= threshold:
            return lag * dt
    return math.nan


def heading_resultant_length(
    records: list[dict[str, float | int | str]],
) -> float:
    angles = np.radians(finite(float(record["heading"]) for record in records))
    if not angles.size:
        return math.nan
    return float(
        np.hypot(np.mean(np.cos(angles)), np.mean(np.sin(angles)))
    )


def empirical_quantile_rows(
    name: str,
    condition: str,
    values: np.ndarray,
    unit: str,
    grid_size: int,
) -> list[dict[str, object]]:
    """
    Export a numerical inverse empirical CDF. Linear interpolation between rows
    gives the continuous quantile transformation used by the simulator.
    """
    values = finite(values)
    if values.size == 0:
        return []

    probabilities = np.linspace(0.0, 1.0, grid_size)
    quantiles = np.quantile(values, probabilities)

    return [
        {
            "distribution": name,
            "condition": condition,
            "quantile": float(probability),
            "value": float(value),
            "unit": unit,
            "n_observations": int(values.size),
        }
        for probability, value in zip(probabilities, quantiles)
    ]


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def write_scalar_csv(path: Path, rows: list[dict[str, object]]) -> None:
    fields = ["section", "parameter", "value", "unit", "rationale"]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def write_quantile_csv(path: Path, rows: list[dict[str, object]]) -> None:
    fields = [
        "distribution",
        "condition",
        "quantile",
        "value",
        "unit",
        "n_observations",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract empirical local parameters for the zoospore ABCA plugin."
    )
    parser.add_argument("metrics_dir", type=Path)
    parser.add_argument("-o", "--outdir", type=Path)
    parser.add_argument("--threshold", type=float)
    parser.add_argument("--max-lag-steps", type=int, default=25)
    parser.add_argument(
        "--quantile-grid-size",
        type=int,
        default=1001,
        help="Number of points used to export each empirical quantile function.",
    )
    parser.add_argument(
        "--accel-cap-multiplier",
        type=float,
        default=3.0,
        help="Configurable multiplier m_a applied to q90(|a|).",
    )
    parser.add_argument(
        "--microns-per-cell",
        type=float,
        default=10.0,
        help="Environmental grid scale exported for the plugin.",
    )
    args = parser.parse_args()

    if args.quantile_grid_size < 2:
        parser.error("--quantile-grid-size must be at least 2")
    if args.accel_cap_multiplier <= 0:
        parser.error("--accel-cap-multiplier must be positive")
    if args.microns_per_cell <= 0:
        parser.error("--microns-per-cell must be positive")

    output_dir = args.outdir or args.metrics_dir / "abca_rationale"
    output_dir.mkdir(parents=True, exist_ok=True)

    step_rows = read_csv(args.metrics_dir / "step_metrics.csv")
    track_rows = read_csv(args.metrics_dir / "track_metrics.csv")
    turn_rows = read_csv(args.metrics_dir / "turn_metrics.csv")

    if not step_rows or not track_rows:
        raise FileNotFoundError(
            "step_metrics.csv and track_metrics.csv are required."
        )

    columns = infer_columns(step_rows, track_rows, turn_rows)
    records = build_steps(step_rows, columns)
    dt = infer_dt(records)

    if not (np.isfinite(dt) and dt > 0):
        raise ValueError("A positive time interval could not be inferred.")

    fill_accelerations(records, dt)

    speeds = finite(float(record["speed"]) for record in records)
    if speeds.size == 0:
        raise ValueError("No finite speed was found.")

    if args.threshold is None:
        threshold, threshold_method = infer_run_stop_threshold(speeds)
    else:
        threshold = args.threshold
        threshold_method = "user-specified"

    for record in records:
        record["state"] = "RUN" if float(record["speed"]) >= threshold else "STOP"

    transitions = transition_probabilities(records)
    episode_rows = episodes(records, dt)
    turns = build_turns(turn_rows, columns, records)

    run_speeds = finite(
        float(record["speed"]) for record in records if record["state"] == "RUN"
    )
    stop_speeds = finite(
        float(record["speed"]) for record in records if record["state"] == "STOP"
    )
    accelerations = finite(float(record["acceleration"]) for record in records)
    absolute_accelerations = np.abs(accelerations)

    signed_turns = finite(float(turn["angle"]) for turn in turns)
    absolute_turns = np.abs(signed_turns)
    turn_speeds = np.asarray(
        [float(turn["speed_before"]) for turn in turns],
        dtype=float,
    )
    turn_magnitudes_for_pairs = np.asarray(
        [abs(float(turn["angle"])) for turn in turns],
        dtype=float,
    )

    run_durations = finite(
        float(row["duration"]) for row in episode_rows if row["state"] == "RUN"
    )
    stop_durations = finite(
        float(row["duration"]) for row in episode_rows if row["state"] == "STOP"
    )
    run_lengths = finite(
        float(row["length"]) for row in episode_rows if row["state"] == "RUN"
    )
    stop_lengths = finite(
        float(row["length"]) for row in episode_rows if row["state"] == "STOP"
    )

    speed_previous, speed_following = speed_lag_pairs(records)
    speed_rho_s, speed_pair_n = spearman(speed_previous, speed_following)
    speed_rho_gaussian = gaussian_copula_rho(speed_rho_s)

    turn_previous, turn_following = turn_lag_pairs(turns)
    turn_rho_s, turn_pair_n = spearman(turn_previous, turn_following)
    turn_rho_gaussian = gaussian_copula_rho(turn_rho_s)

    speed_turn_rho_s, speed_turn_pair_n = spearman(
        turn_speeds,
        turn_magnitudes_for_pairs,
    )
    speed_turn_rho_gaussian = gaussian_copula_rho(speed_turn_rho_s)

    # Fit the complete latent process described in the model:
    #     Z_(t+1) = A Z_t + epsilon_t, epsilon_t ~ N(0, Q),
    # for Z_t = (Z_speed,t, Z_|turn|,t)^T.
    latent_var1 = fit_stationary_bivariate_var1(
        turns,
        speed_turn_rho_gaussian,
    )

    speed_array = np.asarray([float(record["speed"]) for record in records])
    acceleration_array = np.asarray(
        [float(record["acceleration"]) for record in records]
    )
    speed_acceleration_rho_s, speed_acceleration_n = spearman(
        speed_array,
        acceleration_array,
    )

    speed_autocorrelation = autocorrelation_speed(records, args.max_lag_steps)
    direction_autocorrelation = autocorrelation_direction(
        records,
        args.max_lag_steps,
    )

    straightness = (
        finite(as_float(row[columns["straightness"]]) for row in track_rows)
        if columns["straightness"]
        else np.array([])
    )
    tortuosity = (
        finite(as_float(row[columns["tortuosity"]]) for row in track_rows)
        if columns["tortuosity"]
        else np.array([])
    )
    net_displacement = (
        finite(as_float(row[columns["net_displacement"]]) for row in track_rows)
        if columns["net_displacement"]
        else np.array([])
    )
    path_length = (
        finite(as_float(row[columns["path_length"]]) for row in track_rows)
        if columns["path_length"]
        else np.array([])
    )

    scalar_rows: list[dict[str, object]] = []

    def add(
        section: str,
        parameter: str,
        value: object,
        unit: str,
        rationale: str,
    ) -> None:
        scalar_rows.append(
            {
                "section": section,
                "parameter": parameter,
                "value": value,
                "unit": unit,
                "rationale": rationale,
            }
        )

    # Simulation scale and spatial assumptions.
    add(
        "0_simulation_scale",
        "time_step",
        dt,
        "s",
        "Natural local update interval inferred from the acquisition.",
    )
    add(
        "0_simulation_scale",
        "continuous_position",
        "true",
        "boolean",
        "Agents move in continuous coordinates; the lattice is used for display and local interactions.",
    )
    add(
        "0_simulation_scale",
        "microns_per_cell",
        args.microns_per_cell,
        "micron/cell",
        "Configurable conversion between physical distance and lattice units.",
    )
    add(
        "0_simulation_scale",
        "initialization_scheme",
        "stratified_midpoint_quantiles",
        "categorical",
        "For N agents, use u_i=(i+1/2)/N and randomly permute assignments.",
    )
    add(
        "0_simulation_scale",
        "initial_heading_distribution",
        "uniform_0_2pi",
        "categorical",
        "Initial headings are stratified over [0,2pi) and randomly permuted.",
    )

    # RUN/STOP Markov chain.
    add(
        "1_motion_states",
        "run_stop_speed_threshold",
        threshold,
        "micron/s",
        threshold_method,
    )
    add(
        "1_motion_states",
        "initial_run_fraction",
        run_speeds.size / speeds.size,
        "fraction",
        "Observed occupancy used to initialize the population.",
    )
    add(
        "1_motion_states",
        "initial_stop_fraction",
        stop_speeds.size / speeds.size,
        "fraction",
        "Observed occupancy used to initialize the population.",
    )
    for name in (
        "P_STOP_to_STOP",
        "P_STOP_to_RUN",
        "P_RUN_to_STOP",
        "P_RUN_to_RUN",
    ):
        add(
            "1_motion_states",
            name,
            transitions[name],
            "probability/update",
            "Empirical local transition probability.",
        )

    # Descriptive episode statistics; not separate update rules.
    for state, durations, lengths in (
        ("run", run_durations, run_lengths),
        ("stop", stop_durations, stop_lengths),
    ):
        duration_summary = summary(durations)
        length_summary = summary(lengths)
        for statistic in ("median", "q25", "q75", "q90"):
            add(
                "2_episode_statistics",
                f"{state}_duration_{statistic}",
                duration_summary[statistic],
                "s",
                "Observed contiguous-state duration; descriptive consequence of the Markov chain.",
            )
            add(
                "2_episode_statistics",
                f"{state}_length_{statistic}",
                length_summary[statistic],
                "micron",
                "Observed distance covered within a contiguous state episode.",
            )

    # ------------------------------------------------------------------
    # Latent bivariate Gaussian VAR(1)
    # ------------------------------------------------------------------
    #
    # These are the parameters that the OCaml plugin must use directly:
    #
    #     Z_(t+1) = A Z_t + epsilon_t,
    #     epsilon_t ~ N(0, Q),
    #
    # with stationary covariance R. Unlike two independent AR(1) equations,
    # this vector process can preserve speed memory, turn memory and their
    # contemporaneous coupling simultaneously.
    matrix_a = np.asarray(latent_var1["A"], dtype=float)
    matrix_q = np.asarray(latent_var1["Q"], dtype=float)
    matrix_r = np.asarray(latent_var1["R"], dtype=float)
    matrix_c1_empirical = np.asarray(latent_var1["C1_empirical"], dtype=float)
    matrix_c1_model = np.asarray(latent_var1["C1_model"], dtype=float)

    for row_index in range(2):
        for column_index in range(2):
            add(
                "3_latent_bivariate_var1",
                f"latent_var_a{row_index + 1}{column_index + 1}",
                float(matrix_a[row_index, column_index]),
                "coefficient",
                "Entry of A in Z_(t+1)=A Z_t+epsilon_t; use directly in the plugin.",
            )

    add(
        "3_latent_bivariate_var1",
        "latent_var_q11",
        float(matrix_q[0, 0]),
        "variance",
        "Innovation variance for latent speed.",
    )
    add(
        "3_latent_bivariate_var1",
        "latent_var_q12",
        float(matrix_q[0, 1]),
        "covariance",
        "Innovation covariance coupling latent speed and latent turn magnitude.",
    )
    add(
        "3_latent_bivariate_var1",
        "latent_var_q22",
        float(matrix_q[1, 1]),
        "variance",
        "Innovation variance for latent turn magnitude.",
    )

    add(
        "3_latent_bivariate_var1",
        "latent_var_r11",
        float(matrix_r[0, 0]),
        "variance",
        "Stationary latent-speed variance; fixed to one.",
    )
    add(
        "3_latent_bivariate_var1",
        "latent_var_r12",
        float(matrix_r[0, 1]),
        "correlation",
        "Stationary Gaussian-copula correlation between speed and |turn|.",
    )
    add(
        "3_latent_bivariate_var1",
        "latent_var_r22",
        float(matrix_r[1, 1]),
        "variance",
        "Stationary latent-turn variance; fixed to one.",
    )

    add(
        "3_latent_bivariate_var1",
        "latent_var_pair_count",
        int(latent_var1["pair_count"]),
        "pairs",
        "Number of complete consecutive (speed, |turn|) vector pairs.",
    )
    add(
        "3_latent_bivariate_var1",
        "latent_var_observation_count",
        int(latent_var1["observation_count"]),
        "observations",
        "Number of complete contemporaneous speed-turn observations.",
    )
    add(
        "3_latent_bivariate_var1",
        "latent_var_shrinkage_factor",
        float(latent_var1["shrinkage_factor"]),
        "multiplier",
        "Uniform factor applied to raw A only when required for stationarity and Q >= 0.",
    )
    add(
        "3_latent_bivariate_var1",
        "latent_var_spectral_radius",
        float(latent_var1["spectral_radius"]),
        "0_to_1",
        "Spectral radius of A; must remain below one.",
    )
    add(
        "3_latent_bivariate_var1",
        "latent_var_spectral_radius_raw",
        float(latent_var1["spectral_radius_raw"]),
        "ratio",
        "Spectral radius before any transparent stationarity shrinkage.",
    )

    # Diagnostics retained for biological interpretation and documentation.
    add(
        "4_copula_diagnostics",
        "speed_lag1_spearman_rho",
        speed_rho_s,
        "rho_S",
        "Rank correlation between v_t and v_(t+1); diagnostic, not an independent AR coefficient.",
    )
    add(
        "4_copula_diagnostics",
        "speed_lag1_gaussian_copula_rho",
        speed_rho_gaussian,
        "rho_G",
        "Bivariate lag-one Gaussian-copula diagnostic for speed.",
    )
    add(
        "4_copula_diagnostics",
        "speed_lag1_pair_count",
        speed_pair_n,
        "pairs",
        "Number of valid within-track consecutive speed pairs.",
    )
    add(
        "4_copula_diagnostics",
        "turn_lag1_spearman_rho",
        turn_rho_s,
        "rho_S",
        "Rank correlation between successive absolute turning angles.",
    )
    add(
        "4_copula_diagnostics",
        "turn_lag1_gaussian_copula_rho",
        turn_rho_gaussian,
        "rho_G",
        "Bivariate lag-one Gaussian-copula diagnostic for |turn|.",
    )
    add(
        "4_copula_diagnostics",
        "turn_lag1_pair_count",
        turn_pair_n,
        "pairs",
        "Number of valid within-track consecutive turn-magnitude pairs.",
    )
    add(
        "4_copula_diagnostics",
        "speed_vs_abs_turn_spearman_rho",
        speed_turn_rho_s,
        "rho_S",
        "Contemporaneous rank correlation between speed and turning magnitude.",
    )
    add(
        "4_copula_diagnostics",
        "speed_vs_abs_turn_gaussian_copula_rho",
        speed_turn_rho_gaussian,
        "rho_G",
        "Off-diagonal entry R_12 of the stationary latent covariance.",
    )
    add(
        "4_copula_diagnostics",
        "speed_vs_abs_turn_pair_count",
        speed_turn_pair_n,
        "pairs",
        "Number of valid contemporaneous speed-turn pairs.",
    )
    add(
        "4_copula_diagnostics",
        "latent_empirical_speed_turn_rho",
        float(latent_var1["latent_empirical_rho"]),
        "correlation",
        "Empirical Pearson correlation after rank-to-Gaussian transformation.",
    )
    add(
        "4_copula_diagnostics",
        "speed_memory_1_over_e_time",
        first_below(speed_autocorrelation, 1.0 / math.e, dt),
        "s",
        "Descriptive speed-memory timescale.",
    )
    add(
        "4_copula_diagnostics",
        "direction_memory_1_over_e_time",
        first_below(direction_autocorrelation, 1.0 / math.e, dt),
        "s",
        "Descriptive directional-persistence timescale.",
    )
    add(
        "4_copula_diagnostics",
        "heading_resultant_length_R",
        heading_resultant_length(records),
        "0_to_1",
        "Near zero supports uniformly distributed initial headings.",
    )
    add(
        "4_copula_diagnostics",
        "positive_turn_probability",
        float(np.mean(signed_turns > 0)) if signed_turns.size else math.nan,
        "probability",
        "Empirical sign balance used after sampling turning magnitude.",
    )
    add(
        "4_copula_diagnostics",
        "negative_turn_probability",
        float(np.mean(signed_turns < 0)) if signed_turns.size else math.nan,
        "probability",
        "Empirical sign balance used after sampling turning magnitude.",
    )

    # Acceleration is derived, not sampled.
    acceleration_summary = summary(accelerations)
    absolute_acceleration_summary = summary(absolute_accelerations)
    add(
        "6_acceleration_guard",
        "absolute_acceleration_q90",
        absolute_acceleration_summary["q90"],
        "micron/s2",
        "Empirical q90(|a|) used only as a numerical guard.",
    )
    add(
        "6_acceleration_guard",
        "accel_cap_multiplier",
        args.accel_cap_multiplier,
        "multiplier",
        "Configurable plugin argument ACCEL_CAP_MULTIPLIER.",
    )
    add(
        "6_acceleration_guard",
        "absolute_acceleration_cap",
        args.accel_cap_multiplier * float(absolute_acceleration_summary["q90"]),
        "micron/s2",
        "Numerical cap m_a*q90(|a|); not a biological distribution.",
    )
    add(
        "6_acceleration_guard",
        "speed_vs_acceleration_spearman_rho",
        speed_acceleration_rho_s,
        "rho_S",
        "Diagnostic dependence only; acceleration is derived from successive speeds.",
    )
    add(
        "6_acceleration_guard",
        "speed_vs_acceleration_pair_count",
        speed_acceleration_n,
        "pairs",
        "Number of valid speed-acceleration pairs.",
    )

    # Selected summaries retained for readability.
    for label, values, unit in (
        ("all_speed", speeds, "micron/s"),
        ("run_speed", run_speeds, "micron/s"),
        ("stop_speed", stop_speeds, "micron/s"),
        ("signed_turn_angle", signed_turns, "degree"),
        ("absolute_turn_angle", absolute_turns, "degree"),
        ("signed_acceleration", accelerations, "micron/s2"),
    ):
        values_summary = summary(values)
        for statistic in ("median", "q10", "q25", "q75", "q90"):
            add(
                "7_distribution_summaries",
                f"{label}_{statistic}",
                values_summary[statistic],
                unit,
                "Human-readable summary; simulation uses the full exported empirical quantile function.",
            )

    # Global quantities are validation targets only.
    for label, values, unit in (
        ("straightness", straightness, "0_to_1"),
        ("tortuosity", tortuosity, "ratio"),
        ("net_displacement", net_displacement, "micron"),
        ("path_length", path_length, "micron"),
    ):
        if values.size:
            values_summary = summary(values)
            for statistic in ("median", "q25", "q75"):
                add(
                    "8_validation_targets",
                    f"{label}_{statistic}",
                    values_summary[statistic],
                    unit,
                    "Emergent validation target; never imposed as a local rule.",
                )

    quantile_rows: list[dict[str, object]] = []
    for name, condition, values, unit in (
        ("speed", "RUN", run_speeds, "micron/s"),
        ("speed", "STOP", stop_speeds, "micron/s"),
        ("turn_angle_signed", "ALL", signed_turns, "degree"),
        ("turn_angle_absolute", "ALL", absolute_turns, "degree"),
    ):
        quantile_rows.extend(
            empirical_quantile_rows(
                name,
                condition,
                values,
                unit,
                args.quantile_grid_size,
            )
        )

    write_scalar_csv(output_dir / "abca_local_parameters.csv", scalar_rows)
    write_quantile_csv(output_dir / "abca_empirical_quantiles.csv", quantile_rows)

    payload = {
        "source_directory": str(args.metrics_dir),
        "threshold_method": threshold_method,
        "model_specification": {
            "state_model": "two_state_empirical_markov_chain",
            "marginals": "empirical_quantile_functions",
            "latent_dynamics": "stationary_bivariate_gaussian_VAR1",
            "latent_state": ["speed", "absolute_turn_angle"],
            "stationary_covariance": "R=[[1,rho_speed_turn],[rho_speed_turn,1]]",
            "acceleration": "derived_then_optionally_capped",
            "position": "continuous_with_lattice_projection",
        },
        "latent_var1": {
            "A": matrix_a.tolist(),
            "Q": matrix_q.tolist(),
            "R": matrix_r.tolist(),
            "C1_empirical": matrix_c1_empirical.tolist(),
            "C1_model": matrix_c1_model.tolist(),
            "pair_count": int(latent_var1["pair_count"]),
            "observation_count": int(latent_var1["observation_count"]),
            "shrinkage_factor": float(latent_var1["shrinkage_factor"]),
            "spectral_radius": float(latent_var1["spectral_radius"]),
        },
        "parameters": scalar_rows,
        "empirical_quantiles": quantile_rows,
    }
    (output_dir / "abca_local_parameters.json").write_text(
        json.dumps(payload, indent=2, allow_nan=True),
        encoding="utf-8",
    )

    rationale_lines = [
        "EMPIRICAL PARAMETERS FOR THE ZOOSPORE ABCA",
        "=" * 48,
        "",
        f"Source: {args.metrics_dir}",
        f"Tracks: {len(track_rows)}",
        f"Local steps: {len(records)}",
        f"Natural update interval: {format_number(dt)} s",
        "",
        "RUN/STOP MARKOV CHAIN",
        "---------------------",
        f"Threshold: {format_number(threshold)} micron/s ({threshold_method})",
        f"P(STOP->STOP)={format_number(transitions['P_STOP_to_STOP'])}",
        f"P(STOP->RUN)={format_number(transitions['P_STOP_to_RUN'])}",
        f"P(RUN->STOP)={format_number(transitions['P_RUN_to_STOP'])}",
        f"P(RUN->RUN)={format_number(transitions['P_RUN_to_RUN'])}",
        "",
        "EMPIRICAL MARGINALS",
        "-------------------",
        "Full inverse empirical CDFs are written to abca_empirical_quantiles.csv.",
        f"RUN speed observations: {run_speeds.size}",
        f"STOP speed observations: {stop_speeds.size}",
        f"Turning-angle observations: {signed_turns.size}",
        "",
        "STATIONARY BIVARIATE GAUSSIAN VAR(1)",
        "--------------------------------------",
        (
            "A = [["
            f"{format_number(float(matrix_a[0, 0]))}, "
            f"{format_number(float(matrix_a[0, 1]))}], ["
            f"{format_number(float(matrix_a[1, 0]))}, "
            f"{format_number(float(matrix_a[1, 1]))}]]"
        ),
        (
            "Q = [["
            f"{format_number(float(matrix_q[0, 0]))}, "
            f"{format_number(float(matrix_q[0, 1]))}], ["
            f"{format_number(float(matrix_q[1, 0]))}, "
            f"{format_number(float(matrix_q[1, 1]))}]]"
        ),
        (
            "R = [["
            f"{format_number(float(matrix_r[0, 0]))}, "
            f"{format_number(float(matrix_r[0, 1]))}], ["
            f"{format_number(float(matrix_r[1, 0]))}, "
            f"{format_number(float(matrix_r[1, 1]))}]]"
        ),
        (
            f"Valid consecutive vector pairs: {int(latent_var1['pair_count'])}; "
            f"spectral radius={format_number(float(latent_var1['spectral_radius']))}; "
            f"A shrinkage={format_number(float(latent_var1['shrinkage_factor']))}"
        ),
        (
            "Diagnostics: "
            f"speed lag-1 rho_S={format_number(speed_rho_s)}; "
            f"|turn| lag-1 rho_S={format_number(turn_rho_s)}; "
            f"speed-|turn| rho_S={format_number(speed_turn_rho_s)}"
        ),
        "",
        "ACCELERATION",
        "------------",
        "Acceleration is derived as (v[t+1]-v[t])/dt; it is not sampled independently.",
        (
            f"q90(|a|)={format_number(float(absolute_acceleration_summary['q90']))} "
            "micron/s2"
        ),
        (
            f"Default cap={format_number(args.accel_cap_multiplier)} * q90(|a|) = "
            f"{format_number(args.accel_cap_multiplier * float(absolute_acceleration_summary['q90']))} "
            "micron/s2"
        ),
        "",
        "SPATIAL SCALE",
        "-------------",
        f"MICRONS_PER_CELL={format_number(args.microns_per_cell)}",
        "Positions remain continuous; lattice coordinates are a projection.",
        "",
        "IMPORTANT",
        "---------",
        "Global track metrics are validation targets only and are never imposed as local rules.",
    ]
    (output_dir / "abca_parameter_rationale.txt").write_text(
        "\n".join(rationale_lines) + "\n",
        encoding="utf-8",
    )

    print(f"Wrote outputs to {output_dir}")


if __name__ == "__main__":
    main()
