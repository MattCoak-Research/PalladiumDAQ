# QCoDeSOffline.py
"""Run a QCoDeS driver with no instrument connected, for QCoDeSInstrument's simulation (Debug) mode.

The driver is created against a fake VISA connection that answers every query
with something plausible, and its parameters are then replaced by a simple
in-memory store: setting one stores the value (after the driver's own
validators have checked it), and reading it gives the value back, starting
from a default drawn from the parameter's allowed range.

Not every driver can be created like this - some read the model or firmware
from the instrument's replies, and reject the made-up ones. QCoDeSInstrument
offers its simulation mode only for the drivers that can.

qcodes is imported only inside the functions that need it, so that a module
importing this one works without qcodes installed.
"""
import importlib
import inspect
import random


class _FakeVisaLibrary:
    """Stands in for a pyvisa VisaLibrary (QCoDeS only looks at its class name)."""


class FakeVisaHandle:
    """A tolerant stand-in for a pyvisa message-based resource.

    Writing "FREQ 5" stores "5" under FREQ, and querying "FREQ?" returns it; any
    other query returns "0". "*IDN?" returns the identity string given. Anything
    else a driver does to the handle (set_visa_attribute and so on) does nothing.
    """

    DEFAULT_IDN = "Fake,Model,0001,1.0"

    def __init__(self, resource_name="GPIB0::1::INSTR", idn=DEFAULT_IDN, state=None):
        self.resource_name = resource_name
        self.idn = idn
        self.session = 0
        self.timeout = 2000
        self.read_termination = "\n"
        self.write_termination = "\n"
        self.visalib = _FakeVisaLibrary()
        self.state = dict(state or {})   # canned replies, keyed by command without its "?", e.g. {"*LANG": "SCPI"}

    def write(self, cmd):
        for part in cmd.split(";"):
            key, _, arg = part.strip().partition(" ")
            if key:
                self.state[key.upper().rstrip("?")] = arg.strip()
        return len(cmd)

    def query(self, cmd):
        key = cmd.strip().split(";")[-1].strip().split(" ")[0].upper()
        if key in ("*IDN?", "ID?"):
            return self.idn
        return self.state.get(key.rstrip("?"), "0")

    def read(self, *args, **kwargs):
        return "0"

    def read_raw(self, *args, **kwargs):
        return b"0\n"

    def write_raw(self, cmd, *args, **kwargs):
        return self.write(cmd.decode() if isinstance(cmd, bytes) else cmd)

    def clear(self):
        pass

    def flush(self, *args, **kwargs):
        pass

    def close(self):
        pass

    def __getattr__(self, name):
        # Anything else a driver pokes at is a no-op
        if name.startswith("__"):
            raise AttributeError(name)
        return lambda *args, **kwargs: 0


def load_class(class_path):
    """The class at a dotted path, e.g. "qcodes.instrument_drivers.Keithley.Keithley_2450.Keithley2450"."""
    module_name, _, class_name = class_path.rpartition(".")
    return getattr(importlib.import_module(module_name), class_name)


def walk_parameters(obj, prefix=""):
    """Yield (name, parameter) for an instrument and its submodules and channels.

    A submodule's parameters are named with the submodule's name in front, e.g.
    "A_temperature" (channel A of a Lakeshore's temperature); the members of a
    list of channels are numbered from 0, e.g. "ch0_voltage".
    """
    for name, parameter in getattr(obj, "parameters", {}).items():
        yield prefix + name, parameter
    for submodule_name, submodule in getattr(obj, "submodules", {}).items():
        if hasattr(submodule, "parameters"):
            yield from walk_parameters(submodule, prefix + submodule_name + "_")
        else:
            try:
                for i, channel in enumerate(submodule):
                    yield from walk_parameters(channel, f"{prefix}{submodule_name}{i}_")
            except TypeError:
                pass


def idn_guesses(driver_class):
    """IDN strings to try for a driver, guessing its model from its class and module names."""
    import re

    parts = driver_class.__module__.split(".")
    skip = ("qcodes", "qcodes_contrib_drivers", "instrument_drivers", "drivers", "instrument")
    vendor = next((p for p in parts if p not in skip), "Fake")
    models = []
    for name in (driver_class.__name__, parts[-1], parts[-1].split("_")[-1]):
        for candidate in (re.sub("^" + re.escape(vendor), "", name, flags=re.I).lstrip("_ "), name):
            if candidate and candidate not in models:
                models.append(candidate)
    models.append("Unknown")
    return [f"{vendor},{model},0001,1.0" for model in models]


