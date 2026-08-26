# Instrument.py
from abc import ABC, abstractmethod
import socket
import json
import time

HOST = "127.0.0.1"
PORT = 50000
RETRY_DELAY = 1.0     # seconds between reconnect attempts
SEND_INTERVAL = 0.5   # seconds between events in example loop

class Instrument(ABC):
    """
    Abstract base class mirroring the MATLAB Instrument interface.
    Subclasses must implement the abstract properties Name and FullName,
    and the abstract methods GetHeaders() and Measure().
    """

    def __init__(self):
        # default, override or use subclass-set values
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

    def ConnectToMessageServer(self, port=PORT, host=HOST, timeout=5.0):
        """Create and return a connected socket (blocking)."""
        #while True:
        try:
            self.sock = socket.create_connection((host, port), timeout=timeout)
            self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            print(f"Connected to {host}:{port}")
        except Exception as e:
            print(f"Connect failed: {e}; retrying in {RETRY_DELAY}s")
          #  time.sleep(RETRY_DELAY)

    def send_event(self, sock, name, data):
        """Send a single event as newline-terminated JSON."""
        msg = {"event": name, "data": data}
        s = json.dumps(msg) + "\n"
        try:
            sock.sendall(s.encode("utf-8"))
        except BrokenPipeError:
            raise
            
    def send_event_full(self, name, data):
        try:
            self.send_event(self.sock, name, data)
        except BrokenPipeError:
            print("Connection lost, reconnecting...")
            self.sock.close()
            self.ConnectToMessageServer()
            self.send_event(self.sock, name, data)
            time.sleep(SEND_INTERVAL)
        finally:
            try:
                sock.close()
            except:
                pass

    def test_event(self):
        print("TEST EVENT");
        #self.send_event_full("test", 4.5)
