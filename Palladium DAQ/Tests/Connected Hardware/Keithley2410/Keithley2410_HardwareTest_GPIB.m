classdef Keithley2410_HardwareTest_GPIB < Keithley2410_HardwareTest_Base
    %Keithley2410_HardwareTest_GPIB - The Keithley2410 hardware tests, over GPIB.
    %All the tests, and the required setup and safety limits, are described in
    %Keithley2410_HardwareTest_Base - read the notes at the top of that file
    %before running these. In short: a Keithley 2400-series SourceMeter on GPIB
    %(address 24 on GPIB board 0, factory settings) with a 1.09 kOhm resistor on the
    %output, 4-wire. Run with runtests("Keithley2410_HardwareTest_GPIB").
    %
    %To test another connection type, copy this file, rename it, and change
    %ConfigureConnection to suit.

    properties (Constant)
        GPIB_Address = 24;      %Factory default - change if the instrument has been set to something else
    end

    methods (Access = protected)
        function ConfigureConnection(testCase, instrument)
            instrument.Connection_Type = Palladium.Enums.ConnectionType.GPIB;
            instrument.GPIB_Address = testCase.GPIB_Address;
        end
    end
end
