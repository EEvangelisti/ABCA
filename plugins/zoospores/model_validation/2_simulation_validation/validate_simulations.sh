#! /bin/bash

source ../python_venvs/zoospore_env/bin/activate

python compare_experimental_simulation_ensemble_metrics.py \
    ../exp_Jo/trajectory_analysis/ \
    simulated_trajectories_resampled/trajectory_analysis/ \
    -o validation_dataset_comparison \
    --upper-percentile 99.5

deactivate
