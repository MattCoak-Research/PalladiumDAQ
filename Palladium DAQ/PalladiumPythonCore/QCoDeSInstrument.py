# QCoDeSInstrument.py
"""Use a QCoDeS instrument driver in Palladium DAQ.

QCoDeS (https://microsoft.github.io/Qcodes/) is a Python data acquisition
framework with drivers for a lot of instruments. To use one, make a short
Python instrument for it - a few lines in a file in the PythonInstruments
folder of the user files folder, whose class name matches the file name:

    from PalladiumPythonCore.QCoDeSInstrument import QCoDeSInstrument

    class QCoDeS_Keithley2450(QCoDeSInstrument):
        DriverClass = "qcodes.instrument_drivers.Keithley.Keithley_2450.Keithley2450"
        Parameters = ["sense_function"]             # numeric parameters to record each tick
        Settings = {"source_function": "voltage"}   # settings to apply on connecting
        OfflineState = {"*LANG": "SCPI"}            # replies the fake instrument needs, for Debug mode

It then works like any Python instrument: the connection type and address are
chosen in the Instrument Settings panel, and its readings and settings go in
the data file. The driver's own validators check every setting.

Debug (simulation) mode runs the real driver against a fake connection (see
QCoDeSOffline), so it is only offered for drivers that can be created that
way. QCoDeS itself must be installed in the Python Palladium DAQ uses
(python -m pip install qcodes), which is set by PythonSettings.PythonExecutable
in Config.json.
"""
import itertools
import json
import os
import re
import sys

from PalladiumPythonCore.Instrument import Instrument, _require_package
from PalladiumPythonCore import QCoDeSOffline

_instance_counter = itertools.count(1)
_simulation_support_cache = {}      # driver class path -> (supported, reason)
_parameter_list_cache = {}          # driver class path -> parameters found with no instrument connected

# What the fake instrument needs to give some drivers, for them to be created with no instrument: the identity
# string (OfflineIDN) and replies to commands (OfflineState). Drivers not listed use the defaults.
KNOWN_OFFLINE_SETTINGS = {
    "qcodes.instrument_drivers.Keithley.Keithley_2450.Keithley2450":
        dict(idn="Keithley Instruments,MODEL 2450,0001,1.0", state={"*LANG": "SCPI"}),
}


