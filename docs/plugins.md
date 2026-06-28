# Plugins

ABCA has been designed from the beginning as a plugin-oriented simulation framework.

Rather than modifying the simulation engine itself, new models are added by creating plugins that implement a common interface. This architecture allows independent development of new automata families while keeping the core engine small, reusable, and stable.

## What is a plugin?

A plugin is responsible for defining one or more simulation models belonging to the same family.

For example:

* Life-like automata
* Larger-than-Life automata
* Generations automata
* Cyclic automata
* Weighted Life automata
* Agent-based models
* Biological simulations

Each plugin registers its models in the global registry during program initialization.

## Plugin responsibilities

A plugin is responsible for:

* defining one or more models;
* loading model definitions (for example from external rule files);
* generating the initial simulation state;
* executing the simulation;
* exporting simulation results to XML;
* converting internal states into color indices for rendering.

Rendering itself is handled by the ABCA rendering engine and is therefore completely independent of the plugin.

## Rule files

Many plugins rely on external rule definition files rather than hard-coded rules.

This approach makes it easy to:

* add new models;
* modify existing rules;
* distribute collections of automata without recompiling ABCA.

For example, a Life-like plugin may simply load all rules contained in a `life.rules` file and automatically register them.

## Plugin directory structure

A typical plugin directory looks like:

```text
plugins/
    life/
        dune
        life.ml
        life.rules

    cyclic/
        dune
        cyclic.ml
        cyclic.rules
```

Each directory corresponds to a single family of related models.

## Static and dynamic plugins

The current implementation uses static registration during compilation.

The architecture has deliberately been designed so that future versions may also support dynamically loaded plugins without modifying the core simulation engine.

## Future developments

Planned extensions include:

* dynamically loaded plugins;
* plugin-specific command-line arguments;
* custom initialization strategies;
* plugin metadata;
* documentation generated directly from plugins.

