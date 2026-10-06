← **[Back to ABCA documentation](../../README.md)**

---

# Agentic-AI-Derived Models of Zoospore Swimming Behaviour

This plugin provides a reconciled portfolio of agent-based models describing the swimming behaviour of *Phytophthora* zoospores.

Unlike the manually designed zoospore models distributed in the [`zoospores`](../zoospores/README.md) plugin, the models provided here were obtained through an **agentic-AI model-discovery workflow**. Three independent AI modelling campaigns were given the same experimental trajectory data and the ABCA core simulation framework, but no zoospore-specific model from the previous study. Each campaign independently explored candidate generative rules, implemented executable ABCA models, and performed pilot quantitative screening.

The resulting candidate portfolios were then analysed by a separate **AI reconciliation team**, which compared models according to their mathematical and generative structure rather than their names or exploratory rankings. Equivalent or nested formulations were consolidated where appropriate, while structurally distinct hypotheses were retained. This procedure produced a canonical portfolio of **13 model classes**, all exposed through a common ABCA plugin.

The canonical models were subsequently fitted using a common Python pipeline operating on the complete TrackMate XML trajectory dataset published in Le Berre et al. (2026). Fitted numerical parameters are stored externally in a TOML parameter file so that model calibration remains separate from the simulation source code.

Independent experimental movies are reserved for subsequent out-of-sample validation in the associated study.

## Reference manuscript

The agentic-AI model-discovery and reconciliation workflow is described in:

> **[MANUSCRIPT REFERENCE TO BE ADDED SOON]**

The original experimental trajectory dataset and manually developed zoospore models are described in:

Le Berre J, Attard A, Evangelisti E (2026). *Data-driven inference of local behavioural rules predicts emergent properties of Phytophthora zoospore dispersal*. bioRxiv 2026.08.12.744352.  
https://doi.org/10.64898/2026.08.12.744352

## How the canonical portfolio was obtained

The workflow comprised four successive stages:

1. **Independent model discovery.**  
   Three agentic-AI modelling campaigns independently inspected the same experimental trajectories and ABCA framework, proposed alternative generative hypotheses, implemented executable plugins, and compared them in small pilot screens.

2. **Cross-campaign reconciliation.**  
   A separate specialised AI team compared the resulting candidates at the level of state variables, update equations, stochastic dependencies, memory structure, and parameterisation. Reconciliation was used to identify equivalence, nesting, relatedness, and genuine structural differences; it was not used to select a preferred model.

3. **Canonical implementation.**  
   The reconciled hypotheses were implemented in a single ABCA plugin exposing 13 canonical model classes through a common simulation interface and a shared external parameter schema.

4. **Common fitting.**  
   All canonical models were fitted from the same complete TrackMate trajectory dataset using a common preprocessing pipeline. Model-specific estimators were used where required, while preserving a common data source, parameter provenance, and output format. Empirical models were fitted by generating transition- and whole-trajectory reference libraries directly from the experimental trajectories.

This separation between discovery, reconciliation, implementation, and fitting was designed to prevent exploratory campaign-specific parameterisations or rankings from being carried directly into the final model comparison.

## Available models

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


## Plugin structure

The main files used by this plugin are:

| File | Description |
| --- | --- |
| `zoospores_IA.ml` | Main ABCA plugin implementing the 13 canonical model classes. |
| `schema_validation.ml` | Strict validation of the external parameter-file structure. |
| `canonical_fit/canonical_parameters.toml` | Fitted parameters and structural choices for all canonical models. |
| `canonical_fit/empirical_local_transitions.txt` | Empirical local transition library used by `CAN-EMP-LOCAL`. |
| `canonical_fit/empirical_whole_trajectories.txt` | Whole-trajectory displacement library used by `CAN-EMP-WHOLE`. |
| `[FITTING SCRIPT PATH PLACEHOLDER]` | Python fitting pipeline used to regenerate the canonical parameter set and empirical libraries from TrackMate XML trajectories. |

The two empirical libraries are large derived fitting artefacts and are stored using **Git LFS**.

## Large empirical assets

