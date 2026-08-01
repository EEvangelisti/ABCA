#!/usr/bin/env python3
"""Extract trajectory metrics from supported XML tracking files.

The command-line interface and all numerical calculations are preserved
from the original analysis script.
"""

from __future__ import annotations
import argparse
import csv
import math
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
import numpy as np


@dataclass
class Track:
    track_id: int
    source_xml: str
    frames: np.ndarray
    xy: np.ndarray

    @property
    def n_spots(self):
        return int(self.xy.shape[0])


def lname(tag):
    return tag.rsplit('}', 1)[-1]


def write_csv(path, rows, fields=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = fields or (list(rows[0].keys()) if rows else [])
    with path.open('w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction='ignore')
        w.writeheader()
        w.writerows(rows)


def wrap(a):
    return (np.asarray(a) + 180) % 360 - 180


def sdiv(a, b):
    return float(a / b) if b and np.isfinite(b) else math.nan


def read_simple(path, scale, min_spots):
    root = ET.parse(path).getroot()
    out = []
    for p in [e for e in root.iter() if lname(e.tag) == 'particle']:
        ds = [e for e in p if lname(e.tag) == 'detection']
        ds.sort(key=lambda d: int(float(d.attrib['t'])))
        if len(ds) <= min_spots:
            continue
        fr = np.array([int(float(d.attrib['t'])) for d in ds])
        xy = np.array(
            [
                [
                    float(d.attrib['x']) * scale,
                    float(d.attrib['y']) * scale,
                ]
                for d in ds
            ]
        )
        keep = np.ones(fr.size, dtype=bool)
        keep[1:] = fr[1:] != fr[:-1]
        fr, xy = (fr[keep], xy[keep])
        if len(fr) > min_spots:
            out.append((fr, xy))
    return out


def read_trackmate(path, scale, min_spots):
    root = ET.parse(path).getroot()
    spots = {}
    for e in root.iter():
        if lname(e.tag) == 'Spot' and 'ID' in e.attrib:
            a = e.attrib
            sid = int(float(a['ID']))
            fr = int(float(a.get('FRAME', a.get('POSITION_T', 0))))
            spots[sid] = (
                fr,
                float(a['POSITION_X']) * scale,
                float(a['POSITION_Y']) * scale,
            )
    visible = {
        int(float(e.attrib['TRACK_ID']))
        for e in root.iter()
        if lname(e.tag) == 'TrackID' and 'TRACK_ID' in e.attrib
    }
    out = []
    for e in root.iter():
        if lname(e.tag) != 'Track' or 'TRACK_ID' not in e.attrib:
            continue
        tid = int(float(e.attrib['TRACK_ID']))
        if visible and tid not in visible:
            continue
        ids = set()
        for ed in e:
            if lname(ed.tag) == 'Edge':
                ids.add(int(float(ed.attrib['SPOT_SOURCE_ID'])))
                ids.add(int(float(ed.attrib['SPOT_TARGET_ID'])))
        pts = sorted((spots[i] for i in ids if i in spots), key=lambda p: p[0])
        if len(pts) <= min_spots:
            continue
        fr = np.array([p[0] for p in pts])
        xy = np.array([[p[1], p[2]] for p in pts])
        keep = np.ones(fr.size, dtype=bool)
        keep[1:] = fr[1:] != fr[:-1]
        fr, xy = (fr[keep], xy[keep])
        if len(fr) > min_spots:
            out.append((fr, xy))
    return out


def read_xml(path, scale, min_spots):
    root = ET.parse(path).getroot()
    if any((lname(e.tag) == 'particle' for e in root.iter())):
        return read_simple(path, scale, min_spots)
    if any((lname(e.tag) == 'Track' and 'TRACK_ID' in e.attrib for e in root.iter())):
        return read_trackmate(path, scale, min_spots)
    raise ValueError(f'Unsupported XML structure: {path}')


def compute(tracks, dt, unit, turn_thr, max_lag):
    tr, st, tu = ([], [], [])
    heads = {}
    sk = f'speed_{unit}_per_s'
    dk = f'distance_{unit}'
    pk = f'path_length_{unit}'
    nk = f'net_displacement_{unit}'
    for t in tracks:
        fr, xy = (t.frames, t.xy)
        dxy = xy[1:] - xy[:-1]
        dfr = np.diff(fr) * dt
        dist = np.linalg.norm(dxy, axis=1)
        # Account for possible gaps in frame numbering when computing speed.
        sp = np.divide(
            dist,
            dfr,
            out=np.full_like(dist, np.nan, dtype=float),
            where=dfr > 0,
        )
        hd = np.degrees(np.arctan2(dxy[:, 1], dxy[:, 0]))
        heads[t.track_id] = hd
        for i in range(len(dist)):
            st.append(
                {
                    'track_id': t.track_id,
                    'source_xml': t.source_xml,
                    'step_index': i + 1,
                    'frame_start': int(fr[i]),
                    'frame_end': int(fr[i + 1]),
                    'dt_s': float(dfr[i]),
                    f'x_start_{unit}': float(xy[i, 0]),
                    f'y_start_{unit}': float(xy[i, 1]),
                    f'x_end_{unit}': float(xy[i + 1, 0]),
                    f'y_end_{unit}': float(xy[i + 1, 1]),
                    f'dx_{unit}': float(dxy[i, 0]),
                    f'dy_{unit}': float(dxy[i, 1]),
                    dk: float(dist[i]),
                    sk: float(sp[i]),
                    'heading_deg': float(hd[i]),
                }
            )
        nturn = 0
        for i in range(len(dist) - 1):
            ang = float(wrap(hd[i + 1] - hd[i]))
            aa = abs(ang)
            nturn += int(aa >= turn_thr)
            ds = float(sp[i + 1] - sp[i])
            mdt = float((dfr[i] + dfr[i + 1]) / 2)
            acc = ds / mdt if mdt > 0 else math.nan
            tu.append(
                {
                    'track_id': t.track_id,
                    'source_xml': t.source_xml,
                    'turn_index': i + 1,
                    'frame': int(fr[i + 1]),
                    'heading_before_deg': float(hd[i]),
                    'heading_after_deg': float(hd[i + 1]),
                    'turn_angle_deg': ang,
                    'abs_turn_angle_deg': aa,
                    f'speed_before_{unit}_per_s': float(sp[i]),
                    f'speed_after_{unit}_per_s': float(sp[i + 1]),
                    f'delta_speed_{unit}_per_s': ds,
                    f'acceleration_{unit}_per_s2': acc,
                    f'absolute_acceleration_{unit}_per_s2': abs(acc),
                    'is_direction_change': int(aa >= turn_thr),
                }
            )
        # Summarise each complete trajectory after step- and turn-level metrics.
        path = float(dist.sum())
        net = float(np.linalg.norm(xy[-1] - xy[0]))
        dur = float((fr[-1] - fr[0]) * dt)
        tr.append(
            {
                'track_id': t.track_id,
                'source_xml': t.source_xml,
                'n_spots': t.n_spots,
                'n_steps': len(dist),
                'duration_s': dur,
                pk: path,
                nk: net,
                'straightness': sdiv(net, path),
                'tortuosity': sdiv(path, net),
                f'mean_speed_{unit}_per_s': float(np.nanmean(sp)),
                f'median_speed_{unit}_per_s': float(np.nanmedian(sp)),
                f'max_speed_{unit}_per_s': float(np.nanmax(sp)),
                'direction_change_count': nturn,
                'direction_change_frequency_per_s': sdiv(nturn, dur),
            }
        )
    # Pool squared displacements across all trajectories for each lag.
    msd = []
    for lag in range(1, max_lag + 1):
        vals = []
        for t in tracks:
            if t.n_spots > lag:
                vals.extend(np.sum((t.xy[lag:] - t.xy[:-lag]) ** 2, axis=1).tolist())
        v = np.asarray(vals, float)
        v = v[np.isfinite(v)]
        if v.size:
            msd.append(
                {
                    'lag_frames': lag,
                    'lag_s': lag * dt,
                    f'msd_{unit}2': float(v.mean()),
                    f'median_squared_displacement_{unit}2': float(
                        np.median(v)
                    ),
                    'n_pairs': int(v.size),
                }
            )
    # Circular directional autocorrelation based on heading differences.
    dac = []
    for lag in range(1, max_lag + 1):
        vals = []
        for h in heads.values():
            if h.size > lag:
                vals.extend(np.cos(np.radians(h[lag:]) - np.radians(h[:-lag])).tolist())
        v = np.asarray(vals, float)
        v = v[np.isfinite(v)]
        if v.size:
            dac.append(
                {
                    'lag_steps': lag,
                    'lag_s': lag * dt,
                    'direction_autocorrelation': float(v.mean()),
                    'n_pairs': int(v.size),
                }
            )
    return (tr, st, tu, msd, dac)


def source_summary(tracks):
    by_source = {}
    for track in tracks:
        by_source.setdefault(track.source_xml, []).append(track)
    rows = []
    for source_xml in sorted(by_source):
        source_tracks = by_source[source_xml]
        ids = [track.track_id for track in source_tracks]
        rows.append(
            {
                'source_xml': source_xml,
                'n_tracks_retained': len(source_tracks),
                'first_global_track_id': min(ids),
                'last_global_track_id': max(ids),
                'n_spots_retained': sum(
                    track.n_spots for track in source_tracks
                ),
            }
        )
    return rows


def write_metric_set(
    outdir,
    tracks,
    dt,
    unit,
    turn_thr,
    max_lag,
    n_xml_files,
    dataset_name,
    filter_method='none',
    filter_threshold_points=None,
):
    """
    Compute and write one complete, internally consistent metric dataset.

    MSD and direction autocorrelation are recomputed from the selected tracks;
    they are not copied from the complete dataset.
    """
    tr, st, tu, msd, dac = compute(tracks, dt, unit, turn_thr, max_lag)
    write_csv(outdir / 'track_metrics.csv', tr)
    write_csv(outdir / 'step_metrics.csv', st)
    write_csv(outdir / 'turn_metrics.csv', tu)
    write_csv(outdir / 'msd.csv', msd)
    write_csv(outdir / 'direction_autocorrelation.csv', dac)
    write_csv(outdir / 'source_xml_summary.csv', source_summary(tracks))
    lengths = np.asarray([track.n_spots for track in tracks], dtype=int)
    write_csv(
        outdir / 'summary.csv',
        [
            {
                'dataset_name': dataset_name,
                'n_xml_files': n_xml_files,
                'n_tracks': len(tr),
                'n_steps': len(st),
                'n_turns': len(tu),
                'dt_s': dt,
                'unit': unit,
                'direction_threshold_deg': turn_thr,
                'filter_method': filter_method,
                'filter_threshold_points': (
                    filter_threshold_points
                    if filter_threshold_points is not None
                    else ''
                ),
                'min_trajectory_points': (
                    int(np.min(lengths)) if lengths.size else ''
                ),
                'median_trajectory_points': (
                    float(np.median(lengths)) if lengths.size else ''
                ),
                'max_trajectory_points': (
                    int(np.max(lengths)) if lengths.size else ''
                ),
            }
        ],
    )


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('xml_source', type=Path)
    p.add_argument('-o', '--outdir', type=Path, default=Path('zoospore_metrics'))
    p.add_argument('--dt', type=float, default=0.22)
    p.add_argument('--coord-scale', type=float, default=1.0)
    p.add_argument('--unit', default='micron')
    p.add_argument('--min-spots', type=int, default=10)
    p.add_argument('--direction-threshold-deg', type=float, default=30.0)
    p.add_argument('--max-lag', type=int, default=25)
    filter_group = p.add_mutually_exclusive_group()
    filter_group.add_argument(
        '--length-filter-percentile',
        type=float,
        default=90.0,
        metavar='PERCENTILE',
        help=(
            'Retain trajectories at or below this trajectory-length '
            'percentile in the filtered metric set. Default: 90.'
        ),
    )
    filter_group.add_argument(
        '--length-filter-max-points',
        type=int,
        default=None,
        metavar='POINTS',
        help=(
            'Retain trajectories containing at most this many points. '
            'Prefer this after establishing a biological/QC cutoff.'
        ),
    )
    filter_group.add_argument(
        '--no-length-filter',
        action='store_true',
        help='Do not create a filtered metric set.',
    )
    p.add_argument(
        '--filtered-subdir',
        default='length_filtered',
        help=(
            'Subdirectory of OUTDIR receiving the filtered metric set. '
            'Default: length_filtered.'
        ),
    )
    args = p.parse_args()
    if args.dt <= 0:
        p.error('--dt must be > 0')
    if args.coord_scale <= 0:
        p.error('--coord-scale must be > 0')
    if args.min_spots < 1:
        p.error('--min-spots must be >= 1')
    if args.max_lag < 1:
        p.error('--max-lag must be >= 1')
    if not 0 < args.length_filter_percentile <= 100:
        p.error('--length-filter-percentile must be in ]0, 100]')
    if args.length_filter_max_points is not None and args.length_filter_max_points < 2:
        p.error('--length-filter-max-points must be >= 2')
    if not args.filtered_subdir.strip():
        p.error('--filtered-subdir must not be empty')
    return args


def main():
    a = parse_args()
    a.outdir.mkdir(parents=True, exist_ok=True)
    xmls = (
        sorted(a.xml_source.glob('*.xml'))
        if a.xml_source.is_dir()
        else [a.xml_source]
    )
    if not xmls:
        raise ValueError('No XML files found')
    tracks = []
    next_id = 1
    for xml_path in xmls:
        local_tracks = read_xml(xml_path, a.coord_scale, a.min_spots)
        for frames, xy in local_tracks:
            tracks.append(Track(next_id, xml_path.name, frames, xy))
            next_id += 1
        print(f'{xml_path.name}: {len(local_tracks)} tracks')
    if not tracks:
        raise ValueError('No trajectory passed the minimum-length filter.')
    write_metric_set(
        outdir=a.outdir,
        tracks=tracks,
        dt=a.dt,
        unit=a.unit,
        turn_thr=a.direction_threshold_deg,
        max_lag=a.max_lag,
        n_xml_files=len(xmls),
        dataset_name='complete',
    )
    if not a.no_length_filter:
        lengths = np.asarray([track.n_spots for track in tracks], dtype=int)
        if a.length_filter_max_points is not None:
            threshold = float(a.length_filter_max_points)
            filter_method = 'absolute_max_points'
            criterion = f'n_spots <= {a.length_filter_max_points}'
        else:
            threshold = float(np.percentile(lengths, a.length_filter_percentile))
            filter_method = f'percentile_{a.length_filter_percentile:g}'
            criterion = f'n_spots <= {threshold:g} (P{a.length_filter_percentile:g})'
        retained = [track for track in tracks if track.n_spots <= threshold]
        excluded = [track for track in tracks if track.n_spots > threshold]
        if not retained:
            raise ValueError(
                'The requested trajectory-length filter excluded all tracks.'
            )
        filtered_dir = a.outdir / a.filtered_subdir
        write_metric_set(
            outdir=filtered_dir,
            tracks=retained,
            dt=a.dt,
            unit=a.unit,
            turn_thr=a.direction_threshold_deg,
            max_lag=a.max_lag,
            n_xml_files=len(xmls),
            dataset_name=a.filtered_subdir,
            filter_method=filter_method,
            filter_threshold_points=threshold,
        )
        write_csv(
            filtered_dir / 'excluded_tracks.csv',
            [
                {
                    'track_id': track.track_id,
                    'source_xml': track.source_xml,
                    'n_spots': track.n_spots,
                    'filter_criterion': criterion,
                    'reason': 'trajectory_length_above_threshold',
                }
                for track in excluded
            ],
            fields=[
                'track_id',
                'source_xml',
                'n_spots',
                'filter_criterion',
                'reason',
            ],
        )
        write_csv(
            filtered_dir / 'filter_summary.csv',
            [
                {
                    'filter_method': filter_method,
                    'filter_criterion': criterion,
                    'threshold_points': threshold,
                    'n_tracks_before': len(tracks),
                    'n_tracks_retained': len(retained),
                    'n_tracks_excluded': len(excluded),
                    'fraction_retained': len(retained) / len(tracks),
                    'fraction_excluded': len(excluded) / len(tracks),
                }
            ],
        )
        print(
            f'Filtered metrics written to: {filtered_dir} '
            f'({len(retained)}/{len(tracks)} tracks retained; {criterion})'
        )
    print(f'Complete metrics written to: {a.outdir}')
if __name__ == '__main__':
    main()
