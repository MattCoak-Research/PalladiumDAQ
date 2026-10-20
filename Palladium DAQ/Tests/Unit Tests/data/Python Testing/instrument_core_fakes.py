"""Stand-in connections and test scenarios for PalladiumPythonCore/Instrument.py:
its communication helpers (write_command, read_string, query_string,
query_double) and its connect methods. Used by
Tests/Unit Tests/PythonInstruments/test_PythonInstrumentCore.m and
test_PythonInstrument.m. No hardware, pyvisa or pyserial needed: Ethernet uses
a real local socket pair, pyvisa and serial connections are replaced by the
small classes below, and install_fake_packages puts stand-in pyvisa and serial
modules in place for the connect methods to import."""
import socket
import sys
import types

from PalladiumPythonCore.Instrument import Instrument


class CoreTestInstrument(Instrument):
    """The smallest concrete instrument."""
    FullName = "Core Test Instrument"

    def GetHeaders(self):
        return (["V"], ["V"])

    def Measure(self):
        return [0.0]


class FakeVisa:
    """Behaves like a pyvisa resource: write, read and query, with text."""
    def __init__(self, replies):
        self.written = []
        self.replies = list(replies)

    def write(self, command):
        self.written.append(command)

    def read(self):
        return self.replies.pop(0)

    def query(self, command):
        self.write(command)
        return self.read()


class FakeSerial:
    """Behaves like a pyserial port: write and read_until, with bytes."""
    def __init__(self, replies):
        self.written = []
        self.buffer = "".join(replies).encode()

    def write(self, data):
        self.written.append(data)

    def read_until(self, expected=b"\n"):
        end = self.buffer.find(expected)
        end = len(self.buffer) if end < 0 else end + len(expected)
        chunk, self.buffer = self.buffer[:end], self.buffer[end:]
        return chunk


def instrument(handle=None, simulation=False):
    inst = CoreTestInstrument()
    inst.DeviceHandle = handle
    inst.SimulationMode = simulation
    return inst


def socket_query_double(reply):
    """query_double over Ethernet: returns the value read and what the instrument received."""
    ours, theirs = socket.socketpair()
    try:
        theirs.sendall(reply.encode())
        value = instrument(ours).query_double("MEAS?")
        received = theirs.recv(100).decode()
        return {"value": value, "received": received}
    finally:
        ours.close()
        theirs.close()


def socket_custom_terminators(reply):
    """write_command and read_string over Ethernet, with \\r\\n terminators."""
    ours, theirs = socket.socketpair()
    try:
        inst = instrument(ours)
        inst.WriteTermination = "\r\n"
        inst.ReadTermination = "\r\n"
        inst.write_command("OUTP ON")
        theirs.sendall(reply.encode())
        read = inst.read_string()
        received = theirs.recv(100).decode()
        return {"read": read, "received": received}
    finally:
        ours.close()
        theirs.close()


def visa_scenario(replies):
    """write_command, query_string and query_double over a pyvisa-like connection."""
    handle = FakeVisa(replies)
    inst = instrument(handle)
    inst.write_command("*RST")
    text = inst.query_string("*IDN?")
    value = inst.query_double("MEAS?")
    return {"text": text, "value": value, "written": " | ".join(handle.written)}


def serial_scenario(replies):
    """write_command, query_string and query_double over a serial-like connection."""
    handle = FakeSerial(replies)
    inst = instrument(handle)
    inst.write_command("*RST")
    text = inst.query_string("*IDN?")
    value = inst.query_double("MEAS?")
    return {"text": text, "value": value, "written": " | ".join(w.decode() for w in handle.written)}


def simulation_scenario():
    """Simulation mode: no connection needed, made-up replies."""
    inst = instrument(None, simulation=True)
    inst.write_command("*RST")
    return {"text": inst.query_string("*IDN?"), "read": inst.read_string(), "value": inst.query_double("MEAS?")}


def query_double_non_number():
    """query_double when the reply isn't a number - raises ValueError."""
    instrument(FakeVisa(["OVERLOAD"])).query_double("MEAS?")