class QCoDeSInstrument(Instrument):
    """A Palladium DAQ instrument that uses a QCoDeS driver. Subclass it and set the class attributes below."""

    # --- Set by the subclass ---
    DriverClass = ""        # Dotted path of the QCoDeS driver class
    Parameters = []         # Names of the numeric parameters to record in each reading (see QCoDeSOffline.list_parameters)
    Settings = {}           # {parameter name: value} applied after connecting, and recorded in the data file's header
    DriverKwargs = {}       # Extra keyword arguments for the driver's constructor, if it needs any
    OfflineIDN = None       # Identity string the fake instrument gives in Debug mode, for drivers that read the model from it (default: guessed)
    OfflineState = {}       # Replies the fake instrument gives in Debug mode, keyed by command without its "?"
    FullNameText = None     # Name shown in the GUI (default: made from the driver class)

    def __init__(self):
        super().__init__()
        self._qcodes_instrument = None      # The QCoDeS driver object, while connected or simulating
        self._parameters = {}               # Its parameters by name
        self._idn = {}
        self.SimulationProblem = ""         # Why Debug mode isn't offered, if it isn't
        short = (self.DriverClass or type(self).__name__).rsplit(".", 1)[-1]
        self.Name = short

    # ------------------------------------------------------------------ names
    @property
    def FullName(self):
        """Descriptive name, shown in the GUI."""
        if self.FullNameText:
            return self.FullNameText
        return "QCoDeS " + (self.DriverClass or type(self).__name__).rsplit(".", 1)[-1]

    # ------------------------------------------------------------- simulation
    @property
    def SupportsSimulation(self):
        """True if Debug mode can be used: the driver can be created against a fake instrument.

        Found out by trying, once per driver, and remembered. Set
        SupportsSimulation = True or False as a class attribute to skip the test.
        The reason, if it can't, is in SimulationProblem."""
        key = self.DriverClass
        if key not in _simulation_support_cache:
            _simulation_support_cache[key] = self._test_simulation()
        supported, reason = _simulation_support_cache[key]
        self.SimulationProblem = reason
        return supported

    def _test_simulation(self):
        """Try creating the driver offline: (True, "") if it works, else (False, why not)."""
        try:
            _require_package("qcodes", "qcodes", "A QCoDeS instrument")
            instrument, _ = QCoDeSOffline.create_driver(
                QCoDeSOffline.load_class(self.DriverClass), self._new_qcodes_name(),
                idn=self.OfflineIDN, state=self.OfflineState, driver_kwargs=self.DriverKwargs)
            instrument.close()
            return True, ""
        except Exception as e:
            return False, f"{self.DriverClass} can't be created without an instrument ({type(e).__name__}: {e})"

    @property
    def SimulationMode(self):
        return self._simulation_mode

    @SimulationMode.setter
    def SimulationMode(self, val):
        val = bool(val)
        if val:
            self._start_simulation()
        self._simulation_mode = val

    def _start_simulation(self):
        """Create the driver against a fake instrument (if that hasn't been done) and apply the settings."""
        if self._qcodes_instrument is not None:
            return
        _require_package("qcodes", "qcodes", "A QCoDeS instrument")
        try:
            instrument, handle = QCoDeSOffline.create_driver(
                QCoDeSOffline.load_class(self.DriverClass), self._new_qcodes_name(),
                idn=self.OfflineIDN, state=self.OfflineState, driver_kwargs=self.DriverKwargs)
        except Exception as e:
            raise RuntimeError(f"Debug mode isn't possible for {self.DriverClass}: it can't be created without an instrument "
                               f"({type(e).__name__}: {e}). Connect to the real instrument instead.") from e
        QCoDeSOffline.mock_parameters(instrument)
        self._idn = dict(zip(("vendor", "model", "serial", "firmware"), [s.strip() for s in handle.idn.split(",")] + [""] * 4))
        self._adopt(instrument)

    # ------------------------------------------------------------- connecting
    def connectGPIB(self, board_index, gpib_address, timeout):
        self._connect(f"GPIB{int(board_index)}::{int(gpib_address)}::INSTR", self._setting("GPIB_Timeout", timeout))

    def connectVISA(self, visa_address):
        self._connect(str(visa_address), self._setting("GPIB_Timeout", 10))

    def connectUSB(self, visa_address=None):
        address = visa_address if visa_address else self.VISA_Address
        if not address:
            raise RuntimeError("connectUSB: No VISA_Address available to open USB device.")
        self.connectVISA(address)

    def connectTCPIP(self, ip, port):
        self._connect(f"TCPIP0::{ip}::{int(port)}::SOCKET", self._setting("GPIB_Timeout", 10))

    def connectSerial(self, port):
        port = str(port)
        match = re.fullmatch(r"COM(\d+)", port, flags=re.I)
        resource = f"ASRL{match.group(1)}::INSTR" if match else f"ASRL{port}::INSTR"
        self._connect(resource, self._setting("GPIB_Timeout", 10), serial=True)

    def _connect(self, address, timeout, serial=False):
        """Create the QCoDeS driver on a VISA address, then apply the timeout, settings and so on."""
        _require_package("qcodes", "qcodes", "A QCoDeS instrument")
        driver_class = QCoDeSOffline.load_class(self.DriverClass)
        try:
            instrument = driver_class(self._new_qcodes_name(), address, **self.DriverKwargs)
        except Exception as e:
            raise RuntimeError(f"Connecting to {self.DriverClass} at {address} failed: {e}") from e
        try:
            if "timeout" in instrument.parameters:
                instrument.timeout(float(timeout))
            terminators = self._setting("GPIB_Terminators")
            if terminators:
                instrument.visa_handle.read_termination = list(terminators)[0]
                instrument.visa_handle.write_termination = list(terminators)[-1]
            if serial:
                self._apply_serial_settings(instrument.visa_handle)
            self.DeviceHandle = instrument.visa_handle
            try:
                idn = instrument.get_idn()
                self._idn = {k: str(v) for k, v in idn.items()}
            except Exception:
                self._idn = {}
        except Exception:
            instrument.close()
            self.DeviceHandle = None
            raise
        self._adopt(instrument)     # closes the instrument itself if the parameters or settings are wrong

    def _apply_serial_settings(self, handle):
        """Set a serial VISA resource's baud rate, data bits, parity and stop bits from ConnectionSettings."""
        settings = self._setting("SerialSettings", {})
        if not settings:
            return
        from pyvisa import constants
        get = (lambda k, d: settings.get(k, d)) if isinstance(settings, dict) else (lambda k, d: getattr(settings, k, d))
        handle.baud_rate = int(get("BaudRate", 9600))
        handle.data_bits = int(get("DataBits", 8))
        handle.parity = {"N": constants.Parity.none, "E": constants.Parity.even, "O": constants.Parity.odd,
                         "M": constants.Parity.mark, "S": constants.Parity.space}[str(get("Parity", "N"))]
        handle.stop_bits = {1.0: constants.StopBits.one, 1.5: constants.StopBits.one_and_a_half,
                            2.0: constants.StopBits.two}[float(get("StopBits", 1))]

    def _adopt(self, instrument):
        """Keep the connected (or simulated) driver, check the chosen parameters exist, and apply the settings."""
        self._qcodes_instrument = instrument
        self._parameters = dict(QCoDeSOffline.walk_parameters(instrument))
        try:
            for name in self.Parameters:
                if name not in self._parameters:
                    raise ValueError(self._unknown_parameter_message(name))
                if not hasattr(self._parameters[name], "get"):
                    raise ValueError(f"Parameter '{name}' of {self.DriverClass} can't be read, so can't be recorded.")
            for name, value in self.Settings.items():
                self._parameter(name)(value)
        except Exception:
            self.close()    # Palladium doesn't close an instrument that failed to connect, and QCoDeS keeps its name until it is closed
            raise

    def close(self):
        """Close the QCoDeS driver (its connection, and its name) - called when measurements stop."""
        instrument, self._qcodes_instrument = self._qcodes_instrument, None
        self._parameters = {}
        self.DeviceHandle = None
        self._simulation_mode = False
        if instrument is not None:
            instrument.close()

    # ---------------------------------------------------------------- reading
    def GetHeaders(self):
        """Column headers and units, one per recorded parameter: the parameter's name and its unit."""
        self._require_driver()
        headers, units = [], []
        for name in self.Parameters:
            unit = getattr(self._parameters[name], "unit", "") or "arb"
            headers.append(f"{name}_{unit}")
            units.append(unit)
        return (headers, units)

    def Measure(self):
        """Read each recorded parameter. In simulation mode they have a little noise, so the data looks alive."""
        self._require_driver()
        row = []
        for name in self.Parameters:
            value = self._parameters[name]()
            try:
                number = float(value)
            except (TypeError, ValueError):
                raise ValueError(f"Parameter '{name}' returned {value!r}, which isn't a number. "
                                 f"Only numeric parameters can be recorded - non-numeric settings can go in Settings.") from None
            row.append(QCoDeSOffline.simulated_reading(number) if self.SimulationMode else number)
        return row

    def collect_metadata(self):
        """The instrument's identity and the settings, as read back from it, for the data file's header."""
        if self._qcodes_instrument is None:
            return None
        metadata = {"Driver": self.DriverClass.rsplit(".", 1)[-1]}
        for key in ("model", "firmware"):
            if self._idn.get(key):
                metadata[key.capitalize()] = self._idn[key]
        for name in self.Settings:
            value = self._parameter(name)()
            metadata[name] = value if isinstance(value, (int, float, str)) else str(value)
        return metadata

    # ---------------------------------------------------------------- helpers
    def parameter(self, name):
        """A parameter of the connected driver, for a subclass's own methods: parameter("source_voltage")(1.5) sets it."""
        self._require_driver()
        return self._parameter(name)

    def _parameter(self, name):
        if name not in self._parameters:
            raise KeyError(self._unknown_parameter_message(name))
        return self._parameters[name]

    def _unknown_parameter_message(self, name):
        import difflib

        names = sorted(n for n in self._parameters if not n.startswith("_"))     # The underscore ones are the driver's internals
        close = difflib.get_close_matches(name, names, n=3)
        suggestion = f" Did you mean: {', '.join(close)}?" if close else ""
        shown = ", ".join(names[:40]) + (f", ... ({len(names)} in all)" if len(names) > 40 else "")
        return f"{self.DriverClass} has no parameter '{name}'.{suggestion} Its parameters: {shown}"

    def _require_driver(self):
        if self._qcodes_instrument is None:
            raise AssertionError(f"The QCoDeS driver isn't connected yet ({self._describe()})")

    @staticmethod
    def _new_qcodes_name():
        """A QCoDeS instrument name that isn't in use - QCoDeS needs every instrument's name to be unique."""
        from qcodes.instrument import Instrument

        while True:
            name = f"palladium_{next(_instance_counter)}"
            if not Instrument.exist(name):
                return name


    # ------------------------------------------------------------ parameters
    def available_parameters_json(self):
        """The driver's parameters, as JSON: a list of dicts with name, label, unit, gettable, settable, vals.

        From the connected driver if there is one, otherwise found with no instrument connected - which
        only works for drivers that can be simulated, so it is "[]" for the others until they have been
        connected once (the list is then kept)."""
        if self._qcodes_instrument is not None:
            listing = self._describe_parameters(self._parameters)
            _parameter_list_cache[self.DriverClass] = listing
        elif self.DriverClass in _parameter_list_cache:
            listing = _parameter_list_cache[self.DriverClass]
        elif self.SupportsSimulation:
            listing = QCoDeSOffline.list_parameters(self.DriverClass, idn=self.OfflineIDN, state=self.OfflineState,
                                                    driver_kwargs=self.DriverKwargs)
            _parameter_list_cache[self.DriverClass] = listing
        else:
            listing = []
        return json.dumps(listing, default=str)

    @staticmethod
    def _describe_parameters(parameters):
        return [dict(name=name, label=getattr(p, "label", name), unit=getattr(p, "unit", ""),
                     gettable=hasattr(p, "get"), settable=hasattr(p, "set"),
                     vals=repr(p.vals) if getattr(p, "vals", None) else "")
                for name, p in parameters.items()]


