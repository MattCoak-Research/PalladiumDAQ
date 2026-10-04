# Instrument.py
from abc import ABC, abstractmethod
from typing import Optional, Any
import importlib
import random
import socket
import sys
import time

# pyvisa and pyserial are imported only by the connect methods that use them
# (see _require_package), so that instruments using other connections - or
# none, in simulation mode - work without them installed


def _require_package(module_name: str, pip_name: str, purpose: str):
    """Import and return an optional package, or raise an error saying how to install it."""
    try:
        return importlib.import_module(module_name)
    except ImportError as e:
        raise RuntimeError(
            f"{purpose} needs the Python package '{pip_name}', which isn't installed in the Python "
            f"Palladium DAQ uses ({sys.executable}). Install it with: \"{sys.executable}\" -m pip install {pip_name}"
        ) from e


class Instrument(ABC):
    """
    Abstract base class mirroring the MATLAB Instrument interface.
    Subclasses must implement the abstract properties Name and FullName,
    and the abstract methods GetHeaders() and Measure().
    """

    def __init__(self, *args, **kwargs):
        self._simulation_mode = False
        self.DeviceHandle: Optional[Any] = None
        self.OverrideConnectMethod = False
        # Line endings added to commands, and expected at the end of replies, on Ethernet
        # (socket) and serial connections. pyvisa resources use their own settings
        self.WriteTermination = "\n"
        self.ReadTermination = "\n"


    # Abstract properties (read-only)
    @property
    @abstractmethod
    def Name(self) -> str:
        """Short name of the instrument (must be implemented by subclass)."""
        raise NotImplementedError

    @property
    @abstractmethod
    def FullName(self) -> str:
        """Human-readable full name of the instrument (must be implemented)."""
        raise NotImplementedError

    # Abstract methods
    @abstractmethod
    def GetHeaders(self):
        """Return (headers, units)."""
        pass

    @abstractmethod
    def Measure(self):
        """Perform a measurement and return data (e.g., list or tuple)."""
        pass

    # Concrete base class properties
    @property
    def SimulationMode(self) -> bool:
        return self._simulation_mode

    @SimulationMode.setter
    def SimulationMode(self, val: bool):
        self._simulation_mode = bool(val)

    @property
    def Name(self) -> str:
        return self._name

    @Name.setter
    def Name(self, val: str):
        self._name = val

    # Concrete methods (can be used or overridden by subclasses)   
    def read_string(self) -> str:
        """Read one reply from the instrument, without its line ending ("null" in simulation mode)."""
        if self.SimulationMode:
            return "null"

        handle = self._connected_handle("Read")
        try:
            kind = self._handle_kind(handle)
            if kind == "visa":
                reply = handle.read()
            elif kind == "socket":
                reply = self._read_socket_line(handle)
            else:
                reply = handle.read_until(self.ReadTermination.encode()).decode()
            return str(reply).strip()
        except Exception as e:
            raise RuntimeError(f"Failed to read from {self._describe()}: {e}") from e

    def connectTCPIP(self, ip, port):
        """Called from MATLAB with (py.str(ip), int32(port))."""
        host = str(ip)
        port = int(port)
        try:
            timeout = float(getattr(self, "ConnectionSettings", {}).get("GPIB_Timeout", 10))
        except Exception:
            timeout = 10.0
        try:
            s = socket.create_connection((host, port), timeout=timeout)
            self.DeviceHandle = s
        except Exception as e:
            raise RuntimeError(f"TCP/IP connection failed ({host}:{port}): {e}")

    def connectGPIB(self, board_index, gpib_address, timeout):
        """Called from MATLAB with (int32(boardIndex), int32(address), double(timeout))."""
        pyvisa = _require_package("pyvisa", "pyvisa", "A GPIB connection")
        rm = pyvisa.ResourceManager()
        try:
            board = int(board_index)
        except Exception:
            board = 0
        addr = int(gpib_address)
        # Use a pyvisa-friendly resource string. MATLAB used "GPIB::22::INSTR" while pyvisa commonly accepts "GPIB{board}::{addr}::INSTR"
        resource = f"GPIB{board}::{addr}::INSTR"
        try:
            inst = rm.open_resource(resource)
            # apply terminators/timeouts if ConnectionSettings available
            cs = getattr(self, "ConnectionSettings", None)
            if cs:
                terms = None
                try:
                    terms = cs.get("GPIB_Terminators") if isinstance(cs, dict) else getattr(cs, "GPIB_Terminators", None)
                except Exception:
                    terms = None
                if terms:
                    inst.read_termination = terms[0]
                    inst.write_termination = terms[1] if len(terms) > 1 else terms[0]
                try:
                    t = float(timeout)
                    inst.timeout = int(t * 1000)  # pyvisa timeout in ms
                except Exception:
                    pass
            self.DeviceHandle = inst
        except Exception as e:
            raise RuntimeError(f"GPIB connection failed ({resource}): {e}")
            
    def close(self):
        """Close device handle (complementary to MATLAB Close)."""
        if self.DeviceHandle is None:
            return
        try:
            if hasattr(self.DeviceHandle, "close"):
                self.DeviceHandle.close()
            elif hasattr(self.DeviceHandle, "disconnect"):
                self.DeviceHandle.disconnect()
        finally:
            self.DeviceHandle = None

    def connectVISA(self, visa_address):
        """Called from MATLAB with (py.str(visaAddress))."""
        pyvisa = _require_package("pyvisa", "pyvisa", "A VISA connection")
        rm = pyvisa.ResourceManager()
        resource = str(visa_address)
        try:
            inst = rm.open_resource(resource)
            # apply optional settings
            cs = getattr(self, "ConnectionSettings", None)
            if cs:
                terms = None
                try:
                    terms = cs.get("GPIB_Terminators") if isinstance(cs, dict) else getattr(cs, "GPIB_Terminators", None)
                except Exception:
                    terms = None
                if terms:
                    inst.read_termination = terms[0]
                    inst.write_termination = terms[1] if len(terms) > 1 else terms[0]
                try:
                    timeout = getattr(cs, "GPIB_Timeout") if not isinstance(cs, dict) else cs.get("GPIB_Timeout", None)
                    if timeout is not None:
                        inst.timeout = int(float(timeout) * 1000)
                except Exception:
                    pass
            self.DeviceHandle = inst
        except Exception as e:
            raise RuntimeError(f"VISA connection failed ({resource}): {e}")

    def connectUSB(self):
        """Default USB -> treat as VISA resource if self.VISA_Address present."""
        va = getattr(self, "VISA_Address", None)
        if va:
            return self.connectVISA(str(va))
        raise RuntimeError("connectUSB: No VISA_Address available to open USB device.")

    def connectSerial(self, port):
        """Called from MATLAB with (py.str(port))."""
        serial = _require_package("serial", "pyserial", "A serial connection")
        port_str = str(port)
        cs = getattr(self, "ConnectionSettings", {})
        # support both dict-style or object-style ConnectionSettings
        def get_cs(key, default=None):
            if isinstance(cs, dict):
                return cs.get(key, default)
            return getattr(cs, key, default)
        serial_settings = get_cs("SerialSettings", {})
        try:
            if isinstance(serial_settings, dict):
                baud = int(serial_settings.get("BaudRate", 9600))
                bytesize = int(serial_settings.get("DataBits", 8))
                parity = serial_settings.get("Parity", "N")
                stopbits = serial_settings.get("StopBits", 1)
            else:
                baud = int(getattr(serial_settings, "BaudRate", 9600))
                bytesize = int(getattr(serial_settings, "DataBits", 8))
                parity = getattr(serial_settings, "Parity", "N")
                stopbits = getattr(serial_settings, "StopBits", 1)
            timeout = float(get_cs("GPIB_Timeout", 10))
            ser = serial.Serial(port=port_str, baudrate=baud, bytesize=bytesize, parity=parity, stopbits=stopbits, timeout=timeout)
            self.DeviceHandle = ser
        except Exception as e:
            raise RuntimeError(f"Serial connection failed ({port_str}): {e}")


    def write_command(self, command: str) -> None:
        """Send a command to the instrument (nothing is sent in simulation mode)."""
        if self.SimulationMode:
            return

        handle = self._connected_handle("Write")
        try:
            kind = self._handle_kind(handle)
            if kind == "visa":
                handle.write(command)
            elif kind == "socket":
                handle.sendall((command + self.WriteTermination).encode())
            else:
                handle.write((command + self.WriteTermination).encode())
        except Exception as e:
            raise RuntimeError(f"Failed to send command '{command}' to {self._describe()}: {e}") from e

    def query_string(self, command: str) -> str:
        """Send a query and return the reply as text, without its line ending ("null" in simulation mode)."""
        if self.SimulationMode:
            return "null"

        handle = self._connected_handle("Query")
        if self._handle_kind(handle) == "visa":
            try:
                return str(handle.query(command)).strip()
            except Exception as e:
                raise RuntimeError(f"Failed to query '{command}' on {self._describe()}: {e}") from e

        self.write_command(command)
        return self.read_string()

    def query_double(self, command: str) -> float:
        """Send a query and return the reply as a number (a random value near 100 in simulation mode)."""
        if self.SimulationMode:
            return random.random() + 100.0

        reply = self.query_string(command)
        try:
            return float(reply)
        except ValueError as e:
            raise ValueError(f"Reply to '{command}' from {self._describe()} is not a number: '{reply}'") from e

    # Internal helpers for the methods above
    def _connected_handle(self, action: str):
        """Return the connection, or raise an error if the instrument isn't connected."""
        if getattr(self, "DeviceHandle", None) is None:
            raise AssertionError(f"Device Handle is empty - device is not connected yet when sending {action} command ({self._describe()})")
        return self.DeviceHandle

    @staticmethod
    def _handle_kind(handle) -> str:
        """The kind of connection: "socket" (Ethernet), "visa" (pyvisa: GPIB, VISA, USB) or "serial".
        Worked out from the object itself, so that pyvisa and pyserial need not be imported."""
        if isinstance(handle, socket.socket):
            return "socket"
        if hasattr(handle, "query"):
            return "visa"
        if hasattr(handle, "read_until"):
            return "serial"
        raise TypeError(f"Unsupported connection type: {type(handle).__name__}")

    def _read_socket_line(self, sock) -> str:
        """Read from a socket up to and including ReadTermination, and return the text before it."""
        terminator = self.ReadTermination.encode()
        data = b""
        while not data.endswith(terminator):
            chunk = sock.recv(1)
            if not chunk:
                break   # connection closed
            data += chunk
        return data[: -len(terminator)].decode() if data.endswith(terminator) else data.decode()

    def _describe(self) -> str:
        """The instrument's full name, for error messages."""
        try:
            return str(self.FullName)
        except Exception:
            return type(self).__name__

    def collect_metadata(self):
        """Default: no metadata (return None)."""
        return None

