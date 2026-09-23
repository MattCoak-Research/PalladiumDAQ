classdef MercuryITC < Palladium.Core.Instrument
    %Instrument implementation for the Oxford Instruments Mercury iTC
    %temperature controller / sensor readout unit.
    %Ported from the mercuryITC.py reference implementation (Benno Meier,
    %2015). That implementation exposes generic read/write/set access to
    %the instrument's DEV:<board>.<sensor>:SIG:<signal> command tree, used
    %there to read out Voltage, Current, Resistance and Temperature from
    %up to eight sensor boards. Heater/PID/setpoint control was never
    %implemented in the Python source, so it is not present here either.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Oxford Instruments Mercury iTC";   %Full name, just for displaying on GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "MercuryITC";                                     %Instrument name
        Connection_Type = Palladium.Enums.ConnectionType.Ethernet;   %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.

        %Device address for each sensor channel, in the instrument's own
        %DEV:<board>.<sensor>:<...> addressing scheme. Leave as "Default"
        %to have GetDeviceCatalog() auto-populate it from the instrument's
        %own SYS:CAT catalogue, or edit it directly to pin a channel to a
        %specific sensor board.
        Channel_1_Name = "Default";
        Channel_2_Name = "Default";
        Channel_3_Name = "Default";
        Channel_4_Name = "Default";
        Channel_5_Name = "Default";
        Channel_6_Name = "Default";
        Channel_7_Name = "Default";
        Channel_8_Name = "Default";
    end

    %% Properties (Private)
    properties(Access = private)
        DeviceCatalogue = [];
    end

    %% Constructor
    methods
        function this = MercuryITC()
            %Specify communication options and settings - the real
            %instrument is only ever accessed over Ethernet or RS232
            %Serial, matching the two classes in the Python reference
            %implementation.
            this.DefineSupportedConnectionTypes(["Debug", "Ethernet", "Serial", "VISA"]);

            this.ConnectionSettings.Port = 7020;   %Mercury iTC SCPI Ethernet port

            this.ConnectionSettings.SerialSettings.BaudRate = 115200;
            this.ConnectionSettings.SerialSettings.StopBits = 1;
            this.ConnectionSettings.SerialSettings.Terminator = "LF";
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function Connect(this)
            Connect@Palladium.Core.Instrument(this);

            %Scan over all the hardware boards on this instrument
            this.DeviceCatalogue = this.GetDeviceCatalogue();

            if ~this.SimulationMode
              %  pause(2);
            end
        end

        function idnString = GetIDN(this)
            %Query the instrument identity string (*IDN?)
            if this.SimulationMode
                idnString = "SIMULATED MERCURY ITC";
                return;
            end

            idnString = this.ReadValue("*IDN?", "");
        end

        function [deviceAddresses, catalogString] = GetDeviceCatalogue(this)
            %Query the instrument for the catalogue of devices/boards it
            %can see (SYS:CAT) and parse it into a list of fully-qualified
            %device addresses, eg ["DEV:MB1.T1:TEMP", "DEV:DB6.T1:TEMP",
            %...], in the same format as the Channel_n_Address properties.
            %
            %The response is of the form
            %STAT:DEV:<uid>:<type>:DEV:<uid>:<type>:... (see the
            %MercuryiPS manual, section 10.3.5, for the equivalent
            %documented example - both instruments share this protocol).
            if this.SimulationMode
                %Hard-typed example catalog string, matching the default
                %Channel_n_Address properties
                catalogString = "STAT:DEV:DB7.T1:TEMP:DEV:DB6.T1:TEMP:DEV:MB1.T1:TEMP";
            else
                catalogString = this.ReadValue("SYS:CAT");
            end

            %Splitting on ":DEV:" isolates each device's <uid>:<type>
            %segment; the first split segment is the leading STAT (and
            %any SYS:CAT echo) prefix, which is discarded.
            deviceSegments = strsplit(catalogString, ":DEV:");
            deviceSegments(1) = [];

            deviceAddresses = "DEV:" + string(deviceSegments);

            %Auto-populate any channel still left at its "Default" value
            %with the corresponding device address found in the catalogue
            for channelIndex = 1:8
                propName = "Channel_" + string(channelIndex) + "_Name";
                if this.(propName) == "Default" && channelIndex <= numel(deviceAddresses)
                    this.(propName) = deviceAddresses(channelIndex);
                end
            end
        end

        function [Headers, Units] = GetHeaders(this)
            Headers = strings(1, 0);
            Units = strings(1, 0);

            if isempty(this.DeviceCatalogue)
                warning("Device Catalogue empty in Mercury ITC - no modules found or GetDeviceCatalogue not yet called");
            end

            for i = 1:length(this.DeviceCatalogue)
                channelName = this.("Channel_" + string(i) + "_Name");
                Headers = [Headers, this.Name + " - " + channelName]; %#ok<AGROW>
                Units = [Units, this.GuessUnitFromDeviceAddress(this.DeviceCatalogue(i))]; %#ok<AGROW>
            end
        end

        function value = GetSignal(this, deviceAddress, signalName)
            %Get a signal from a device address, eg deviceAddress =
            %this.Channel_1_Name, signalName = "TEMP", "VOLT", "CURR",
            %"RES", etc. SI unit prefixes on the returned value are
            %handled and the result is returned as a double.
            arguments
                this;
                deviceAddress {mustBeTextScalar};
                signalName {mustBeTextScalar};
            end

            if this.SimulationMode
                value = 273 + rand()*1;
                return;
            end

            resultString = this.ReadValue(string(deviceAddress) + ":SIG:" + string(signalName));

            %Response is of the form ...:SIG:TEMP:<value><unitPrefix><unit>
            %Take everything after the last colon
            parts = strsplit(resultString, ":");
            valueString = char(parts{end});

            value = this.ParseSIPrefixedValue(valueString);
        end

        function varargout = GetSensorInformation(this, deviceAddress, includeTemperature)
            %Get Voltage, Current, Resistance and optionally Temperature
            %of a device address.
            arguments
                this;
                deviceAddress {mustBeTextScalar};
                includeTemperature (1,1) logical = false;
            end

            v = this.GetSignal(deviceAddress, "VOLT");
            c = this.GetSignal(deviceAddress, "CURR");
            r = this.GetSignal(deviceAddress, "RES");

            if includeTemperature
                t = this.GetSignal(deviceAddress, "TEMP");
                varargout = {v, c, r, t};
            else
                varargout = {v, c, r};
            end
        end

        function [dataRow] = Measure(this)
            %One column per catalogued device, matching GetHeaders(). The
            %signal read for each device is guessed from its type suffix
            %(see GuessSignalNameFromDeviceAddress), the same way
            %GuessUnitFromDeviceAddress picks the header unit.
            dataRow = nan(1, length(this.DeviceCatalogue));

            for i = 1:length(this.DeviceCatalogue)
                if this.SimulationMode
                    %Dummy value
                    dataRow(i) = 273 + rand();
                    continue;
                end

                deviceAddress = this.DeviceCatalogue(i);
                signalName = this.GuessSignalNameFromDeviceAddress(deviceAddress);

                if signalName ~= ""
                    dataRow(i) = this.GetSignal(deviceAddress, signalName);
                end
            end
        end

        function resultString = ReadValue(this, command, readPrefix)
            %Low level read - writes readPrefix + command to the
            %instrument and returns the reply string. readPrefix defaults
            %to "READ:", matching the instrument's SCPI-like command set.
            arguments
                this;
                command {mustBeTextScalar};
                readPrefix {mustBeTextScalar} = "READ:";
            end

            if this.SimulationMode
                resultString = "null";
                return;
            end

            resultString = string(this.QueryString(string(readPrefix) + string(command)));
        end

        function resultString = SetValue(this, command)
            %Low level set - writes "SET:" + command to the instrument
            %and returns the (echoed) reply string.
            arguments
                this;
                command {mustBeTextScalar};
            end

            if this.SimulationMode
                resultString = "null";
                return;
            end

            resultString = char(this.QueryString("SET:" + string(command)));
        end

    end

    %% Methods (Protected)
    methods(Access = protected)

        function propertiesToIgnore = GetPropertiesToIgnore(~)
            %Set properties in the underlying Instrument class that should
            %be ignored here
            propertiesToIgnore = {"GPIB_Address"};
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function signalName = GuessSignalNameFromDeviceAddress(~, deviceAddress)
            %Guess which SIG:<name> to read for Measure() from the device
            %type suffix of a catalogue address, eg "DEV:DB7.T1:TEMP" ->
            %"TEMP". Mirrors GuessUnitFromDeviceAddress's type mapping.
            %Returns "" for device types this class doesn't otherwise
            %handle (eg LVL, PSU, GRPZ), which Measure() reports as NaN.
            addr = upper(string(deviceAddress));

            if contains(addr, "TEMP")
                signalName = "TEMP";
            elseif contains(addr, "HTR")
                signalName = "PWR";
            elseif contains(addr, "AUX")
                signalName = "PERC";
            else
                signalName = "";
            end
        end

        function unit = GuessUnitFromDeviceAddress(~, deviceAddress)
            %Guess a display unit from the device type suffix of a
            %catalogue address, eg "DEV:DB7.T1:TEMP" -> "K". Falls back to
            %"??" for device types this class doesn't otherwise handle
            %(eg LVL, PSU, GRPZ).
            addr = upper(string(deviceAddress));

            if contains(addr, "TEMP")
                unit = "K";
            elseif contains(addr, "HTR")
                unit = "W";
            elseif contains(addr, "AUX")
                unit = "%";
            else
                unit = "??";
            end
        end

        function value = ParseSIPrefixedValue(~, valueString)
            %Parse a value string of the form "<number><prefix><unit>" or
            %"<number><unit>" (no prefix) into a double, applying the SI
            %unit prefix if present. Mirrors the siPrefixes handling in
            %the Python reference implementation's getSignal().
            siPrefixes = containers.Map(...
                {'M', 'k', 'm', char(181), 'n', 'p'}, ...   %char(181) is micro sign, matches Python's u"\xb5"
                {1e6, 1e3, 1e-3, 1e-6, 1e-9, 1e-12});

            %The last two characters are the unit and (optionally) an SI
            %prefix. Check whether the second-to-last character is the
            %prefix letter or a digit (ie no prefix, just eg "12A").
            prefixChar = valueString(end-1);

            if isstrprop(prefixChar, 'digit')
                value = str2double(valueString(1:end-1));
            elseif isKey(siPrefixes, prefixChar)
                value = str2double(valueString(1:end-2)) * siPrefixes(prefixChar);
            else
                error("Could not parse SI-prefixed value: " + string(valueString));
            end
        end

    end
end
