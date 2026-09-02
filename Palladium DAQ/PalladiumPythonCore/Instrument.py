# Instrument.py
from abc import ABC, abstractmethod
from typing import Optional, Any
import time
import random
import socket
import pyvisa
import serial


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
        """
        Read string from the instrument using a MATLAB object proxy.
        Assumes self.DeviceHandle has an fscanf method.
        """
        if getattr(self, "SimulationMode", False):
            return "null"

        if not hasattr(self, "DeviceHandle") or self.DeviceHandle is None:
            raise AssertionError(
                f"Device Handle is empty - device is not connected yet when sending Query command ({getattr(self, 'FullName', '')})"
            )

            try:
                resp = self.DeviceHandle.fscanf()
                return str(resp)
            except Exception as e:
                raise RuntimeError(f"Failed to read from DeviceHandle.fscanf: {e}") from e

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


    def query_double(self, command: str) -> float:
        """
        Query the instrument and return a double (float).
        Mirrors MATLAB Instrument.QueryDouble.
        """
        if getattr(self, "SimulationMode", False):
            return random.random() + 100.0

        # Ensure we have a device handle
        if not hasattr(self, "DeviceHandle") or self.DeviceHandle is None:
            raise AssertionError(f"Device Handle is empty - device is not connected yet when sending Query command ({getattr(self, 'FullName', '')})")

            # Send query using common VISA-like API: device.query(command)
            # If your device uses a different method name (e.g. read, write_read), adjust accordingly.
            resp = self.DeviceHandle.query(command)

            # Convert to float, raising ValueError on bad conversion
            try:
                return float(resp)
            except Exception as e:
                raise ValueError(f"Failed to convert device response to float. Response: {resp}") from e

    def query_string(self, command: str) -> str:
        """
        Send a query string to a MATLAB visadev/serial proxy and return the response.
        """
        if getattr(self, "SimulationMode", False):
            return "null"
    
        if not hasattr(self, "DeviceHandle") or self.DeviceHandle is None:
            raise AssertionError(f"Device Handle is empty - device is not connected yet when sending Query command ({getattr(self, 'FullName', '')})")
    
        try:
            # MATLAB object proxy: call its query method (forwarded to MATLAB)
            resp = self.DeviceHandle.query(command)
            # Ensure Python has a str
            return str(resp)
        except Exception as e:
            raise RuntimeError(f"Failed to query DeviceHandle: {e}") from e


    def query_double(self, command: str) -> float:
        """
        Send a query and convert the response to float. Mirrors MATLAB QueryDouble.
        """
        if getattr(self, "SimulationMode", False):
            import random
            return random.random() + 100.0
    
        if not hasattr(self, "DeviceHandle") or self.DeviceHandle is None:
            raise AssertionError(f"Device Handle is empty - device is not connected yet when sending Query command ({getattr(self, 'FullName', '')})")
    
        try:
            resp = self.DeviceHandle.query(command)
            # Convert response to float; will raise ValueError if conversion fails
            return float(resp)
        except Exception as e:
            raise RuntimeError(f"Failed to query/convert DeviceHandle response to float. Response: {resp if 'resp' in locals() else None}; Error: {e}") from e


    def write_command(self, command: str) -> None:
        """
        Send a command string to the instrument using a MATLAB visadev/serial proxy.
        Assumes self.DeviceHandle is a matlab.object with a fprintf method.
        """
        if getattr(self, "SimulationMode", False):
            return
    
        if not hasattr(self, "DeviceHandle") or self.DeviceHandle is None:
            raise AssertionError(
                f"Device Handle is empty - device is not connected yet when sending Write command ({getattr(self, 'FullName', '')})"
            )
    
        try:
            # Call MATLAB object's fprintf method (bridge forwards to MATLAB)
            self.DeviceHandle.fprintf(command)
        except Exception as e:
            raise RuntimeError(f"Failed to send command via DeviceHandle.fprintf: {e}") from e


    def collect_metadata(self):
        """Default: no metadata (return None)."""
        return None

