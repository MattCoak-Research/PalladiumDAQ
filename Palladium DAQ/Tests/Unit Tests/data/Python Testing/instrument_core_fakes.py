"""Stand-in connections and test scenarios for the communication helpers of
PalladiumPythonCore/Instrument.py (write_command, read_string, query_string,
query_double). Used by Tests/Unit Tests/PythonInstruments/test_PythonInstrumentCore.m.
No hardware, pyvisa or pyserial needed: Ethernet uses a real local socket pair,
and pyvisa and serial connections are replaced by the small classes below."""
import socket

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
