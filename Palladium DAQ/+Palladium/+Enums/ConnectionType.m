classdef ConnectionType
    %ConnectionType - How an instrument communicates with its hardware, set by its Connection_Type property.
    %Each instrument declares which of these it supports, by calling
    %`DefineSupportedConnectionTypes` in its constructor. `Instrument.Connect()`
    %then opens the matching connection, using the instrument's address
    %property for that type.

    %% Enumeration
    enumeration
        Debug       %No hardware: the instrument runs in SimulationMode and returns synthetic data, for testing
        Ethernet    %TCP/IP socket to IP_Address, on port ConnectionSettings.Port
        GPIB        %GPIB, via VISA, to GPIB_Address on interface board ConnectionSettings.GPIB_BoardIndex
        Serial      %Serial (COM) port Serial_Address, with settings from ConnectionSettings.SerialSettings
        USB         %USB, connected through VISA using VISA_Address
        VISA        %Any VISA resource, given in full by VISA_Address
    end
end
