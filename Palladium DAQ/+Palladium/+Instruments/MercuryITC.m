classdef MercuryITC < Palladium.Core.Instrument
    %MercuryITC - Instrument driver for the Oxford Instruments Mercury iTC temperature controller.
    %Logs one reading per device board each measurement tick: temperature (K)
    %for temperature sensors, heater power (W) for heaters, valve opening (%)
    %for auxiliary (gas flow) boards and pressure for pressure sensors. When it
    %connects, the driver reads the instrument's device catalogue (`SYS:CAT`)
    %and fills each `Channel_n_Name` left at "Default" with the next device
    %address found, such as `DEV:MB1.T1:TEMP`. Up to 8 devices are logged, one
    %data column each.
    %
    %The temperature control loops can be driven from scripts or sequences -
    %`SetTemperatureSetpoint`, `SetPIDValues`, `EnablePIDControl`,
    %`AssignHeaterToLoop` and so on - but there is no Instrument Control tab
    %for them.
    %
    %The Mercury iTC connects over Ethernet (always port 7020) or RS-232 / USB
    %(Serial, set to 115200 baud here), and must be set to use its SCPI
    %command set rather than the legacy one. Level meter (LVL) signals and the
    %Lambda and HelioxX control modes are not implemented. Ported from the
    %mercuryITC.py driver (Benno Meier, 2015), and checked against the Mercury
    %iTC User Manual (MAN-NS-0014, Revision B), chapter 10.

    %% Properties (Constant, Private)
    properties(Constant, Access = private)
        NumChannels = 8;                                        %Number of Channel_n_Name properties, so the maximum number of devices logged
    end

    %% Properties (Public)
    properties(Access = public)
        FullName = "Oxford Instruments Mercury iTC";            %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties(Access = public, SetObservable)
        Name = "MercuryITC";                                    %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.Ethernet;  %Type of connection to use to communicate with the instrument. Debug allows testing without a physical instrument.
        Channel_1_Name (1,1) string = "Default";                %Device address logged in column 1, e.g. "DEV:MB1.T1:TEMP". "Default" is filled from the device catalogue when connecting.
        Channel_2_Name (1,1) string = "Default";                %Device address logged in column 2, or "Default" to fill it from the device catalogue
        Channel_3_Name (1,1) string = "Default";                %Device address logged in column 3, or "Default" to fill it from the device catalogue
        Channel_4_Name (1,1) string = "Default";                %Device address logged in column 4, or "Default" to fill it from the device catalogue
        Channel_5_Name (1,1) string = "Default";                %Device address logged in column 5, or "Default" to fill it from the device catalogue
        Channel_6_Name (1,1) string = "Default";                %Device address logged in column 6, or "Default" to fill it from the device catalogue
        Channel_7_Name (1,1) string = "Default";                %Device address logged in column 7, or "Default" to fill it from the device catalogue
        Channel_8_Name (1,1) string = "Default";                %Device address logged in column 8, or "Default" to fill it from the device catalogue
    end

    %% Properties (Private)
    properties(Access = private)
        DeviceCatalogue string = strings(1, 0);                 %Addresses of the devices found on the instrument, read by GetDeviceCatalogue when connecting
    end

    %% Constructor
    methods
        function this = MercuryITC()
            %Set the supported connection types and default connection settings.

            %Ethernet and RS-232 / USB (which appears as a serial port);
            %VISA can address either
            this.DefineSupportedConnectionTypes(["Debug", "Ethernet", "Serial", "VISA"]);

            this.ConnectionSettings.Port = 7020;    %Fixed on the Mercury iTC

            %USB is fixed at 115200 baud, 8 data bits, 1 stop bit and no
            %parity; for RS-232 these must match the instrument's RS232
            %settings page. Commands end with LF
            this.ConnectionSettings.SerialSettings.BaudRate = 115200;
            this.ConnectionSettings.SerialSettings.StopBits = 1;
            this.ConnectionSettings.SerialSettings.Terminator = "LF";
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function AssignAuxToLoop(this, deviceAddress, auxUID)
            %Assign an auxiliary (gas flow) board to a temperature sensor's control loop.
            %Sets `LOOP:AUX`, so the loop can drive the gas flow valve
            %
            %Inputs:
            %   deviceAddress - the temperature sensor's address, e.g. "DEV:MB1.T1:TEMP"
            %   auxUID        - the auxiliary board's UID, e.g. "DB3.G1"

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
            %Assign a heater to a temperature sensor's control loop.
            %Sets `LOOP:HTR`. A loop needs a heater before PID control can
            %drive the temperature
            %
            %Inputs:
            %   deviceAddress - the temperature sensor's address, e.g. "DEV:MB1.T1:TEMP"
            %   heaterUID     - the heater's UID, e.g. "MB0.H1"

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

        function Connect(this)
            %Open the connection and read the instrument's device catalogue.
            %Fills any Channel_n_Name left at "Default" (see GetDeviceCatalogue)

            Connect@Palladium.Core.Instrument(this);
            this.DeviceCatalogue = this.GetDeviceCatalogue();
        end

        function DisablePIDControl(this, deviceAddress)
            %Switch a temperature sensor's control loop to manual (PID control off).
            %Sets `LOOP:ENAB` to OFF
            %
            %Inputs:
            %   deviceAddress - the temperature sensor's address, e.g. "DEV:MB1.T1:TEMP"

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
            %Switch a temperature sensor's control loop to automatic (PID control on).
            %Sets `LOOP:ENAB` to ON
            %
            %Inputs:
            %   deviceAddress - the temperature sensor's address, e.g. "DEV:MB1.T1:TEMP"

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

        function [deviceAddresses, catalogString] = GetDeviceCatalogue(this)
            %Read the list of devices on the instrument, and fill unset channels from it.
            %Sends `READ:SYS:CAT`, whose reply lists each device as
            %`DEV:<UID>:<TYPE>` (manual section 10.3.7). Each Channel_n_Name
            %still at "Default" is set to the device address at the same
            %position in the list
            %
            %Outputs:
            %   deviceAddresses - device addresses, e.g. ["DEV:MB1.T1:TEMP", "DEV:MB0.H1:HTR"]
            %   catalogString   - the instrument's reply

            if this.SimulationMode
                catalogString = "STAT:SYS:CAT:DEV:DB7.T1:TEMP:DEV:DB6.T1:TEMP:DEV:MB1.T1:TEMP";
            else
                catalogString = this.ReadValue("SYS:CAT");
            end

            %Splitting on ":DEV:" leaves each device's <UID>:<TYPE>; the
            %first piece is the STAT:SYS:CAT prefix, which is discarded
            deviceSegments = strsplit(catalogString, ":DEV:");
            deviceSegments(1) = [];
            deviceAddresses = "DEV:" + string(deviceSegments);

            for channelIndex = 1:this.NumChannels
                propName = "Channel_" + string(channelIndex) + "_Name";
                if this.(propName) == "Default" && channelIndex <= numel(deviceAddresses)
                    this.(propName) = deviceAddresses(channelIndex);
                end
            end
        end

        function [Headers, Units] = GetHeaders(this)
            %Data column headers and units for the values returned by Measure.
            %One column per catalogued device, up to 8, named after its
            %Channel_n_Name
            %
            %Outputs:
            %   Headers - e.g. "MercuryITC - DEV:MB1.T1:TEMP"
            %   Units   - matching units, from the device type: "K", "W", "%" or "mbar"

            if isempty(this.DeviceCatalogue)
                warning("MercuryITCWarning:EmptyDeviceCatalogue", "Device Catalogue empty in Mercury ITC - no modules found or GetDeviceCatalogue not yet called");
            end

            addresses = this.GetChannelAddresses();
            Headers = this.Name + " - " + addresses;
            Units = strings(1, numel(addresses));
            for i = 1:numel(addresses)
                Units(i) = this.GuessUnitFromDeviceAddress(addresses(i));
            end
        end

        function idnString = GetIDN(this)
            %Read the instrument's identity string (`*IDN?`).
            %
            %Outputs:
            %   idnString - e.g. "IDN:OXFORD INSTRUMENTS:MERCURY ITC:<serial>:<firmware>"

            if this.SimulationMode
                idnString = "SIMULATED MERCURY ITC";
                return;
            end

            idnString = this.ReadValue("*IDN?", "");
        end

        function isEnabled = GetPIDControlEnabled(this, deviceAddress)
            %Read whether a temperature sensor's control loop is in automatic (PID) mode.
            %
            %Inputs:
            %   deviceAddress - the temperature sensor's address, e.g. "DEV:MB1.T1:TEMP"
            %
            %Outputs:
            %   isEnabled - true for automatic (PID control on), false for manual

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
            %Read the PID values of a temperature sensor's control loop.
            %
            %Inputs:
            %   deviceAddress - the temperature sensor's address, e.g. "DEV:MB1.T1:TEMP"
            %
            %Outputs:
            %   P - proportional band, in K
            %   I - integral action time, in minutes
            %   D - derivative action time, in minutes

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

        function varargout = GetSensorInformation(this, deviceAddress, includeTemperature)
            %Read the voltage, current and resistance of a temperature sensor, and optionally its temperature.
            %
            %Inputs:
            %   deviceAddress      - the sensor's address, e.g. "DEV:MB1.T1:TEMP"
            %   includeTemperature - true to also read the temperature (default false)
            %
            %Outputs:
            %   varargout - voltage (V), current (A) and resistance (Ohms), then the
            %               temperature (K) if includeTemperature is true

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

        function value = GetSignal(this, deviceAddress, signalName)
            %Read one signal of a device, in base SI units.
            %Sends `READ:<deviceAddress>:SIG:<signalName>`, and removes the
            %SI prefix from the reply's units (e.g. mV becomes V)
            %
            %Inputs:
            %   deviceAddress - e.g. "DEV:MB1.T1:TEMP"
            %   signalName    - e.g. "TEMP", "VOLT", "CURR", "RES" or "POWR" (see the
            %                   signal tables in chapter 10 of the manual)
            %
            %Outputs:
            %   value - the reading

            arguments
                this;
                deviceAddress {mustBeTextScalar};
                signalName {mustBeTextScalar};
            end

            if this.SimulationMode
                value = this.GenerateSimulatedData(1, Baseline=273, Variance=0.1);
                return;
            end

            resultString = this.ReadValue(string(deviceAddress) + ":SIG:" + string(signalName));
            value = this.ParseSignalResponse(resultString);
        end

        function setpoint_K = GetTemperatureSetpoint(this, deviceAddress)
            %Read the temperature setpoint of a temperature sensor's control loop.
            %
            %Inputs:
            %   deviceAddress - the temperature sensor's address, e.g. "DEV:MB1.T1:TEMP"
            %
            %Outputs:
            %   setpoint_K - the setpoint (`LOOP:TSET`), in K

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

        function [dataRow] = Measure(this)
            %Read one signal from each channel's device, in the same order as GetHeaders.
            %The signal is chosen from the device type: TEMP for temperature
            %sensors, POWR for heaters, PERC for auxiliary boards and PRES for
            %pressure sensors. Other device types give NaN
            %
            %Outputs:
            %   dataRow - one reading per channel

            addresses = this.GetChannelAddresses();
            dataRow = nan(1, numel(addresses));

            for i = 1:numel(addresses)
                if this.SimulationMode
                    dataRow(i) = this.GenerateSimulatedData(1, Baseline=273, Variance=0.1);
                    continue;
                end

                signalName = this.GuessSignalNameFromDeviceAddress(addresses(i));
                if signalName ~= ""
                    dataRow(i) = this.GetSignal(addresses(i), signalName);
                end
            end
        end

        function resultString = ReadValue(this, command, readPrefix)
            %Send a READ command and return the instrument's reply.
            %
            %Inputs:
            %   command    - the noun to read, e.g. "SYS:CAT"
            %   readPrefix - prefix to send before it (default "READ:")
            %
            %Outputs:
            %   resultString - the reply, e.g. "STAT:SYS:CAT:DEV:MB1.T1:TEMP"

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

        function SetPIDValues(this, deviceAddress, P, I, D)
            %Set the PID values of a temperature sensor's control loop.
            %
            %Inputs:
            %   deviceAddress - the temperature sensor's address, e.g. "DEV:MB1.T1:TEMP"
            %   P             - proportional band, in K
            %   I             - integral action time, in minutes
            %   D             - derivative action time, in minutes

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

        function SetTemperatureSetpoint(this, deviceAddress, setpoint_K)
            %Set the temperature setpoint of a temperature sensor's control loop.
            %The loop needs a heater assigned (AssignHeaterToLoop) and PID
            %control on (EnablePIDControl) to drive the temperature
            %
            %Inputs:
            %   deviceAddress - the temperature sensor's address, e.g. "DEV:MB1.T1:TEMP"
            %   setpoint_K    - the setpoint, in K

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
            assert(achievedSetPt == setpoint_K, "MercuryITC:SetpointNotSet", "%s", "Failed to set temperature setpoint on " + string(deviceAddress) + ". Requested " + num2str(setpoint_K) + " K, achieved " + num2str(achievedSetPt) + " K.");
        end

        function resultString = SetValue(this, command)
            %Send a SET command and return the instrument's reply.
            %
            %Inputs:
            %   command - the noun and value to set, e.g. "DEV:MB1.T1:TEMP:LOOP:TSET:4.2"
            %
            %Outputs:
            %   resultString - the reply, which echoes the value set and ends in
            %                  VALID if it was accepted

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
            %Hide the GPIB address in the GUI - this driver does not support GPIB.

            propertiesToIgnore = {"GPIB_Address"};
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function addresses = GetChannelAddresses(this)
            %Device addresses of the logged channels: one per catalogued device, up to 8.
            %
            %Outputs:
            %   addresses - the Channel_n_Name values, as a string array

            numLogged = min(numel(this.DeviceCatalogue), this.NumChannels);
            addresses = strings(1, numLogged);
            for i = 1:numLogged
                addresses(i) = this.("Channel_" + string(i) + "_Name");
            end
        end

        function strVal = GetLoopString(this, deviceAddress, loopCommand)
            %Read a text setting of a temperature control loop, e.g. ENAB, HTR or AUX.
            %
            %Inputs:
            %   deviceAddress - the temperature sensor's address, e.g. "DEV:MB1.T1:TEMP"
            %   loopCommand   - the LOOP setting to read, e.g. "ENAB"
            %
            %Outputs:
            %   strVal - the setting, e.g. "ON"

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

        function value = GetLoopValue(this, deviceAddress, loopCommand)
            %Read a numeric setting of a temperature control loop, e.g. TSET, P, I or D.
            %
            %Inputs:
            %   deviceAddress - the temperature sensor's address, e.g. "DEV:MB1.T1:TEMP"
            %   loopCommand   - the LOOP setting to read, e.g. "TSET"
            %
            %Outputs:
            %   value - the setting

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

        function mult = GetSIPrefixMultiplier(~, unitToken)
            %Multiplier for the SI prefix of a units string, e.g. 1e-3 for "mK".
            %A unit with no prefix, e.g. "K", gives 1 (manual section 10.3.5)
            %
            %Inputs:
            %   unitToken - units string, e.g. "mV"
            %
            %Outputs:
            %   mult - the multiplier

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

        function signalName = GuessSignalNameFromDeviceAddress(~, deviceAddress)
            %Signal to read in Measure for a device, from its type, e.g. "TEMP" for "DEV:DB7.T1:TEMP".
            %Signal names are from the manual's signal tables (sections
            %10.3.11 TEMP, 10.3.15 HTR, 10.3.17 AUX and 10.3.18 PRES)
            %
            %Inputs:
            %   deviceAddress - a device address from the catalogue
            %
            %Outputs:
            %   signalName - "TEMP", "POWR", "PERC" or "PRES", or "" for other
            %                device types (e.g. LVL or PSU), which Measure
            %                records as NaN

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
            %Units of the signal read in Measure for a device, from its type, e.g. "K" for "DEV:DB7.T1:TEMP".
            %
            %Inputs:
            %   deviceAddress - a device address from the catalogue
            %
            %Outputs:
            %   unit - "K", "W", "%" or "mbar", or "??" for other device types

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

        function value = ParseSIPrefixedValue(~, valueString)
            %Convert a number joined to its units, e.g. "12.3mV", into base SI units.
            %
            %Inputs:
            %   valueString - "<number><prefix><unit>" or "<number><unit>", with a
            %                 one-letter unit
            %
            %Outputs:
            %   value - the number, scaled by its SI prefix

            siPrefixes = containers.Map(...
                {'M', 'k', 'm', 'u', char(181), 'n', 'p'}, ...   %char(181) is the micro sign, as in the Python reference
                {1e6, 1e3, 1e-3, 1e-6, 1e-6, 1e-9, 1e-12});

            %The last character is the unit; the one before is either a
            %prefix or the number's last digit
            prefixChar = valueString(end-1);

            if isstrprop(prefixChar, 'digit')
                value = str2double(valueString(1:end-1));
            elseif isKey(siPrefixes, prefixChar)
                value = str2double(valueString(1:end-2)) * siPrefixes(prefixChar);
            else
                error("MercuryITC:SIValueParseFailed", "%s", "Could not parse SI-prefixed value: " + string(valueString));
            end
        end

        function value = ParseSignalResponse(this, responseString)
            %Read the number from a STAT reply, in base SI units.
            %Handles a plain number (e.g. "...:TSET:4.321:VALID"), a number and
            %units as separate tokens (e.g. "...:SIG:VOLT:12.345:mV:VALID"), and
            %a number joined to its units (e.g. "...:SIG:TEMP:4.2310K")
            %
            %Inputs:
            %   responseString - the instrument's reply
            %
            %Outputs:
            %   value - the number

            tokens = this.StripAndCheckStatusToken(strsplit(char(responseString), ":"), responseString);
            lastToken = tokens{end};

            %Plain number
            directValue = str2double(lastToken);
            if ~isnan(directValue)
                value = directValue;
                return;
            end

            %Number and units as separate tokens
            if numel(tokens) >= 2 && ~isnan(str2double(tokens{end-1}))
                value = str2double(tokens{end-1}) * this.GetSIPrefixMultiplier(lastToken);
                return;
            end

            %Number joined to its units
            value = this.ParseSIPrefixedValue(lastToken);
        end

        function strVal = ParseStringResponse(this, responseString)
            %Read the text value, e.g. ON or OFF, from the end of a STAT reply.
            %
            %Inputs:
            %   responseString - the instrument's reply
            %
            %Outputs:
            %   strVal - the value

            tokens = this.StripAndCheckStatusToken(strsplit(char(responseString), ":"), responseString);
            strVal = string(tokens{end});
        end

        function confirmedStr = SetLoopString(this, deviceAddress, loopCommand, valueStr)
            %Set a text setting of a temperature control loop, e.g. ENAB, HTR or AUX.
            %
            %Inputs:
            %   deviceAddress - the temperature sensor's address, e.g. "DEV:MB1.T1:TEMP"
            %   loopCommand   - the LOOP setting, e.g. "ENAB"
            %   valueStr      - the value to set, e.g. "ON"
            %
            %Outputs:
            %   confirmedStr - the value echoed in the instrument's VALID reply

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

        function confirmedValue = SetLoopValue(this, deviceAddress, loopCommand, value)
            %Set a numeric setting of a temperature control loop, e.g. TSET, P, I or D.
            %
            %Inputs:
            %   deviceAddress - the temperature sensor's address, e.g. "DEV:MB1.T1:TEMP"
            %   loopCommand   - the LOOP setting, e.g. "TSET"
            %   value         - the value to set
            %
            %Outputs:
            %   confirmedValue - the value echoed in the instrument's VALID reply

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

        function tokens = StripAndCheckStatusToken(~, tokens, originalResponse)
            %Remove a trailing VALID from a split reply, or raise an error for an invalid-command reply.
            %The invalid replies are INVALID, NOT_FOUND, N/A and DENIED (manual
            %section 10.4, Table 39)
            %
            %Inputs:
            %   tokens           - the reply, split at its colons
            %   originalResponse - the whole reply, for error messages
            %
            %Outputs:
            %   tokens - the tokens without VALID

            if isempty(tokens)
                return;
            end

            lastToken = string(tokens{end});

            switch(upper(lastToken))
                case "VALID"
                    tokens(end) = [];
                case "INVALID"
                    error("MercuryITC:InvalidCommand", "%s", "MercuryiTC could not interpret command (INVALID): " + string(originalResponse));
                case "NOT_FOUND"
                    error("MercuryITC:DeviceUIDNotFound", "%s", "MercuryiTC device UID not found (NOT_FOUND): " + string(originalResponse));
                case "N/A"
                    error("MercuryITC:FunctionNotApplicable", "%s", "MercuryiTC - function does not apply to this device (N/A): " + string(originalResponse));
                case "DENIED"
                    error("MercuryITC:PermissionDenied", "%s", "MercuryiTC denied permission to change this parameter (DENIED): " + string(originalResponse));
            end
        end

    end
end
