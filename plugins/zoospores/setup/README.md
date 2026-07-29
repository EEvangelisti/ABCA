## Setting up the Python environment

### Purpose

Create a dedicated Python virtual environment, install all required Python
packages, and generate a `python.conf` configuration file for subsequent
analysis scripts.

### Input

- Python interpreter (optional command-line argument; default: `/usr/bin/env python3`)

### Output

- Python virtual environment (`python_venv/`)
- Configuration file (`python.conf`) containing the path to the Python
  interpreter inside the virtual environment

### Usage

```bash
./setup_python.sh
```

or

```bash
./setup_python.sh /path/to/python3
```

### A typical output

```bash
Creating Python virtual environment...
Upgrading pip...
Installing required packages...

Python successfully configured.
Configuration written to: python.conf
Python interpreter:       python_venv/bin/python
```


### Notes

- The virtual environment is created only if it does not already exist.
- Required Python packages are installed or upgraded automatically.
- Other Bash scripts in the workflow read `python.conf` to locate the Python
  interpreter, ensuring that the same environment is used throughout the
  analysis pipeline.

The analysis pipeline depends on the following Python packages:

- **[NumPy](https://numpy.org/)** – numerical arrays and vectorised computations.
- **[pandas](https://pandas.pydata.org/)** – tabular data manipulation and CSV input/output.
- **[SciPy](https://scipy.org/)** – scientific computing and statistical functions.
- **[Matplotlib](https://matplotlib.org/)** – generation of publication-quality figures.
- **[scikit-learn](https://scikit-learn.org/)** – data preprocessing and machine learning utilities.
- **[hmmlearn](https://hmmlearn.readthedocs.io/)** – Gaussian Hidden Markov Model fitting.
- **[tol-colors](https://github.com/jiffyclub/palettable)** – Paul Tol's colour palettes for scientific visualisation.