class QCoDeSGeneric(QCoDeSInstrument):
    """A QCoDeS instrument that Palladium DAQ configures while it runs, instead of by a subclass's attributes.

    Used for the QCoDeS drivers in Palladium's instrument list: Palladium DAQ calls configure with the
    driver the user chose, then set_parameters_json and set_settings_json with the parameters they picked."""

    def configure(self, driver_class, extra_path=""):
        """Choose the driver. extra_path is a folder to put on Python's path to import it from (a driver
        the user put in their QCoDeS Drivers folder), or "" for none."""
        if extra_path and extra_path not in sys.path:
            sys.path.insert(0, extra_path)
        self.DriverClass = driver_class
        self.Name = driver_class.rsplit(".", 1)[-1]
        known = KNOWN_OFFLINE_SETTINGS.get(driver_class, {})
        self.OfflineIDN = known.get("idn")
        self.OfflineState = known.get("state", {})
        self.Parameters = []
        self.Settings = {}

    def set_parameters_json(self, text):
        """The parameters to record in each reading, as a JSON list of names ("" for none)."""
        names = json.loads(text) if text else []
        if isinstance(names, str):      # MATLAB writes a single name as plain text, not a list of one
            names = [names]
        self.Parameters = [str(n) for n in names]

    def set_settings_json(self, text):
        """The settings to apply on connecting, as a JSON object of parameter name: value ("" for none)."""
        settings = json.loads(text) if text else {}
        if not isinstance(settings, dict):
            raise ValueError("Settings must be a JSON object, such as {\"source_function\": \"voltage\"}")
        self.Settings = settings
