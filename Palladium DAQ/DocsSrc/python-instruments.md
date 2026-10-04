# Python instruments

Instrument drivers can also be written in Python - useful when an instrument comes with a Python library, or when Python is more familiar than MATLAB. A Python instrument appears in Palladium DAQ alongside the MATLAB ones: in the Instruments list, in [Presets](presets-and-config.md), and in its data files.

## Requirements

* Python, set up for use from MATLAB - see MathWorks' [Configure Your System to Use Python](https://www.mathworks.com/help/matlab/matlab_external/install-supported-python-implementation.html). Check it with `pyenv` in MATLAB
* The Python packages `pyvisa` (for GPIB and VISA connections) and `pyserial` (for serial), installed in that Python

## Writing one

A Python instrument is a class in its own `.py` file, in the `PythonInstruments` folder of your [user files folder](installation.md). The **class name must match the file name** - `MyDMM.py` contains `class MyDMM` - and it inherits from Palladium DAQ's Python `Instrument` base class:

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

For GPIB, VISA and USB connections, the base class's `self.query_double(command)` and `self.query_string(command)` send a query and return the reply. For Ethernet and serial connections, read and write through `self.DeviceHandle` directly.

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
