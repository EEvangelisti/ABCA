<p align="center">
  <img src="doc/logo.png" alt="ABCA" width="600" />
</p>

**ABCA** is a framework for two-dimensional **cellular automata (CA)** and **agent-based cellular automata (ABCA)**.

It provides a common simulation engine together with a modular plugin system, allowing a wide range of models to share the same execution, rendering, and export pipeline. Simulations can be saved as compact binary files and rendered as images, animations, or videos.

## Installation

The empirical model assets used by the AI-derived zoospore plugins are stored using Git LFS.
Make sure Git LFS is installed before cloning the repository:

```bash
git lfs install
git clone git@github.com:EEvangelisti/ABCA.git
```

If the repository was cloned before Git LFS was installed, retrieve the large assets with:

```bash
git lfs pull
```

Compile the project with [dune](https://github.com/ocaml/dune):

```bash
dune build
```

During development, the program can be run directly without manually locating the executable:

```bash
dune exec abca -- <options>
```

The available `<options>` are defined [in this document](doc/cli.md).

## Plugins

ABCA uses a plugin architecture in which every model is implemented as an independent plugin located in the `plugins/` directory. Each plugin provides its own rules, parameters, documentation, and example simulations while relying on the common ABCA simulation and rendering engine.

The framework currently includes both classical cellular automata and agent-based cellular automata. While the former illustrate the flexibility of the engine, the latter are actively used in computational phytopathology research (e.g., to model the behaviour of *Phytophthora* zoospores from experimentally calibrated data).

The current distribution includes the following plugins:

| Plugin                                                   | Type | Description                                                                     |
| -------------------------------------------------------- | ---- | ------------------------------------------------------------------------------- |
| [`cyclic`](plugins/cyclic/README.md)                     | CA   | Cyclic cellular automata                                                        |
| [`generations`](plugins/generations/README.md)           | CA   | Multi-state Generations automata                                                |
| [`larger_than_life`](plugins/larger_than_life/README.md) | CA   | Larger-than-Life cellular automata                                              |
| [`life`](plugins/life/README.md)                         | CA   | Life-like cellular automata                                                     |
| [`weighted_life`](plugins/weighted_life/README.md)       | CA   | Weighted Life cellular automata                                                 |
| [`zoospores`](plugins/zoospores/README.md)               | ABCA | Agent-based models of *Phytophthora* zoospore swimming                          |


## Agentic-AI discovered zoospore models

A separate set of *Phytophthora* zoospore movement models was generated through
independent agentic-AI model-discovery campaigns and subsequently reconciled into
a common canonical model portfolio. These models are associated with a separate
study currently in preparation and are kept distinct from the
`zoospores` plugin described above.

The reconciled portfolio comprises 13 canonical model classes:

| Canonical model | Family | Generative principle |
| --- | --- | --- |
| `CAN-IID` | Simple / null | Independent step lengths with a newly sampled isotropic heading at each update. |
| `CAN-BALLISTIC` | Simple / null | Motion with a constant heading and stochastic step length. |
| `CAN-PCRW` | Persistent motion | Persistent correlated random walk driven by stochastic step lengths and turning-angle innovations. |
| `CAN-TURN-AR1` | Persistent motion | Persistent walk in which successive turning angles follow a first-order autoregressive process. |
| `CAN-VELOCITY-OU` | Persistent motion | Cartesian velocity follows a mean-reverting autoregressive process. |
| `CAN-SPEED-TURN` | Persistent motion | Turning variability depends on instantaneous movement speed. |
| `CAN-SWITCH-PAUSE` | State switching | Hidden-state model switching between movement and pause states. |
| `CAN-SWITCH-TURN` | State switching | Hidden-state model switching between low- and high-turning regimes. |
| `CAN-SWITCH-SPEED` | State switching | Hidden-state model switching between fast and slow movement regimes. |
| `CAN-HET-SPEED` | Individual heterogeneity | A trajectory-specific random effect introduces persistent between-track differences in speed. |
| `CAN-REVERSAL` | Event-based motion | Persistent movement supplemented by explicit approximately 180° reversal events. |
| `CAN-EMP-LOCAL` | Empirical / resampling | Local movement updates are sampled from empirical step-length/turning-angle transitions. |
| `CAN-EMP-WHOLE` | Empirical / resampling | Complete empirical displacement sequences are resampled as whole trajectories. |

All canonical models are exposed through a common ABCA plugin and use external
parameter files so that model fitting can be performed independently of the
simulation code.