def create_driver(driver_class, name, address="GPIB0::1::INSTR", idn=None, state=None, driver_kwargs=None):
    """Create a QCoDeS driver against a fake VISA connection, returning (instrument, fake handle).

    A driver that isn't VISA-based is created as normal. With no idn given, the
    fake IDN is tried first, then guesses of the model from the class's name;
    the first that the driver accepts is used.

    Raises the driver's own error if none works.
    """
    from qcodes.instrument import Instrument
    from qcodes.instrument.visa import VisaInstrument

    driver_kwargs = driver_kwargs or {}
    is_visa = "address" in inspect.signature(driver_class.__init__).parameters
    candidates = [idn] if idn else [FakeVisaHandle.DEFAULT_IDN] + idn_guesses(driver_class)
    first_error = None
    for candidate in candidates:
        handle = FakeVisaHandle(address, candidate, state)
        original = VisaInstrument._open_resource
        VisaInstrument._open_resource = lambda self, addr, visalib, h=handle: h
        try:
            if is_visa:
                return driver_class(name, address, **driver_kwargs), handle
            return driver_class(name, **driver_kwargs), handle
        except Exception as e:
            first_error = first_error or e
            # A failed constructor can leave its name registered
            try:
                Instrument.find_instrument(name).close()
            except Exception:
                pass
        finally:
            VisaInstrument._open_resource = original
    raise first_error


def _default_for(parameter):
    """A starting value for a mocked parameter, from its validator."""
    import qcodes.validators as vals

    validator = getattr(parameter, "vals", None)
    mapping = getattr(parameter, "val_mapping", None)
    if mapping:
        return next(iter(mapping))
    try:
        if isinstance(validator, vals.Numbers):
            low, high = validator.valid_values[0], validator.valid_values[1]
            low = 0 if low == float("-inf") else low
            high = low + 1 if high == float("inf") else high
            return (low + high) / 2
        if isinstance(validator, vals.Ints):
            return int(validator.valid_values[0])
        if isinstance(validator, vals.Enum):
            return next(iter(validator._values))
        if isinstance(validator, vals.Bool):
            return False
        if isinstance(validator, vals.Strings):
            return ""
    except Exception:
        pass
    return 0.0


def mock_parameters(instrument):
    """Replace each parameter's get and set with an in-memory store.

    Setting a value still runs the parameter's validator, so a value the real
    driver would reject is rejected here too. get and set are replaced on the
    parameter itself, because some parameter types (group parameters) bind their
    wrappers when they are created. Returns the number of parameters mocked.
    """
    count = 0
    for _, parameter in walk_parameters(instrument):
        store = {"value": _default_for(parameter)}
        try:
            if hasattr(parameter, "get"):
                parameter.get = lambda s=store: s["value"]
            if hasattr(parameter, "set"):
                def _set(value, s=store, p=parameter):
                    p.validate(value)
                    s["value"] = value
                parameter.set = _set
            count += 1
        except Exception:
            pass
    return count


def simulated_reading(value):
    """A mocked parameter's value with a little noise, so simulated data looks alive.

    The noise is about 1% of the value, or 0.01 if it is 0.
    """
    value = float(value)
    return value + random.gauss(0, abs(value) * 0.01 if value else 0.01)


def list_parameters(class_path, idn=None, state=None, driver_kwargs=None):
    """The parameters of a QCoDeS driver, found with no instrument connected - to choose what to record.

    Returns a list of dicts with name, label, unit, gettable, settable and vals
    (the validator, as text). The names are those to put in a QCoDeSInstrument's
    Parameters and Settings.
    """
    instrument, _ = create_driver(load_class(class_path), "palladium_listing", idn=idn, state=state, driver_kwargs=driver_kwargs)
    try:
        return [dict(name=name,
                     label=getattr(p, "label", name),
                     unit=getattr(p, "unit", ""),
                     gettable=hasattr(p, "get"),
                     settable=hasattr(p, "set"),
                     vals=repr(p.vals) if getattr(p, "vals", None) else "")
                for name, p in walk_parameters(instrument)]
    finally:
        try:
            instrument.close()
        except Exception:
            pass
