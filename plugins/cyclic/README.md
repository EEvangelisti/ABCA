# Cyclic Cellular Automata

The `cyclic` plugin implements a family of cyclic cellular automata (CCA), a class of multi-state cellular automata in which cells evolve through a cyclic sequence of states depending on the states of their neighbours.

Starting from a random initial configuration, cyclic automata generate a wide variety of dynamic spatial patterns, including spiral waves, domains, and self-organising structures.

## Rule definition

Rules are defined in the file:

```text
plugins/cyclic/cyclic.rules
```

Each rule follows the format:

```text
AUTOMATON "<name>": R<range>/T<threshold>/C<states>
```

where:

* **R** is the neighbourhood radius;
* **T** is the minimum number of neighbouring cells already in the successor state required for a transition;
* **C** is the number of cyclic states.

For example,

```text
AUTOMATON "SPIRALS": R3/T5/C8
```

defines a cyclic automaton with:

* neighbourhood radius = 3;
* transition threshold = 5;
* 8 cyclic states.

## Available rules

The plugin currently provides the following predefined automata:

* 313
* Spirals
* Imperfect
* Fossil Debris
* Lava Lamp
* Perfect
* Turbulent Phase

Additional rules can be added simply by editing `cyclic.rules`; no recompilation is required.

## Initialisation

The initial configuration is generated randomly according to a user-defined density. Active cells are assigned a random state uniformly among the available cyclic states.

## Documentation

General information about the ABCA framework is available in the repository root:

* [`README.md`](../../README.md)

