classdef MercuryITC < Palladium.Core.Instrument
    %Instrument implementation for the Oxford Instruments Mercury iTC
    %temperature controller / sensor readout unit.
    %Originally ported from the mercuryITC.py reference implementation
    %(Benno Meier, 2015), then cross-checked and extended against the
    %official "MercuryiTC" User Manual (Oxford Instruments NanoScience,
    %MAN-NS-0014, Revision B), Chapter 10 "Command reference guide".
    %
    %Devices (temperature sensors, heaters, auxiliary/gas-flow boards,
    %pressure sensors, etc) are addressed as DEV:<UID>:<TYPE>, discovered
    %dynamically via SYS:CAT (see GetDeviceCatalogue). Each device exposes
    %readable signals under DEV:<UID>:<TYPE>:SIG:<name> (see GetSignal).
    %Temperature sensor devices additionally have an associated PID control
    %loop, addressed as DEV:<UID>:TEMP:LOOP:<name> (see
    %SetTemperatureSetpoint, SetPIDValues, EnablePIDControl, etc) - this
    %was not implemented in the Python reference (which predates the
    %manual being available) but is documented in the official manual and
    %is implemented here.
    %
    %Not implemented: the LVL (helium/nitrogen level meter) device type,
    %whose signals are nested under HEL:/NIT: sub-branches rather than a
    %single flat SIG:<name>, and the niche Lambda/HelioxX pre-configured
    %control-loop templates (sections 10.3.20/10.3.21 of the manual) -
    %these require specific daughter-board hardware templates that are
    %out of scope for a general-purpose driver.

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
            value = this.ParseSignalResponse(resultString);
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

        function AssignAuxToLoop(this, deviceAddress, auxUID)
            %Associate an auxiliary/gas-flow device (eg "DEV:DB3:AUX")
            %with the PID control loop of the given temperature sensor
            %device address (LOOP:AUX)
            arguments
                this;
                deviceAddress {mustBeTextScalar};
                auxUID {mustBeTextScalar};
            end

            if this.SimulationMode
                disp("Aux device " + string(auxUID) + " assigned to loop on " + string(deviceAddress));
                return;
            end

            this.SetLoopString(deviceAddress, "AUX", auxUID);
        end

        function AssignHeaterToLoop(this, deviceAddress, heaterUID)
            %Associate a heater device (eg "DEV:MB0:HTR") with the PID
            %control loop of the given temperature sensor device address
            %(LOOP:HTR)
            arguments
                this;
                deviceAddress {mustBeTextScalar};
                heaterUID {mustBeTextScalar};
            end

            if this.SimulationMode
                disp("Heater " + string(heaterUID) + " assigned to loop on " + string(deviceAddress));
                return;
            end

            this.SetLoopString(deviceAddress, "HTR", heaterUID);
        end

        function DisablePIDControl(this, deviceAddress)
            %Disable (Manual mode) the PID control loop of the given
            %temperature sensor device address (LOOP:ENAB)
            arguments
                this;
                deviceAddress {mustBeTextScalar};
            end

            if this.SimulationMode
                disp("PID control disabled on " + string(deviceAddress));
                return;
            end

            this.SetLoopString(deviceAddress, "ENAB", "OFF");
        end

        function EnablePIDControl(this, deviceAddress)
            %Enable (Auto mode) the PID control loop of the given
            %temperature sensor device address (LOOP:ENAB)
            arguments
                this;
                deviceAddress {mustBeTextScalar};
            end

            if this.SimulationMode
                disp("PID control enabled on " + string(deviceAddress));
                return;
            end

            this.SetLoopString(deviceAddress, "ENAB", "ON");
        end

        function isEnabled = GetPIDControlEnabled(this, deviceAddress)
            %Is the PID control loop of the given temperature sensor
            %device address currently enabled (Auto) or disabled (Manual)
            arguments
                this;
                deviceAddress {mustBeTextScalar};
            end

            if this.SimulationMode
                isEnabled = false;
                return;
            end

            isEnabled = strcmpi(this.GetLoopString(deviceAddress, "ENAB"), "ON");
        end

        function [P, I, D] = GetPIDValues(this, deviceAddress)
            %Read the PID control loop values (LOOP:P/I/D) associated
            %with the given temperature sensor device address
            arguments
                this;
                deviceAddress {mustBeTextScalar};
            end

            if this.SimulationMode
                P = 0;
                I = 0;
                D = 0;
                return;
            end

            P = this.GetLoopValue(deviceAddress, "P");
            I = this.GetLoopValue(deviceAddress, "I");
            D = this.GetLoopValue(deviceAddress, "D");
        end

        function SetPIDValues(this, deviceAddress, P, I, D)
            %Set the PID control loop values (LOOP:P/I/D) associated with
            %the given temperature sensor device address
            arguments
                this;
                deviceAddress {mustBeTextScalar};
                P (1,1) double;
                I (1,1) double;
                D (1,1) double;
            end

            if this.SimulationMode
                disp("PID values on " + string(deviceAddress) + " set to P=" + num2str(P) + ", I=" + num2str(I) + ", D=" + num2str(D));
                return;
            end

            this.SetLoopValue(deviceAddress, "P", P);
            this.SetLoopValue(deviceAddress, "I", I);
            this.SetLoopValue(deviceAddress, "D", D);
        end

        function setpoint_K = GetTemperatureSetpoint(this, deviceAddress)
            %Read the PID control loop's temperature setpoint (LOOP:TSET)
            %associated with the given temperature sensor device address
            arguments
                this;
                deviceAddress {mustBeTextScalar};
            end

            if this.SimulationMode
                setpoint_K = 0;
                return;
            end

            setpoint_K = this.GetLoopValue(deviceAddress, "TSET");
        end

        function SetTemperatureSetpoint(this, deviceAddress, setpoint_K)
            %Set the PID control loop's temperature setpoint (LOOP:TSET)
            %associated with the given temperature sensor device address.
            %The loop must have a heater assigned (AssignHeaterToLoop) and
            %PID control enabled (EnablePIDControl) for this to actually
            %drive the temperature.
            arguments
                this;
                deviceAddress {mustBeTextScalar};
                setpoint_K (1,1) double;
            end

            if this.SimulationMode
                disp("Temperature setpoint on " + string(deviceAddress) + " set to " + num2str(setpoint_K) + " K");
                return;
            end

            achievedSetPt = this.SetLoopValue(deviceAddress, "TSET", setpoint_K);
            assert(achievedSetPt == setpoint_K, "Failed to set temperature setpoint on " + string(deviceAddress) + ". Requested " + num2str(setpoint_K) + " K, achieved " + num2str(achievedSetPt) + " K.");
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
            %
            %Signal names are per the manual's per-device SIG tables
            %(section 10.3.11 TEMP, 10.3.15 HTR, 10.3.17 AUX, 10.3.18
            %PRES) - note HTR's power signal is "POWR", not "PWR".
            addr = upper(string(deviceAddress));

            if contains(addr, "TEMP")
                signalName = "TEMP";
            elseif contains(addr, "HTR")
                signalName = "POWR";
            elseif contains(addr, "AUX")
                signalName = "PERC";
            elseif contains(addr, "PRES")
                signalName = "PRES";
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
            elseif contains(addr, "PRES")
                unit = "mbar";
            else
                unit = "??";
            end
        end

        function value = GetLoopValue(this, deviceAddress, loopCommand)
            %Generic numeric read of a DEV:<uid>:TEMP:LOOP:<loopCommand>
            %value, eg loopCommand = "TSET", "P", "I", "D"
            arguments
                this;
                deviceAddress {mustBeTextScalar};
                loopCommand {mustBeTextScalar};
            end

            if this.SimulationMode
                value = 0;
                return;
            end

            resultString = this.ReadValue(string(deviceAddress) + ":LOOP:" + string(loopCommand));
            value = this.ParseSignalResponse(resultString);
        end

        function strVal = GetLoopString(this, deviceAddress, loopCommand)
            %Generic string read of a DEV:<uid>:TEMP:LOOP:<loopCommand>
            %value, eg loopCommand = "ENAB", "HTR", "AUX"
            arguments
                this;
                deviceAddress {mustBeTextScalar};
                loopCommand {mustBeTextScalar};
            end

            if this.SimulationMode
                strVal = "";
                return;
            end

            resultString = this.ReadValue(string(deviceAddress) + ":LOOP:" + string(loopCommand));
            strVal = this.ParseStringResponse(resultString);
        end

        function mult = GetSIPrefixMultiplier(~, unitToken)
            %Convert an SI-prefixed unit string (eg "mK", "uA") into its
            %multiplier. A bare unit with no recognised prefix (eg "K",
            %"A") returns a multiplier of 1, matching the manual's own
            %definition of "$ - none" as one of the possible scales.
            prefixMap = containers.Map(...
                {'n', 'u', char(181), 'm', 'k', 'M'}, ...   %char(181) is the micro sign
                {1e-9, 1e-6, 1e-6, 1e-3, 1e3, 1e6});

            if isempty(unitToken) || strlength(string(unitToken)) < 2
                mult = 1;
                return;
            end

            firstChar = char(unitToken);
            firstChar = firstChar(1);

            if isKey(prefixMap, firstChar)
                mult = prefixMap(firstChar);
            else
                mult = 1;
            end
        end

        function value = ParseSignalResponse(this, responseString)
            %Parse a STAT:...:<value> response into a double. Handles a
            %SET confirmation echoing back a plain unscaled number (eg
            %"...:TSET:4.321:VALID"), a READ of a signal returning the
            %number and its SI-prefixed unit as separate colon-delimited
            %tokens (eg "...:SIG:VOLT:12.345:mV:VALID"), and (as a
            %fallback) the number and unit concatenated into one token.
            tokens = this.StripAndCheckStatusToken(strsplit(char(responseString), ":"), responseString);

            lastToken = tokens{end};

            %Case 1 - plain unscaled numeric value
            directValue = str2double(lastToken);
            if ~isnan(directValue)
                value = directValue;
                return;
            end

            %Case 2 - number and SI-prefixed unit as separate tokens
            if numel(tokens) >= 2 && ~isnan(str2double(tokens{end-1}))
                value = str2double(tokens{end-1}) * this.GetSIPrefixMultiplier(lastToken);
                return;
            end

            %Case 3 - number and unit concatenated into a single token
            value = this.ParseSIPrefixedValue(lastToken);
        end

        function strVal = ParseStringResponse(this, responseString)
            %Parse a STAT:...:<value> response where the value is a
            %string/enumerated status (eg ON/OFF) rather than a number.
            tokens = this.StripAndCheckStatusToken(strsplit(char(responseString), ":"), responseString);
            strVal = string(tokens{end});
        end

        function confirmedValue = SetLoopValue(this, deviceAddress, loopCommand, value)
            %Generic numeric write to a DEV:<uid>:TEMP:LOOP:<loopCommand>
            %value, eg loopCommand = "TSET", "P", "I", "D". Verifies the
            %instrument confirmed the value was VALID and returns the
            %confirmed (echoed) value.
            arguments
                this;
                deviceAddress {mustBeTextScalar};
                loopCommand {mustBeTextScalar};
                value (1,1) double;
            end

            if this.SimulationMode
                confirmedValue = value;
                return;
            end

            commandStr = string(deviceAddress) + ":LOOP:" + string(loopCommand) + ":" + num2str(value);
            responseString = this.SetValue(commandStr);
            confirmedValue = this.ParseSignalResponse(responseString);
        end

        function confirmedStr = SetLoopString(this, deviceAddress, loopCommand, valueStr)
            %Generic string write to a DEV:<uid>:TEMP:LOOP:<loopCommand>
            %value, eg loopCommand = "ENAB", "HTR", "AUX". Verifies the
            %instrument confirmed the value was VALID and returns the
            %confirmed (echoed) value.
            arguments
                this;
                deviceAddress {mustBeTextScalar};
                loopCommand {mustBeTextScalar};
                valueStr {mustBeTextScalar};
            end

            if this.SimulationMode
                confirmedStr = string(valueStr);
                return;
            end

            commandStr = string(deviceAddress) + ":LOOP:" + string(loopCommand) + ":" + string(valueStr);
            responseString = this.SetValue(commandStr);
            confirmedStr = this.ParseStringResponse(responseString);
        end

        function tokens = StripAndCheckStatusToken(~, tokens, originalResponse)
            %Strip a trailing VALID confirmation token, or raise a clear
            %error for one of the manual's documented invalid-response
            %tokens (section 10.4, Table 39): INVALID, NOT_FOUND, N/A or
            %DENIED - rather than letting them fall through to a
            %confusing numeric parse failure.
            if isempty(tokens)
                return;
            end

            lastToken = string(tokens{end});

            switch(upper(lastToken))
                case "VALID"
                    tokens(end) = [];
                case "INVALID"
                    error("MercuryiTC could not interpret command (INVALID): " + string(originalResponse));
                case "NOT_FOUND"
                    error("MercuryiTC device UID not found (NOT_FOUND): " + string(originalResponse));
                case "N/A"
                    error("MercuryiTC - function does not apply to this device (N/A): " + string(originalResponse));
                case "DENIED"
                    error("MercuryiTC denied permission to change this parameter (DENIED): " + string(originalResponse));
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
