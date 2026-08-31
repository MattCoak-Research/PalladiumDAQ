# Palladium Data Acquisition

## Description
This is a modular framework for laboratory data acquisition. A library of Instrument files (basically drivers) is included for the hardware added so far, and adding more based on the InstrumentTemplate class is straightforward. A default GUI is included, but alternatives can easily be added and switched to, and in fact the programme can be run without a GUI at all (though graphing isn't so useful then).

> [!CAUTION]
> This software is currently under active development and is not yet stable or feature complete

## System Requirements
PalladiumDAQ can be installed as a Toolbox inside a MATLAB environment (allows more customisation) or, on machines with no MATLAB licence, as a standalone programme.
 - To run PalladiumDAQ Toolbox Version, MATLAB version 2026a is required, with the Instrument Control Toolbox installed.
 - To run PalladiumDAQ Standalone Version, the MATLAB Runtime (2026a Update 4) is required. This is bundled with some installers (see Installation & Downloads sections) or can be downloaded from [Mathworks Downloads](https://uk.mathworks.com/products/compiler/matlab-runtime.html) (no MATLAB licence required).

## Download
Latest release download:
* [PalladiumDAQ.mltbx](https://github.com/MattCoak-Research/PalladiumDAQ/releases/latest/download/PalladiumDAQ.mltbx)

## Installation
* Toolbox version - search "Palladium" in MATLAB's built in Add On Explorer (Home -> Add-Ons -> Explore Add-Ons), select the entry and then click Add.

     <img width="320" alt="image" src="https://github.com/user-attachments/assets/f44b1e8a-c62a-4606-b733-86d9e69c07e6" />
     <img width="280" alt="image" src="https://github.com/user-attachments/assets/6d4d43a0-8904-4ef7-ab03-723bfb3c8602" />


* Toolbox version - manual install. Download the PalladiumDAQ.mltbx file in the Download section above. Double click the file to run (it will open via MATLAB) and it will install.

## Run PalladiumDAQ

### Toolbox Version
* Type 'Palladium;' in the command window. All other options below are not required in 99% of cases, just stop here.
* Optional parameters and presets can be included, like `Palladium(Preset = "Example");`
(Presets are .json files that automatically configure the programme on launch, i.e. adding certain Instruments, setting their IP Addresses etc. Default examples are found in the PalladiumPresets folder, and new ones can be added to this folder and then ran)
* If a reference is stored to the Palladium.m entry point when calling it / wrapper object, methods can then be called on that, just like a Preset does. For example, one could run: `pd = Palladium(); pd.AddInstrument("Keithley2000", ConnectionType="Debug"); pd.Start();`

### Standalone Version
* Launch the programme via the shortcut created on installation, or via the list of installed programmes on your computer.

## Customising and adding new functionality, new Instruments

### Presets
Presets are designed to streamline programme startup by removing configuration steps for a set of connected hardware that doesn't change, as well as programme-level settings. The original use case for this is a cryostat setup in a condensed matter physics lab - the temperature controllers, magnet power supplies etc do not change, and have various required and nice-to-have settings that can be configured (naming the various temperatures monitored to reflect the cryostat's cooling stages for example). It can also add graphing tabs and windows so a consistent set of graphical interfaces loads on startup with no manual clicks (display a new window showing the key cryostat temperatures plotted against time, to be viewed at all times on a second monitor for example).

An example Preset `example.json` is provided with the installation - .json files can be copied, renamed and edited in any text editor, or dragged into the MATLAB editor and worked on there, and - more simply - the state of the programme after manual configuration can be directly saved as a Preset.

## Development
A modest library of Instruments and Controls is included in the install, but biased towards the author's lab setup! New contributions are very welcome, either by email to m.j.coak@bham.ac.uk or through Pull Request.

New Instruments are simple to write, and Controls - while more powerful and generalised, and often including new GUI elements and therefore more complex - can be built based on the examples included with limited work. 

To write code for Palladium, clone the repository and navigate to it in MATLAB. It has a MATLAB Project - select the Project Tab and Open Project to locate the `Palladium.prj` file. This handles source control, deployment, path management etc all in one place.

### Run Tests
* Test files are stored in the Palladium DAQTtests folder.
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

