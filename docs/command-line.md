# Command-line interface

ABCA is primarily designed as a command-line application.

The executable is called:

```bash
abca
```

The program is organized around several operating modes.

---

# Simulation

Run a simulation and save the complete history in ABCA's binary format.

```bash
abca --mode run [options]
```

## General options

| Option          | Description                          |
| --------------- | ------------------------------------ |
| `--model`       | Model to simulate.                   |
| `--rows`        | Grid height.                         |
| `--cols`        | Grid width.                          |
| `--generations` | Number of generations to compute.    |
| `--density`     | Initial proportion of active cells.  |
| `--seed`        | Random seed used for initialization. |
| `--toroidal`    | Use toroidal boundary conditions.    |
| `--out`         | Output binary file (`.autbin`).      |

### Example

```bash
abca \
  --mode run \
  --model life \
  --rows 300 \
  --cols 300 \
  --generations 500 \
  --density 0.25 \
  --seed 42 \
  --out life.autbin
```

---

# XML export

Export a previously generated simulation to XML.

```bash
abca --mode xml [options]
```

## Options

| Option    | Description              |
| --------- | ------------------------ |
| `--input` | Input binary simulation. |
| `--xml`   | Output XML file.         |

### Example

```bash
abca \
  --mode xml \
  --input life.autbin \
  --xml life.xml
```

---

# Rendering

Generate PNG images, animated GIFs, or MP4 videos from a simulation.

```bash
abca --mode render [options]
```

## Input

| Option    | Description                   |
| --------- | ----------------------------- |
| `--input` | Input simulation (`.autbin`). |

## PNG generation

| Option        | Description                             |
| ------------- | --------------------------------------- |
| `--png`       | Output directory containing PNG frames. |
| `--every`     | Export one frame every *N* generations. |
| `--cell-size` | Cell size in pixels.                    |

## GIF / MP4 generation

| Option  | Description           |
| ------- | --------------------- |
| `--gif` | Output GIF filename.  |
| `--mp4` | Output MP4 filename.  |
| `--fps` | Animation frame rate. |

## Rendering options

| Option         | Description                                           |
| -------------- | ----------------------------------------------------- |
| `--palette`    | Color palette.                                        |
| `--background` | Background colour (`white`, `black`, `#RRGGBB`, ...). |

### Example

```bash
abca \
  --mode render \
  --input life.autbin \
  --gif life.gif \
  --palette viridis \
  --background white \
  --every 5 \
  --fps 30
```

---

# Listing available models

Display all registered models.

```bash
abca --list-models
```

Example output:

```text
life-like
    life
    high-life
    day-and-night
    maze

larger-than-life
    bugs
    waffle

cyclic
    spirals

generations
    star-wars
```

---

# Listing available palettes

Display all registered palettes.

```bash
abca --list-palettes
```

Example output:

```text
grayscale
heat
fire
cyclic
viridis
plasma
magma
inferno
cividis
```

---

# Typical workflow

A complete workflow usually consists of three independent steps.

## 1. Run the simulation

```bash
abca --mode run ...
```

↓

Produces:

```text
simulation.autbin
```

## 2. Export (optional)

```bash
abca --mode xml ...
```

↓

Produces:

```text
simulation.xml
```

## 3. Render

```bash
abca --mode render ...
```

↓

Produces one or more of:

* PNG frames
* animated GIF
* MP4 video

Because rendering is independent from simulation, the same binary file can be rendered multiple times using different palettes, backgrounds, frame rates, or image sizes without recomputing the simulation.

---

# Future extensions

The command-line interface is expected to evolve while remaining backward compatible.

Planned additions include:

* plugin-specific command-line arguments;
* external palette files;
* user-defined initialization strategies;
* simulation metadata inspection;
* binary file information (`abca --info simulation.autbin`);
* dynamic plugin loading.

