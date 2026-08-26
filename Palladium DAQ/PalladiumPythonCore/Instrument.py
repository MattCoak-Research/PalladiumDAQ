# Instrument.py
from abc import ABC, abstractmethod
from typing import Optional, Any
import time
import random


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
    def Name(self, val: string):
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