`CAN-EMP-LOCAL` and `CAN-EMP-WHOLE` require empirical libraries generated from the fitting dataset. These files are distributed through Git LFS:

- `canonical_fit/empirical_local_transitions.txt`
- `canonical_fit/empirical_whole_trajectories.txt`

Make sure Git LFS is installed before cloning the ABCA repository:

```bash
git lfs install
git clone git@github.com:EEvangelisti/ABCA.git
```

If the repository was cloned before Git LFS was installed, retrieve the empirical assets with:

```bash
git lfs pull
```

The SHA-256 checksum of each empirical asset is stored in `canonical_parameters.toml` and is verified by the plugin before simulation.

## Parameter files

All fit-relevant numerical parameters are externalised in:

```text
canonical_fit/canonical_parameters.toml
```

The parameter file contains:

- common simulation settings;
- model-specific fitted parameters;
- explicit structural choices for model classes retaining alternative reconciled formulations;
- paths and SHA-256 checksums for empirical fitting artefacts.

The plugin performs strict schema validation before simulation. Unknown sections or keys, missing required parameters, malformed values, and incompatible model-specific settings are rejected rather than silently replaced by defaults.

This design allows the same model implementation to be refitted to another trajectory dataset without modifying the OCaml source code.

## Model variants retained after reconciliation

Cross-campaign reconciliation identified cases in which independently generated candidates expressed the same broad modelling principle but differed in their mathematical formulation. These alternatives were not silently averaged or hybridised.

In particular:

- `CAN-SPEED-TURN` retains alternative additive and multiplicative formulations for speed-dependent turning;
- `CAN-HET-SPEED` retains alternative additive and multiplicative formulations of persistent between-trajectory speed heterogeneity.

The selected formulation is declared explicitly in the parameter file before fitting and simulation.

Similarly, the state-switching models remain separate because their hidden states control different observables:

- `CAN-SWITCH-PAUSE`: movement versus pause;
- `CAN-SWITCH-TURN`: low- versus high-turning regimes;
- `CAN-SWITCH-SPEED`: fast versus slow movement regimes.

These models therefore represent distinct generative hypotheses rather than interchangeable parameterisations of a single switching process.

## Model fitting

The current parameter set was fitted from the complete TrackMate XML trajectory dataset associated with Le Berre et al. (2026).

The fitting pipeline:

1. parses complete trajectories from the TrackMate XML file;
2. reconstructs ordered displacement vectors, step lengths, headings, and turning angles;
3. applies the same preprocessing to all canonical models;
4. estimates model-specific numerical parameters;
5. constructs the empirical transition and whole-trajectory libraries;
6. writes a common TOML parameter file and fitting summary;
7. records hashes of the source and derived fitting artefacts.

Models containing latent behavioural states are fitted using likelihood-based hidden-state procedures rather than fixed threshold assignments. The purpose of the fitting stage is parameter estimation only; model selection is performed subsequently from independent validation evidence.

To regenerate the complete fitted portfolio:

```bash
python fit_canonical_portfolio_trackmate_particles.py P_nicotianae_zoospore_trajectories_p3-1.xml --out canonical_fit
```

Because hidden-state models are fitted on the complete trajectory collection, fitting can be computationally intensive.

## Running simulations

All 13 canonical models are exposed through the same ABCA plugin. Each simulation requires the external parameter file:

```text
canonical_fit/canonical_parameters.toml
```

For general ABCA command-line options, see the [ABCA CLI documentation](../../doc/cli.md).

## Reproducibility and provenance

The plugin is designed so that the main components of the analysis remain independently inspectable:

- model definitions are contained in the OCaml plugin;
- parameter-file structure is enforced by `schema_validation.ml`;
- fitted values are stored outside the source code;
- empirical fitting artefacts are checksum-verified before use;
- model and parameter-file provenance are embedded in ABCA simulation metadata;
- the fitting pipeline can regenerate the complete parameter set from the original TrackMate trajectory file.

The model portfolio should therefore be interpreted as a set of **alternative generative hypotheses** produced by agentic-AI discovery and reconciliation, rather than as a single inferred biological mechanism.

---

← **[Back to ABCA documentation](../../README.md)**
