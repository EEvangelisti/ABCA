<p align="center">
  <img src="docs/logo.png" alt="ABCA" />
</p>

# ABCA

**ABCA** is a simulation engine for two-dimensional cellular automata and agent-based cellular automata.

It provides two main functions:

* running and storing simulations;
* rendering simulation outputs as images, animations, or videos.

## Plugin-based models

Simulation models are implemented as plugins located in the `plugins/` directory.

ABCA currently includes the following plugins:

### Cellular automata

* [`cyclic`](plugins/cyclic/README.md)
* [`generations`](plugins/generations/README.md)
* [`larger_than_life`](plugins/larger_than_life/README.md)
* [`life`](plugins/life/README.md)
* [`weighted_life`](plugins/weighted_life/README.md)

### Agent-based cellular automata

* [`zoospores`](plugins/zoospores/README.md)

Each plugin defines its own states, parameters, and transition rules while relying on the common ABCA simulation and rendering engine.


