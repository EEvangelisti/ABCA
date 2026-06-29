# Zoospore model

The zoospore model is the first biological proof of concept implemented in ABCA.

It illustrates how the framework can represent mobile biological agents in a discrete spatial environment. Unlike classical cellular automata, where each cell updates its state according to neighboring cells, this model follows individual agents that move across the grid according to local rules.

The purpose of the model is not to prescribe a global swimming pattern. Instead, it defines how each zoospore behaves at each simulation step: how it chooses a direction, how far it moves, how it reacts to obstacles, and how its state is rendered.

## Biological motivation

Zoospores are motile microbial cells produced by several filamentous plant pathogens, including oomycetes. They swim through water films, reorient, collide with surfaces or other cells, and eventually contribute to host colonization.

The ABCA zoospore model does not aim to reproduce a complete biological system. It is a minimal agent-based model designed to test whether biologically inspired movement rules can be integrated into the same framework as classical cellular automata.

It therefore serves as a feasibility demonstration for future models involving microbial movement, chemotaxis, tissue colonization, and host–microbe interactions.

## Local-rule philosophy

The model is intentionally defined through local decisions.

At each generation, every zoospore:

1. starts from its current position and direction;
2. slightly modifies its swimming angle, unless it spontaneously reorients;
3. chooses a movement length;
4. tests whether the target path is available;
5. moves if the path is free;
6. changes direction if the path is blocked;
7. ages by one simulation step.

No global trajectory is imposed. Collective patterns emerge only from the repeated application of these local rules to many agents.

## Agent state

Each zoospore is represented internally as an agent with:

```ocaml
type agent = {
  id    : int;
  row   : int;
  col   : int;
  age   : int;
  angle : int;
}
```

The fields have the following meaning:

* `id`: unique identifier of the zoospore;
* `row`, `col`: current grid position;
* `age`: number of simulation steps since initialization;
* `angle`: current swimming direction.

The rendered simulation frame stores only integer states:

```ocaml
type state = int
```

In the current implementation:

* `0` represents an empty cell;
* positive values represent zoospores;
* the displayed value increases with age, up to `MAX_AGE`.

This keeps the output compatible with ABCA rendering, binary storage, XML export, and color palettes.

## Rule parameters

Zoospore behavior is controlled by rules stored in `zoospores.rules`.

A rule line has the following structure:

```text
AUTOMATON "ZOOSPORE DEFAULT": DIRS=360/BASE_STEP=2/FAST_STEP=5/FAST_PROB=0.166667/WIGGLE=5/PERSISTENCE=12/MIN_TURN=30/MAX_AGE=8/AGENTS=200/INIT=DISK/RADIUS=100/THICKNESS=4
```

The parameters define local movement and initialization rules:

| Parameter     | Meaning                                                              |
| ------------- | -------------------------------------------------------------------- |
| `DIRS`        | Number of discrete angular directions.                               |
| `BASE_STEP`   | Default movement length in cells.                                    |
| `FAST_STEP`   | Longer movement length used during fast steps.                       |
| `FAST_PROB`   | Probability of using `FAST_STEP` instead of `BASE_STEP`.             |
| `WIGGLE`      | Maximum random angular drift around the current direction.           |
| `PERSISTENCE` | Controls how often a zoospore spontaneously chooses a new direction. |
| `MIN_TURN`    | Minimum angular turn after a collision.                              |
| `MAX_AGE`     | Maximum displayed age state.                                         |
| `AGENTS`      | Default number of zoospores.                                         |
| `INIT`        | Initial spatial distribution: `FULL`, `DISK`, or `RING`.             |
| `RADIUS`      | Radius used for disk or ring initialization.                         |
| `THICKNESS`   | Thickness used for ring initialization.                              |

The number of agents can be overridden from the command line using `--agents`.

## Initialization

The initial population is created by selecting grid coordinates from a geometric region.

Three initialization modes are supported:

* `FULL`: agents may be placed anywhere on the grid;
* `DISK`: agents are placed within a disk;
* `RING`: agents are placed within a ring.

The center is currently the grid center. A random subset of coordinates is selected, and each agent receives a random initial angle.

This initialization only defines the starting condition. It does not constrain later movement.

