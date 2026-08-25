# Instrument.py
from abc import ABC, abstractmethod

class Instrument(ABC):
    """
    Abstract base class mirroring the MATLAB Instrument interface.
    Subclasses must implement the abstract properties Name and FullName,
    and the abstract methods GetHeaders() and Measure().
    """

    def __init__(self, mtlbInstr):
        # default, override or use subclass-set values
        self.MatlabInstrInstance = mtlbInstr
        self.SimulationMode = True

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

    # Example concrete methods (can be used or overridden by subclasses)   

    def QueryDouble(self, command: str) -> float:
        if self.SimulationMode:
            import random
            return 100.0 + random.random()
        raise NotImplementedError("QueryDouble not implemented for real device")

    def QueryString(self, command: str) -> str:
        if self.SimulationMode:
            return "null"
        raise NotImplementedError("QueryString not implemented for real device")

    def WriteCommand(self, command: str):
        if self.SimulationMode:
            print(f"[SIM WRITE] {command}")
        else:
            raise NotImplementedError("WriteCommand not implemented for real device")

    def CollectMetaData(self):
        """Default: no metadata (return None)."""
        return None

    
