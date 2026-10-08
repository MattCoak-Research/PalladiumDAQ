# Developing Palladium DAQ

These pages are for people working on Palladium DAQ itself - fixing bugs, adding features, or contributing instrument drivers back to the project. To write your own instrument drivers for your lab, see [Writing an instrument driver](../writing-instruments.md) and [Python instruments](../python-instruments.md).

## Getting the source

Palladium DAQ is developed on [GitHub](https://github.com/MattCoak-Research/PalladiumDAQ). Clone the repository, and in MATLAB open the project file `PalladiumDAQ.prj` (Project tab > Open). The MATLAB Project sets up the path, source control and file labels. Development needs MATLAB R2026b or later with the Instrument Control Toolbox; building the documentation also needs the DocMaker add-on (see [Build pipeline](build-pipeline.md)).

Contributions are welcome, by pull request or by email to m.j.coak@bham.ac.uk.

## Tests

The tests are in `Palladium DAQ/Tests`:

* `Unit Tests` - fast tests of individual classes, run by the build
* `Systems Tests - Simulated Hardware` - full start-up and instrument tests, using simulated (Debug) instruments
* `UITests` - GUI tests

Run them from MATLAB's Test Browser app, or with `runtests`. No hardware is needed: instruments connected with `ConnectionType="Debug"` produce simulated data.

## In this section

* [Build pipeline](build-pipeline.md) - how the toolbox, documentation and standalone application are built, and the GitHub Actions workflow
* [Code and comment conventions](code-conventions.md) - the class layout and help comment style used throughout the code, which the API reference is generated from
* [Error handling in the GUI](error-handling.md) - how errors in GUI callbacks and event listeners are caught and reported, and how to hook up new GUI code
