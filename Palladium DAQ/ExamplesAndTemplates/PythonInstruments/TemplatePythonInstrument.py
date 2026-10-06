# TemplatePythonInstrument.py
"""Starting point for a new Python instrument driver for Palladium DAQ.

Copy this file, then rename the copy and the class inside it to your
instrument's name - the class name must match the file name, e.g.
MyDMM.py containing class MyDMM. Replace the example commands and readings
with your instrument's. See "Python instruments" in the documentation.

Palladium DAQ copies this template into the PythonInstruments folder of your
user files folder, but never lists it as an instrument itself.
"""
import random

from PalladiumPythonCore.Instrument import Instrument


class TemplatePythonInstrument(Instrument):
    """Template Python instrument: measures a resistance and a current."""

    def __init__(self):
        super().__init__()
        # Short name, used to name the instrument (e.g. Template_1) and its data columns
        self.Name = "Template"

        # Line endings for Ethernet and serial connections ("\n" by default).
        # Uncomment and change these if your instrument uses something else
        # self.WriteTermination = "\r\n"
        # self.ReadTermination = "\r\n"

    @property
    def FullName(self):
        """Descriptive name, shown in the GUI."""
        return "Template Python Instrument"

    def GetHeaders(self):
        """Column headers and their units - one each, in the same order as Measure's values.
        Palladium DAQ adds the instrument's name in front of each header."""
        return (["Resistance_Ohms", "Current_A"], ["Ohms", "A"])

    def Measure(self):
        """Take one reading of each column: realistic made-up values in simulation (Debug) mode."""
        if self.SimulationMode:
            return [500 + random.gauss(0, 5), 1e-3 + random.gauss(0, 1e-5)]

        # Replace these with your instrument's commands
        return [self.query_double("MEAS:RES?"), self.query_double("MEAS:CURR?")]

    def collect_metadata(self):
        """Settings to record in the data file's header, which don't change during a run.
        Return a dict of names (valid MATLAB field names) and values (text or
        numbers), or None to record nothing. Delete this method if there is
        nothing to record."""
        return {"ExampleSetting": "Auto range"}

    def SetParameter(self, value):
        """Example of a method that sends a setting to the instrument."""
        self.write_command(f"PARAM {value}")    # Replace with your instrument's command
