# CoakView

## Description
This is a modular framework for laboratory data acquisition. A library of Instrument files (basically drivers) is included for the hardware added so far, and adding more based on the InstrumentTemplate class is straightforward. A default GUI is included, but alternatives can easily be added and switched to, and in fact the programme can be run without a GUI at all (though graphing isn't so useful then).

## System Requirements
To run CoakView MATLAB version 2025b is required with the Instrument Control Toolbox installed.


## Installation
* Clone the repository to your local PC or download and extract the code zip file.
* Open MATLAB and navigate to the main CoakView repository or downloaded folder.

## Open CoakView Project
* CoakView is stored in a MATLAB project.
* Either double click the CoakView.prj file or use the 'Open Project' option to open the project.
* The necessary folders will be added to the MATLAB path when the project is opened (and removed again when the project is closed).

## Run CoakView
* Type `CoakView` in the command window. 
* Optional parameters and presets can be included, like `CoakView("Preset", "ProbeStation");`

## Run Tests
* Test files are stored in the CoakView/tests folder.
* Open the **Test Browser** App and use this to select which of the test files to run.
* Run the tests using the **Run** button.
* To run individual tests in a test file:
    * Right click on the required test in the Test Browser
    * Select 'Run Test' from the dropdown menu
* Test results will be shown in the Test Browser dialog.

## License
This project is open source, with MIT license - see included License file.

## Project status
This codebase is in beta testing and still being expanded with new features.
