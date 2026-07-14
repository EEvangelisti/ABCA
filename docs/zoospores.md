# Zoospore Model

## Overview

This directory contains two **agent-based cellular automaton (ABCA)** models describing the swimming behaviour of individual oomycete zoospores.

Both models are calibrated from **single-cell tracking experiments**, but they differ in the way local behavioural rules are generated:

- **Empirical model**: movement rules are sampled directly from experimentally measured trajectory metrics (speed, turning angle, persistence, etc.).
- **Hidden Markov Model (HMM)**: local behaviour is represented by a discrete-state Hidden Markov Model inferred from experimental trajectories, allowing agents to switch probabilistically between behavioural states.

Both approaches aim to reproduce realistic population-level dynamics emerging from experimentally measured single-cell behaviours, while providing complementary modelling strategies.
---

## Model

Each zoospore is represented as an autonomous agent moving on a discrete lattice.

At every simulation step, each agent updates its state according to locally estimated probabilistic rules, including:

- movement versus stopping;
- swimming speed;
- turning angle;
- directional persistence.

The current implementation assumes independent agents and does not yet include interactions such as:

- chemotaxis;
- collisions;
- hydrodynamic effects;
- signalling between zoospores.

These mechanisms are intended for future versions.

---

## Experimental calibration

Model parameters are extracted from time-lapse microscopy of individual zoospores.

The current calibration includes:

- empirical distributions of swimming speeds;
- empirical turning-angle distributions;
- persistence statistics;
- Markov transition probabilities between RUN and STOP states.

Rather than fitting analytical distributions, the simulator samples directly from experimentally measured data using empirical cumulative distributions.

---

## Model validation

Several independent analyses are performed to verify that the simulated trajectories preserve key properties of the experimental data.

### Angular isotropy

The simulator should not introduce directional bias.

<p align="center">
  <img src="01_heading_isotropy.png" width="600">
</p>


---

### Centered trajectories

Experimental and simulated trajectories can be translated so that every track starts at the origin. This visualization provides a qualitative assessment of the global exploration pattern while removing positional effects.

<p align="center">
  <img src="02_centered_trajectories_viridis.png" width="600">
</p>

---

Additional validation metrics (speed distributions, turning statistics, persistence, MSD, autocorrelation, etc.) are currently under investigation and will be incorporated after publication.

---

## Current status

The zoospore model is under active development.

Current capabilities include:

- empirical calibration from microscopy data;
- stochastic trajectory generation;
- configurable simulation parameters;
- graphical rendering;
- export of simulated trajectories.

Several additional biological mechanisms are being implemented and validated.

---

## Citation

If you use this model, please cite the ABCA framework. Please note that a publication is currently in preparation.
