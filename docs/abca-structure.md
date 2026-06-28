## Project structure

```text
ABCA/
├── bin/                 Command-line executable
├── core/                Simulation engine
├── io/                  Binary and XML input/output
├── render/              PNG, GIF, and MP4 rendering
├── palette/             Built-in color palettes
├── models/              Shared model interface and registry
├── plugin_registry/     Static plugin registration
├── plugins/             Model families
└── examples/            Example animations and outputs
```

## Built-in model families

ABCA currently includes several families of classical automata.

### Life-like automata

Life-like automata generalize Conway’s Game of Life using birth and survival rules. They include models such as Life, HighLife, Day & Night, Maze, Replicator, and many others.

### Generations

Generations automata extend Life-like rules by adding ageing or refractory states. Cells may remain visible for several generations after leaving the active state, producing waves, trails, and excitable patterns.

### Cyclic automata

Cyclic automata use multiple states arranged in a loop. A cell changes state when enough neighboring cells are in its successor state. These models often generate spiral waves and rotating domains.

### Larger-than-Life

Larger-than-Life automata extend neighborhood size beyond the classical Moore neighborhood. They can generate large-scale structures, textures, and collective spatial dynamics.

### Weighted Life

Weighted Life automata assign different weights to neighboring positions. This allows asymmetric or anisotropic local rules and produces patterns that differ strongly from classical Life-like models.

## Rendering and palettes

ABCA includes several built-in palettes, including:

* grayscale;
* heat;
* fire;
* cyclic;
* viridis;
* plasma;
* magma;
* inferno;
* cividis.

Rendering options are independent from model definitions. This means that the same simulation can be visualized with different palettes and backgrounds.

For example:

```bash
abca --mode render \
  --model generations-star-wars \
  --input starwars.bin \
  --gif starwars.gif \
  --palette viridis \
  --background black
```

## Reproducibility

ABCA simulations are reproducible. The `--seed` option controls the pseudo-random generator, while `--density` controls the initial proportion of active cells for classical grid-based automata.

For example:

```bash
--seed 42
```

does not mean “42 active cells”. It means that the same random initialization will be produced again whenever the same parameters are used.


