# qcodes_test_instruments.py
"""QCoDeS instruments for the tests of QCoDeSInstrument - each a few lines, as a user would write them.
Needs qcodes installed; the tests skip when it isn't."""
from PalladiumPythonCore.QCoDeSInstrument import QCoDeSInstrument
from PalladiumPythonCore import QCoDeSOffline


class K2450Test(QCoDeSInstrument):
    DriverClass = "qcodes.instrument_drivers.Keithley.Keithley_2450.Keithley2450"
    Parameters = ["timeout", "line_frequency"]
    Settings = {"source_function": "voltage"}
    OfflineIDN = "Keithley Instruments,MODEL 2450,0001,1.0"
    OfflineState = {"*LANG": "SCPI"}


class K2450NoSettingsTest(K2450Test):
    """For connecting through a fake VISA connection: the real source_function setter reads replies the fake can't give."""
    Settings = {}


class K2450BadSettingTest(K2450Test):
    Settings = {"terminals": "bogus"}


class K2450UnknownParameterTest(K2450Test):
    Parameters = ["not_a_parameter"]


class K2450NonNumericTest(K2450Test):
    Parameters = ["terminals"]


class Lakeshore336Test(QCoDeSInstrument):
    DriverClass = "qcodes.instrument_drivers.Lakeshore.Lakeshore_model_336.LakeshoreModel336"
    Parameters = ["A_temperature", "B_temperature"]


class Keithley2601BTest(QCoDeSInstrument):
    """A driver that checks the model in the instrument's replies, so can't be created offline."""
    DriverClass = "qcodes.instrument_drivers.Keithley.Keithley_2600_channels.Keithley2601B"
    Parameters = []


def connect_gpib_with_fake_visa(instrument, board, address, timeout):
    """Connect over GPIB as Palladium would, but with the VISA connection faked, so no hardware is needed."""
    from qcodes.instrument.visa import VisaInstrument

    handle = QCoDeSOffline.FakeVisaHandle(idn=instrument.OfflineIDN or QCoDeSOffline.FakeVisaHandle.DEFAULT_IDN,
                                          state=instrument.OfflineState)
    original = VisaInstrument._open_resource

    def open_resource(self, addr, visalib):
        handle.resource_name = addr
        return handle

    VisaInstrument._open_resource = open_resource
    try:
        instrument.connectGPIB(board, address, timeout)
    finally:
        VisaInstrument._open_resource = original
    return handle
