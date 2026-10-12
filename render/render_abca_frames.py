#!/usr/bin/env python3
"""Render every spatial frame of an ABCA particle/detection XML as PNG or SVG."""
import argparse
from collections import defaultdict
from pathlib import Path
import xml.etree.ElementTree as ET

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def read_frames(path):
    frames = defaultdict(lambda: [[], []])
    # Streaming parser avoids retaining the complete XML tree in memory.
    for event, elem in ET.iterparse(path, events=('end',)):
        if elem.tag.rsplit('}', 1)[-1] == 'detection':
            try:
                t = int(float(elem.attrib['t']))
                x = float(elem.attrib['x'])
                y = float(elem.attrib['y'])
            except (KeyError, ValueError):
                pass
            else:
                frames[t][0].append(x)
                frames[t][1].append(y)
            elem.clear()
    return frames


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('xml', type=Path, help='ABCA XML input')
    ap.add_argument('-o', '--outdir', type=Path, default=None)
    ap.add_argument('--width', type=float, default=None, help='Physical domain width in µm (overrides --cols * scale)')
    ap.add_argument('--height', type=float, default=None, help='Physical domain height in µm (overrides --rows * scale)')
    ap.add_argument('--rows', type=float, default=None, help='Grid rows (requires --microns-per-cell)')
    ap.add_argument('--cols', type=float, default=None, help='Grid columns (requires --microns-per-cell)')
    ap.add_argument('--microns-per-cell', type=float, default=None, help='µm per XML coordinate unit; applied to both positions and domain (default: 1)')
    ap.add_argument('--format', choices=['png', 'svg', 'pdf'], default='png')
    ap.add_argument('--dpi', type=int, default=180)
    ap.add_argument('--size', type=float, default=6)
    ap.add_argument('--alpha', type=float, default=0.6)
    ap.add_argument('--first', type=int, default=None)
    ap.add_argument('--last', type=int, default=None)
    ap.add_argument('--step', type=int, default=1)
    args = ap.parse_args()
    if args.step < 1:
        ap.error('--step must be >= 1')
    frames = read_frames(args.xml)
    if not frames:
        ap.error('No <detection t="..." x="..." y="..."> elements found')
    xs = [x for xy in frames.values() for x in xy[0]]
    ys = [y for xy in frames.values() for y in xy[1]]
    scale = args.microns_per_cell if args.microns_per_cell is not None else 1.0
    if scale <= 0:
        ap.error('--microns-per-cell must be positive')
    width = args.width if args.width is not None else (args.cols * scale if args.cols is not None else max(xs) * scale)
    height = args.height if args.height is not None else (args.rows * scale if args.rows is not None else max(ys) * scale)
    if width <= 0 or height <= 0:
        ap.error('Domain dimensions must be positive')
    outdir = args.outdir or args.xml.with_suffix('')
    outdir.mkdir(parents=True, exist_ok=True)
    times = sorted(t for t in frames if (args.first is None or t >= args.first) and (args.last is None or t <= args.last))
    times = times[::args.step]
    for t in times:
        x, y = frames[t]
        x = [v * scale for v in x]
        y = [v * scale for v in y]
        fig, ax = plt.subplots(figsize=(5.5, 5.5))
        ax.scatter(x, y, s=args.size, alpha=args.alpha, linewidths=0)
        ax.set(xlim=(0, width), ylim=(0, height), xlabel='x (µm)', ylabel='y (µm)', title=f'Generation {t} | n={len(x)}')
        ax.set_aspect('equal', adjustable='box')
        fig.tight_layout()
        fig.savefig(outdir / f'snapshot_{t:04d}.{args.format}', dpi=args.dpi)
        plt.close(fig)
    print(f'Rendered {len(times)} frames in {outdir}')


if __name__ == '__main__':
    main()