## Direction and angular drift

Angles are represented as integers in a circular space of size `DIRS`.

For example, with:

```text
DIRS=360
```

one unit corresponds to one degree.

At each step, the current angle is updated locally. Most of the time, the agent keeps approximately the same direction, with a small random drift:

```text
angle ← angle + random value between -WIGGLE and +WIGGLE
```

This implements directional persistence while avoiding perfectly straight movement.

## Spontaneous reorientation

A zoospore may occasionally abandon its current direction and choose a completely new one.

This is controlled by `PERSISTENCE`.

In simplified terms:

```text
with probability approximately 1 / PERSISTENCE:
    choose a new random angle
otherwise:
    drift slightly around the current angle
```

Thus, higher persistence values produce longer directional memory, while lower values produce more frequent reorientation.

## Movement speed

Each zoospore chooses its movement length locally at every step.

The default movement length is `BASE_STEP`. With probability `FAST_PROB`, the zoospore instead uses `FAST_STEP`.

For the default rule:

```text
BASE_STEP=2
FAST_STEP=5
FAST_PROB=0.166667
```

most movements are short, but occasional longer movements occur.

This creates variable swimming speed without imposing a global trajectory.

## From angle to grid movement

The selected angle is converted into a grid offset.

The model computes a local direction vector from the angle:

```text
angle → (dr, dc)
```

where:

* `dr` is the row displacement direction;
* `dc` is the column displacement direction.

The actual movement then attempts to advance several cells along this direction, according to the chosen speed.

## Occupancy and collision handling

Before moving, each zoospore checks whether its target path is available.

A move can fail if:

* the target coordinate lies outside a bounded grid;
* another zoospore already occupies the target path;
* another zoospore has already reserved the target position during the current update.

If the move succeeds, the zoospore is placed at the new coordinate.

If the move fails, the zoospore does not move. Instead, it changes direction by at least `MIN_TURN`.

This rule is local: the zoospore reacts only to the availability of the path it attempts to take.

## Collision-induced turning

When movement is blocked, the zoospore receives a new angle.

The new direction is constrained so that the turn is not too small. The parameter `MIN_TURN` defines the minimum angular change after collision.

For example:

```text
MIN_TURN=30
```

means that a blocked zoospore must turn by at least 30 degrees.

This prevents agents from repeatedly attempting almost the same blocked move.

## Grid topology

The model uses the topology provided by the ABCA grid.

With a bounded grid, movement outside the grid fails.

With a toroidal grid, coordinates wrap around the borders.

The same local movement rule can therefore be tested under different spatial assumptions.

## Rendering

Simulation frames are produced from the current agent positions.

Each occupied coordinate receives a positive integer value based on agent age:

```text
state = 1 + age
```

with the age clamped to `MAX_AGE`.

This makes it possible to render zoospores with age-dependent colors, while empty cells remain at state `0`.

## Output

The zoospore model uses the standard ABCA output pipeline:

* binary simulation storage;
* metadata recording;
* XML export;
* PNG rendering;
* GIF and MP4 animation.

The metadata stores the parameters used to generate the simulation, including the rule name, grid size, seed, topology, initialization mode, movement parameters, and agent count.

## Current default rule

The current default model is:

```text
ZOOSPORE DEFAULT
```

with the following parameters:

```text
DIRS=360
BASE_STEP=2
FAST_STEP=5
FAST_PROB=0.166667
WIGGLE=5
PERSISTENCE=12
MIN_TURN=30
MAX_AGE=8
AGENTS=200
INIT=DISK
RADIUS=100
THICKNESS=4
```

This defines a population of mobile agents initialized in a disk, with persistent but noisy movement, occasional faster steps, and collision-induced reorientation.

## Interpretation

The model should not be interpreted as a calibrated biological model.

It is better understood as a local-rule prototype:

* agents do not know the global state of the simulation;
* no target trajectory is prescribed;
* movement is produced step by step;
* global patterns emerge from local decisions;
* all parameters remain explicit and reproducible.

This makes the zoospore model a useful first demonstration of how ABCA can support biological modelling while preserving the logic of cellular automata: simple local rules, repeated over space and time.

