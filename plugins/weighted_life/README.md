# Weighted Life Cellular Automata

The `weighted_life` plugin implements **Weighted Life cellular automata**, a family of Life-like rules in which each position of the local neighbourhood can contribute a different weight to the transition score.

This allows rules to distinguish between directions, emphasise the central cell, and generate behaviours that cannot be expressed using standard neighbour counts alone.

## Rule definition

Rules are defined in:

```text
plugins/weighted_life/weighted_life.rules
```

Each rule follows the format:

```text
AUTOMATON "<name>": NW<nw> NN<nn> NE<ne> WW<ww> ME<me> EE<ee> SW<sw> SS<ss> SE<se> HI<history> RS<score> ... RB<score> ...
```

The nine weight fields describe the contribution of each position in the local 3 × 3 neighbourhood:

```text
NW  NN  NE
WW  ME  EE
SW  SS  SE
```

where `ME` is the central cell.

The transition score is obtained by summing the weights of active cells in this neighbourhood.

* `RS` values specify scores for survival.
* `RB` values specify scores for birth.
* `HI` controls the use of additional cell states.

For example,

```text
AUTOMATON "CAREER": NW1 NN2 NE1 WW1 ME0 EE1 SW1 SS1 SE1 HI0 RS2 RS3 RB3
```

defines a rule in which:

* north and south neighbours have weight 2;
* diagonal and horizontal neighbours have weight 1;
* the central cell has weight 0;
* living cells survive with a score of 2 or 3;
* dead cells are born with a score of 3.

## Cell history

When `HI` is greater than zero, cells that do not survive progress through a sequence of intermediate history states before returning to the inactive state.

When `HI` is zero, the rule does not use decay-history states. Surviving cells can nevertheless progress through display states, allowing their age or persistence to be represented during rendering.

## Available rules

The plugin currently includes:

* Border
* Bricks
* Career
* Cyclish
* Fire-Flies
* Hourglass
* Maze Makers

Additional rules can be added by editing `weighted_life.rules`; no recompilation is required.

## Initialisation

The initial configuration is generated randomly according to a user-defined density. Active cells start in state 1, while all remaining cells start in state 0.

## Documentation

General information about the ABCA framework is available in the repository root:

* [`README.md`](../../README.md)