def not_connected():
    """A helper with no connection - raises AssertionError."""
    instrument(None).query_string("*IDN?")


def unsupported_connection():
    """A connection object of an unknown kind - raises RuntimeError."""
    instrument(object()).write_command("*RST")


# ---- Stand-in pyvisa and pyserial packages, for the connect methods ----

class FakeVisaResource:
    """What the fake pyvisa ResourceManager opens: records its name and settings."""
    def __init__(self, resource_name):
        self.resource_name = resource_name
        self.timeout = None
        self.read_termination = None
        self.write_termination = None
        self.closed = False

    def query(self, command):
        return "0"

    def close(self):
        self.closed = True


class FakeResourceManager:
    def open_resource(self, resource_name):
        return FakeVisaResource(resource_name)


class FakeSerialPort:
    """What the fake serial.Serial makes: records the settings it was opened with."""
    def __init__(self, **kwargs):
        self.settings = dict(kwargs)
        self.closed = False

    def read_until(self, expected=b"\n"):
        return b""

    def close(self):
        self.closed = True


_saved_modules = {}


def install_fake_packages():
    """Put stand-in pyvisa and serial modules in sys.modules, so the connect methods import them."""
    for name in ("pyvisa", "serial"):
        if name not in _saved_modules:
            _saved_modules[name] = sys.modules.get(name)
    fake_pyvisa = types.ModuleType("pyvisa")
    fake_pyvisa.ResourceManager = FakeResourceManager
    fake_serial = types.ModuleType("serial")
    fake_serial.Serial = FakeSerialPort
    sys.modules["pyvisa"] = fake_pyvisa
    sys.modules["serial"] = fake_serial


def restore_packages():
    """Put the real pyvisa and serial modules back (or none, if they weren't imported)."""
    for name, module in _saved_modules.items():
        if module is None:
            sys.modules.pop(name, None)
        else:
            sys.modules[name] = module
    _saved_modules.clear()


def gpib_connect_without_settings(timeout):
    """connectGPIB with no ConnectionSettings: the timeout it is given must still be applied."""
    install_fake_packages()
    try:
        inst = instrument()
        inst.connectGPIB(0, 7, timeout)
        return {"resource": inst.DeviceHandle.resource_name, "timeout": inst.DeviceHandle.timeout}
    finally:
        restore_packages()


def usb_connect(visa_address):
    """connectUSB given a VISA address - it used to need a VISA_Address attribute nothing set."""
    install_fake_packages()
    try:
        inst = instrument()
        inst.connectUSB(visa_address)
        return inst.DeviceHandle.resource_name
    finally:
        restore_packages()


def default_name():
    """Name of an instrument that doesn't set one - its class name (reading it used to fail)."""
    return CoreTestInstrument().Name


def serial_connect(settings=None):
    """connectSerial with the driver's own ConnectionSettings (or none): what the port was opened with."""
    install_fake_packages()
    try:
        inst = instrument()
        if settings is not None:
            inst.ConnectionSettings = dict(settings)
        inst.connectSerial("COM9")
        return inst.DeviceHandle.settings
    finally:
        restore_packages()


def gpib_connect_with_driver_settings():
    """connectGPIB when the driver set its own terminators and timeout: those win over Palladium's timeout."""
    install_fake_packages()
    try:
        inst = instrument()
        inst.ConnectionSettings = {"GPIB_Terminators": ["\r\n", "\n"], "GPIB_Timeout": 2}
        inst.connectGPIB(0, 3, 10)
        h = inst.DeviceHandle
        return {"read": h.read_termination, "write": h.write_termination, "timeout": h.timeout}
    finally:
        restore_packages()


def instrument_with_serial_settings(baud_rate):
    """An instrument whose driver set its own serial settings, for wrapping in MATLAB's PythonInstrument."""
    inst = instrument()
    inst.ConnectionSettings = {"SerialSettings": {"BaudRate": int(baud_rate), "Parity": "E", "StopBits": 2}}
    return inst
