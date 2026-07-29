#!/usr/bin/env bash
set -Eeuo pipefail

# Setting up Python environment
cd setup
./setup_python.sh "${1:-}"
cd ..

# Analysing trajectories
cd trajectory_analysis

cd metrics_extraction
./extract_trajectory_metrics.sh extract_trajectory_metrics.conf
cd ..

cd metrics_analysis
./analyse_trajectory_metrics.sh analyse_trajectory_metrics.conf
cd ..

cd plotting_overviews
./plot_trajectory_overview.sh plot_trajectory_overview.conf
cd ..

cd ..
