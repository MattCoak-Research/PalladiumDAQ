# Palladium DAQ

*Version {{version}}*

Palladium DAQ is a modular framework for laboratory data acquisition: instrument control, data logging and real-time graphing, built in MATLAB. It includes a library of instrument drivers for common lab hardware - multimeters, source meters, lock-in amplifiers, temperature controllers, magnet power supplies and more - and adding new ones is straightforward. It grew out of condensed matter physics labs, where a cryostat's temperature controllers and magnet power supplies run alongside the measurement electronics, but it suits any setup where several instruments are read together over time.

## Features

* **Instruments** - a built-in suite of instrument drivers, easy to extend with new MATLAB or Python classes based on the templates provided
* **Real-time plotting** of all acquired data, in tabs and separate windows
* **Instrument Controls** - logic and GUI elements for sweeps, scans, heater and magnet control, and other more complex measurements
* **Presets** - `.json` files describing a lab's usual hardware and settings, so it is all set up when Palladium DAQ starts
* **Data Viewer** - a programme for viewing and comparing saved data files
* **Sequence Editor** - scripts of commands for autonomous measurement runs

Palladium DAQ can run with its default GUI, with an alternative GUI, or with no GUI at all from scripts.

## Where to start

* [Getting started](quick-start.md) - launch Palladium DAQ and take your first (simulated) measurement
* [Installation](installation.md) - the MATLAB toolbox and the standalone application
* [GUI tour](gui-tour.md) - what the parts of the main window do
* [Presets and Config.json](presets-and-config.md) - setting Palladium DAQ up the same way every time
* [Sequences](sequences.md) - automating measurement runs
* [Data files](data-files.md) - what is saved, and how to load it back
* [Writing an instrument driver](writing-instruments.md) and [Python instruments](python-instruments.md) - adding your own hardware
* [API reference](reference/index.md) - the classes, their properties and methods
* [Developers](developers/index.md) - working on Palladium DAQ itself

Palladium DAQ is developed by M.J. Coak at the University of Birmingham, on [GitHub](https://github.com/MattCoak-Research/PalladiumDAQ). It is under active development - contributions and bug reports are welcome.
