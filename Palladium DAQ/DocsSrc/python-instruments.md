# Python instruments

Instrument drivers can also be written in Python - useful when an instrument comes with a Python library, or when Python is more familiar than MATLAB. A Python instrument appears in Palladium DAQ alongside the MATLAB ones: in the Instruments list, in [Presets](presets-and-config.md), and in its data files.

## Requirements

**In the standalone application on Windows, there is nothing to set up.** It comes with its own copy of Python (version 3.14), with the packages Python instruments need: `pyvisa`, `pyvisa-py` and `pyserial`. It is installed in the `Python` folder of the installation's `application` folder, and doesn't affect any other Python on the computer.

**In the MATLAB toolbox, and the standalone application on Mac and Linux,** Palladium DAQ uses the Python that MATLAB finds (check it with `pyenv` in MATLAB). It needs:

* Python 3.10 to 3.14 - the versions MATLAB R2026b supports (see [Python versions supported by each MATLAB release](https://www.mathworks.com/support/requirements/python-compatibility.html)). Install it from [python.org](https://www.python.org/downloads/); on Windows, tick **Add python.exe to PATH** in the installer. See also MathWorks' [Configure Your System to Use Python](https://www.mathworks.com/help/matlab/matlab_external/install-supported-python-implementation.html)
* The packages `pyvisa` (for GPIB, VISA and USB connections) and `pyserial` (for serial): `python -m pip install pyvisa pyserial` (`python3` on Mac and Linux). Ethernet and simulated (Debug) instruments work without them - the packages are only loaded when an instrument connects in a way that needs them, and a missing one gives an error saying how to install it

GPIB and VISA connections also need a VISA library for pyvisa to use: NI-VISA, if it is installed, or else the pure-Python `pyvisa-py` (which the standalone application includes; install it elsewhere with `python -m pip install pyvisa-py`). pyvisa-py handles Ethernet (TCP/IP) and serial instruments by itself, but GPIB cards need their manufacturer's driver, such as NI-VISA. See [how pyvisa finds a VISA library](https://pyvisa.readthedocs.io/en/latest/introduction/getting.html).

### Using a different Python

To use a particular Python instead - for example one with extra packages that your instruments need - set `PythonExecutable` in the `PythonSettings` section of [Config.json](presets-and-config.md) to the path of its executable, such as `C:\Users\<you>\AppData\Local\Programs\Python\Python314\python.exe`, and restart Palladium DAQ. In MATLAB, this only works if Python hasn't been loaded in the MATLAB session yet - restart MATLAB if it has. The standalone application's own Python has no `pip`, so to add packages, use your own Python this way.

### If Python can't be used

Python is optional: if there is no usable Python, Palladium DAQ starts without Python instruments - everything else works normally. When it has loaded, it shows a warning saying what is wrong (no Python found, a Python that MATLAB can't load, or missing packages) and how to fix it, with links. Click **Don't show this again** to stop the warning; this sets `SuppressPythonSetupWarning` in the `WarningSettings` section of Config.json to `true` - set it back to `false` to see the warning again. The warning is also written to the log.

## Writing one

A Python instrument is a class in its own `.py` file, in the `PythonInstruments` folder of your [user files folder](installation.md). The **class name must match the file name** - `MyDMM.py` contains `class MyDMM` - and it inherits from Palladium DAQ's Python `Instrument` base class.

To start one, copy `TemplatePythonInstrument.py`, which Palladium DAQ puts in that folder, and rename the copy and the class inside it. The template itself is never listed as an instrument. A short example:

```python
import random
from PalladiumPythonCore.Instrument import Instrument


class MyDMM(Instrument):
    """A digital multimeter, read over GPIB or VISA."""

    def __init__(self):
        super().__init__()
        self.Name = "MyDMM"

    @property
    def FullName(self):
        return "My Python DMM"

    def GetHeaders(self):
        return (["Voltage_V"], ["V"])

    def Measure(self):
        if self.SimulationMode:
            return [1.5 + random.gauss(0, 0.01)]
        return [self.query_double("MEAS:VOLT:DC?")]
```

The class must:

* Work with no constructor arguments, and set `self.Name` - a short name, used to name the instrument (`MyDMM_1`) and its data columns
* Define `FullName`, a descriptive name shown in the GUI
* Implement `GetHeaders()`, returning a tuple of two lists: the column headers and their units. Palladium DAQ adds the instrument's name in front of each header, so `Voltage_V` becomes `MyDMM_1 - Voltage_V`
* Implement `Measure()`, returning a list with one number for each header, in the same order

### Connecting and simulating

The connection type and address are chosen in the Instrument Settings panel, as for any instrument. When measurements start, the base class opens the connection and stores it in `self.DeviceHandle`: a `pyvisa` resource for GPIB, VISA and USB; a `socket` for Ethernet; or a `serial.Serial` port for serial.

The base class has methods for talking to the instrument, which work with every connection type:

| Method | What it does |
| --- | --- |
| `self.write_command(command)` | Sends a command |
| `self.query_string(command)` | Sends a query and returns the reply as text |
| `self.query_double(command)` | Sends a query and returns the reply as a number |
| `self.read_string()` | Reads a reply |

Replies are returned without their line ending. On Ethernet and serial connections, commands are sent with a line ending, `self.WriteTermination`, and replies are read up to one, `self.ReadTermination` - both `"\n"` by default. If your instrument uses another, such as `"\r\n"`, set them in your class's `__init__`, after calling `super().__init__()`. GPIB, VISA and USB connections use pyvisa's own line-ending settings. For anything these methods don't cover - such as reading a large block of data - use `self.DeviceHandle` directly.

With the connection type set to **Debug**, `self.SimulationMode` is `True` and no connection is made. `Measure` should then return realistic made-up readings, as above, so the instrument can be tried without hardware.

### Recording the setup

To record the instrument's settings in the [data file's header](data-files.md), override `collect_metadata()` to return a dictionary of settings.

## Using it

Python instruments are loaded when Palladium DAQ starts - restart it after adding or changing one. It then appears in the Instruments list, and can be added like any other instrument, from the GUI, a Preset (`"Type": "MyDMM"`) or a script:

```matlab
pd = Palladium();
dmm = pd.AddInstrument("MyDMM", ConnectionType="Debug"); 
```

If a Python instrument has the same name as a MATLAB one, the Python one is used. A file that fails to import is skipped, with a warning in the Command Window giving the Python error.

## Limitations

Python instruments are simpler than MATLAB ones:

* Only `Name`, the connection type and the connection addresses appear in the Instrument Settings panel - other settings must be set in the Python class
* They cannot offer Instrument Controls, and their methods are not available as [Sequence](sequences.md) commands

For any of these, write the driver in MATLAB - see [Writing an instrument driver](writing-instruments.md).
