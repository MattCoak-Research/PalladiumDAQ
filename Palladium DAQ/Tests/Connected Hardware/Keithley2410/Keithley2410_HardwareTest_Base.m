classdef (Abstract) Keithley2410_HardwareTest_Base < matlab.unittest.TestCase
    %Keithley2410_HardwareTest_Base - Hardware-in-the-loop tests for the Keithley2410 driver,
    %shared by every connection type. NOT run by the build or CI: needs a real SourceMeter.
    %
    %This class holds all the tests and is abstract, so it is never run itself.
    %One small subclass per connection type supplies the connection settings by
    %implementing ConfigureConnection (see Keithley2410_HardwareTest_GPIB), and so
    %re-runs every test over that connection. To add another connection type,
    %copy the GPIB subclass and change ConfigureConnection (and the setup
    %notes at the top of the file).
    %
    %REQUIRED SETUP - the instrument and wiring these tests assume
    %--------------------------------------------------------------
    % * A Keithley 2400-series SourceMeter (2400, 2401, 2410...), powered on,
    %   connected to this PC by the interface being tested, with the
    %   communication settings at their defaults (GPIB address 24, LF terminators).
    % * A 1.09 kOhm resistor connected across the OUTPUT terminals, with 4-wire
    %   (remote) sensing - the INPUT/OUTPUT front/rear switch on whichever
    %   terminals the resistor is plugged into. Nothing else on the output.
    %   (The expected value and tolerance are ResistorOhms and ResistorRelTol.)
    % * Nobody touching the front panel while the tests run: every test starts
    %   with *RST and sets up its own state, so any panel settings are lost.
    %
    %SAFETY - what the tests will source
    %-----------------------------------
    % * Never more than 0.1 mA, or 1 V. Every source level goes through
    %   SetSource, which refuses a level beyond MaxTestCurrent_A (80 uA) when
    %   sourcing current or MaxTestVoltage_V (0.08 V) when sourcing voltage.
    %   Into 1.09 kOhm these give at most 87 mV and 73 uA.
    % * Compliance is set to match the resistor, so even a failed or shorted
    %   resistor cannot pass much: 0.1 V when sourcing current, 0.1 mA when
    %   sourcing voltage (1 kOhm x 0.1 mA = 0.1 V). Tests that want the
    %   compliance to trip only lower these limits.
    % * The output is turned off, and *RST sent, after every test.
    %
    %RUNNING
    %-------
    %   runtests("Keithley2410_HardwareTest_GPIB")
    %   runtests("Keithley2410_HardwareTest_GPIB", ProcedureName="testMeasure")
    %with Palladium DAQ on the path (the folder is not on the build's test path:
    %the file names don't start or end with "test" so runtests(folder) skips them too).

    %% Constants
    properties (Constant)
        ResistorOhms = 1090;                    %Value of the resistor on the output
        ResistorRelTol = 0.03;                  %Allowed relative error on resistance and the values derived from it (resistor tolerance, contact and lead resistance)
        MaxTestCurrent_A = 80e-6;               %Largest current any test may source (limit given: 0.1 mA)
        MaxTestVoltage_V = 0.08;                %Largest voltage any test may source (limit given: 1 V; this is also what stays under 0.1 mA)
        ComplianceVoltage_V = 0.1;              %Voltage compliance when sourcing current
        ComplianceCurrent_A = 100e-6;           %Current compliance when sourcing voltage
        MidCurrent_A = 50e-6;                   %A typical current to source
        MidVoltage_V = 0.05;                    %A typical voltage to source
    end

    %% Properties
    properties
        Instrument;                             %The Keithley2410 under test, connected and initialised by TestMethodSetup
    end

    properties (TestParameter)
        SourceMode = {"Current", "Voltage"};    %Source function to test in
        MeasMode = {"Resistance", "Voltage", "Current"};    %MeasMode (which column comes first) to test
        OtherMeasMode = {"Voltage", "Current"}; %The MeasModes that don't measure resistance
    end

    %% Connection type (implemented by each subclass)
    methods (Abstract, Access = protected)
        ConfigureConnection(testCase, instrument);  %Set Connection_Type and the address/settings for it on the (unconnected) instrument
    end

    %% Setup and teardown
    methods (TestMethodSetup)
        function connectAndInitialise(testCase)
            %Connect, then put the instrument into a known state, sourcing current
            testCase.Instrument = Palladium.Instruments.Keithley2410();
            testCase.ConfigureConnection(testCase.Instrument);
            testCase.addTeardown(@() testCase.shutDown());

            %Connect checks the instrument's source function against SourceMode,
            %and the instrument may be in any state. That check comes after the
            %connection is open, so a mismatch is fine here: initialise next
            try
                testCase.Instrument.Connect();
            catch err
                if err.identifier ~= "Keithley2410:SourceModeMismatch"
                    rethrow(err);
                end
            end
            try
                testCase.Instrument.QueryString("*IDN?");
            catch err
                testCase.assertFail("Could not connect to the Keithley 2410 (see the setup notes at the top of Keithley2410_HardwareTest_Base.m): " + err.message);
            end

            testCase.Initialise("Current");
        end
    end

    %% Helpers
    methods (Access = protected)

        function shutDown(testCase)
            %Leave the instrument safe (source off, trigger stopped), then disconnect.
            %Never errors, so it can't hide the failure of the test itself
            k = testCase.Instrument;
            try
                k.WriteCommand(":ABOR");
                k.WriteCommand(":OUTP OFF");
                k.WriteCommand("*RST");
            catch
            end
            try
                k.Close();
            catch
            end
        end

        function Initialise(testCase, sourceMode)
            %Reset the instrument and set it up, with the output off, to source
            %sourceMode ("Current" or "Voltage") into the resistor: 4-wire sensing,
            %compliance for the resistor, source at zero, manual ohms, 1 NPLC,
            %and V, I and R measured together. Sets the driver to match
            k = testCase.Instrument;
            w = @(command) k.WriteCommand(command);

            w(":ABOR");
            w("*RST");
            w("*CLS");
            w(":OUTP OFF");
            w(":SYST:RSEN ON");

            %Measure voltage, current and resistance on each reading
            w(":SENS:FUNC:CONC ON");
            w(":SENS:FUNC:ON ""VOLT:DC"",""CURR:DC"",""RES""");
            w(":SENS:RES:MODE MAN");        %Auto-ohms controls the source itself, so the level could not be set
            w(":SENS:RES:OCOM OFF");
            w(":SENS:CURR:NPLC 1");         %All functions share one NPLC setting

            %The source range must be set AFTER the manual-ohms setting, or the
            %instrument rejects changes of source level (-221 Settings conflict)
            switch(sourceMode)
                case("Current")
                    w(":SOUR:FUNC CURR");
                    w(":SOUR:CURR:RANG 1E-4");
                    w(":SOUR:CURR:LEV 0");
                    w(":SENS:VOLT:PROT " + testCase.ComplianceVoltage_V);
                case("Voltage")
                    w(":SOUR:FUNC VOLT");
                    w(":SOUR:VOLT:RANG 0.2");
                    w(":SOUR:VOLT:LEV 0");
                    w(":SENS:CURR:PROT " + testCase.ComplianceCurrent_A);
                otherwise
                    error("Initialise: unknown source mode " + sourceMode);
            end
            w(":FORM:ELEM VOLT,CURR,RES");  %Reset by *RST; the driver's Connect sets it again

            k.SourceMode = k.SourceType(sourceMode);
            k.MeasMode = k.MeasType("Resistance");
            k.OffsetComp = false;

            testCase.assertEmpty(testCase.ReadErrors(), "Instrument reported errors during initialisation");
            testCase.assertEqual(testCase.OutputIsOn(), false, "Output should be off after initialisation");
        end

        function SetSource(testCase, level, enableOutput)
            %Set the source level through the driver - the only way the tests
            %set one - after checking it is within the test limits
            k = testCase.Instrument;
            switch(string(k.SourceMode))
                case("Current");    limit = testCase.MaxTestCurrent_A;
                case("Voltage");    limit = testCase.MaxTestVoltage_V;
                otherwise
                    error("SetSource: unknown source mode");
            end
            if abs(level) > limit
                error("Keithley2410_HardwareTest:UnsafeLevel", "Test tried to source %g, beyond the limit of %g", level, limit);
            end
            k.SetSourceLevel(level, enableOutput);
        end

        function level = MidLevel(testCase)
            %A typical source level for the current source mode
            if string(testCase.Instrument.SourceMode) == "Current"
                level = testCase.MidCurrent_A;
            else
                level = testCase.MidVoltage_V;
            end
        end

        function level = MaxLevel(testCase)
            %Largest source level allowed in the current source mode
            if string(testCase.Instrument.SourceMode) == "Current"
                level = testCase.MaxTestCurrent_A;
            else
                level = testCase.MaxTestVoltage_V;
            end
        end

        function errors = ReadErrors(testCase)
            %Empty the instrument's error queue, returning the messages
            errors = strings(0, 1);
            for i = 1 : 20
                reply = testCase.Instrument.QueryString(":SYST:ERR?");
                if startsWith(reply, "0,") || startsWith(reply, "+0,")
                    return;
                end
                errors(end+1, 1) = reply; %#ok<AGROW>
            end
        end

        function tf = OutputIsOn(testCase)
            tf = testCase.Instrument.QueryDouble("OUTP?") == 1;
        end

        function verifyNoInstrumentErrors(testCase)
            testCase.verifyEmpty(testCase.ReadErrors(), "The instrument reported errors");
        end

        function verifyResistance(testCase, actual, message)
            testCase.verifyEqual(actual, testCase.ResistorOhms, "RelTol", testCase.ResistorRelTol, message);
        end

        function lineFrequency = LineFrequency(testCase)
            lineFrequency = testCase.Instrument.QueryDouble("SYST:LFR?");
        end

        function row = DataRowFields(testCase, dataRow)
            %Split a Measure data row by the MeasMode in use, into a struct with
            %fields Resistance (NaN if not measured), Current, Voltage, SourceLevel, Compliance
            k = testCase.Instrument;
            switch(string(k.MeasMode))
                case("Resistance"); row = struct("Resistance", dataRow(1), "Current", dataRow(2), "Voltage", dataRow(3), "SourceLevel", dataRow(4), "Compliance", dataRow(5));
                case("Voltage");    row = struct("Resistance", NaN, "Voltage", dataRow(1), "Current", dataRow(2), "SourceLevel", dataRow(3), "Compliance", dataRow(4));
                case("Current");    row = struct("Resistance", NaN, "Current", dataRow(1), "Voltage", dataRow(2), "SourceLevel", dataRow(3), "Compliance", dataRow(4));
            end
        end

        function [expectedVoltage, expectedCurrent] = ExpectedVI(testCase, level)
            %Voltage and current the resistor should have for a source level
            if string(testCase.Instrument.SourceMode) == "Current"
                expectedCurrent = level;
                expectedVoltage = level * testCase.ResistorOhms;
            else
                expectedVoltage = level;
                expectedCurrent = level / testCase.ResistorOhms;
            end
        end

        function verifyVI(testCase, voltage, current, level, message)
            %Check a measured voltage and current against the resistor, for a source
            %level. Absolute tolerances cover offsets at small signals
            [expectedVoltage, expectedCurrent] = testCase.ExpectedVI(level);
            testCase.verifyEqual(voltage, expectedVoltage, "RelTol", testCase.ResistorRelTol, "AbsTol", 200e-6, message + " (voltage)");
            testCase.verifyEqual(current, expectedCurrent, "RelTol", testCase.ResistorRelTol, "AbsTol", 200e-9, message + " (current)");
        end

    end

    %% Tests - connection
    methods (Test)

        function testIdentity(testCase)
            idn = testCase.Instrument.QueryString("*IDN?");
            testCase.verifyMatches(idn, "(?i)KEITHLEY.*MODEL 24\d\d", "Not a Keithley 2400-series instrument: " + idn);
        end

        function testConnectSetsDataElements(testCase)
            %Connect sets the reading to voltage, current and resistance
            k = testCase.Instrument;
            k.WriteCommand(":FORM:ELEM VOLT");
            testCase.verifyEqual(string(k.QueryString(":FORM:ELEM?")), "VOLT");

            k.Close();
            k.Connect();
            testCase.verifyEqual(string(k.QueryString(":FORM:ELEM?")), "VOLT,CURR,RES");
        end

        function testCloseDisconnects(testCase)
            k = testCase.Instrument;
            k.Close();
            testCase.verifyError(@() k.QueryString("*IDN?"), "QueryStringError:NotConnected");
        end

        function testCloseWhenNotConnectedDoesNothing(testCase)
            k = testCase.Instrument;
            k.Close();
            testCase.verifyWarningFree(@() k.Close());
        end

        function testReconnectAfterClose(testCase)
            k = testCase.Instrument;
            k.Close();
            k.Connect();
            testCase.verifyMatches(k.QueryString("*IDN?"), "(?i)KEITHLEY");
        end

        function testConnectSucceedsWhenSourceModeMatches(testCase, SourceMode)
            k = testCase.Instrument;
            testCase.Initialise(SourceMode);
            k.Close();
            testCase.verifyWarningFree(@() k.Connect());
            testCase.verifyEqual(string(k.GetSourceMode()), string(SourceMode));
        end

        function testConnectErrorsWhenSourceModeMismatches(testCase)
            %The instrument is sourcing current, so a driver set to Voltage must refuse
            k = testCase.Instrument;
            k.Close();
            k.SourceMode = k.SourceType("Voltage");
            testCase.verifyError(@() k.Connect(), "Keithley2410:SourceModeMismatch");
        end

    end

    %% Tests - reading the instrument's settings
    methods (Test)

        function testGetSourceMode(testCase, SourceMode)
            testCase.Initialise(SourceMode);
            testCase.verifyEqual(string(testCase.Instrument.GetSourceMode()), string(SourceMode));
        end

        function testGetSourceModeReadsInstrumentNotDriver(testCase)
            %The instrument sources current; the driver being set to Voltage must not change what it reads
            k = testCase.Instrument;
            k.SourceMode = k.SourceType("Voltage");
            testCase.verifyEqual(string(k.GetSourceMode()), "Current");
        end

        function testGetFourWireEnabledStatus(testCase)
            k = testCase.Instrument;
            testCase.verifyTrue(k.GetFourWireEnabledStatus());
            k.WriteCommand(":SYST:RSEN OFF");
            testCase.verifyFalse(k.GetFourWireEnabledStatus());
            k.WriteCommand(":SYST:RSEN ON");
            testCase.verifyTrue(k.GetFourWireEnabledStatus());
        end

        function testGetComplianceLevel(testCase, SourceMode)
            %Compliance is a voltage (mV) when sourcing current, a current (mA) when sourcing voltage
            testCase.Initialise(SourceMode);
            [value, str] = testCase.Instrument.GetComplianceLevel();
            if SourceMode == "Current"
                testCase.verifyEqual(value, testCase.ComplianceVoltage_V, "AbsTol", 1e-9);
                testCase.verifyEqual(str, "100 mV");
            else
                testCase.verifyEqual(value, testCase.ComplianceCurrent_A, "AbsTol", 1e-12);
                testCase.verifyEqual(str, "0.1 mA");
            end
        end

        function testGetComplianceLevelFollowsInstrument(testCase)
            testCase.Instrument.WriteCommand(":SENS:VOLT:PROT 0.05");
            value = testCase.Instrument.GetComplianceLevel();
            testCase.verifyEqual(value, 0.05, "AbsTol", 1e-9);
        end

        function testGetNPLC(testCase, MeasMode)
            %Each MeasMode reads the NPLC of its own function (the instrument shares
            %one setting between them) and converts it to seconds with the line frequency
            k = testCase.Instrument;
            k.MeasMode = k.MeasType(MeasMode);
            for nplc = [0.1 1 5]
                k.WriteCommand(":SENS:CURR:NPLC " + nplc);
                [readNplc, integrationTime] = k.GetNPLC();
                testCase.verifyEqual(readNplc, nplc, "AbsTol", 1e-9);
                testCase.verifyEqual(integrationTime, nplc / testCase.LineFrequency(), "AbsTol", 1e-9);
            end
        end

        function testGetSourceLevel(testCase, SourceMode)
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            level = testCase.MidLevel();

            testCase.SetSource(level, false);
            [readLevel, enabled] = k.GetSourceLevel();
            testCase.verifyEqual(readLevel, level, "RelTol", 1e-6);
            testCase.verifyFalse(enabled);

            testCase.SetSource(-level, true);
            [readLevel, enabled] = k.GetSourceLevel();
            testCase.verifyEqual(readLevel, -level, "RelTol", 1e-6);
            testCase.verifyTrue(enabled);
            testCase.verifyNoInstrumentErrors();
        end

        function testCollectMetaData(testCase, SourceMode)
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            k.WriteCommand(":SENS:CURR:NPLC 2");
            metadata = k.CollectMetaData();

            testCase.verifyEqual(sort(string(fieldnames(metadata))), sort(["ComplianceLevel"; "SourceMode"; "NumPowerLineCycles"; "IntegrationTime_s"; "FourWireMode"]));
            testCase.verifyEqual(string(metadata.SourceMode), string(SourceMode));
            testCase.verifyEqual(metadata.NumPowerLineCycles, 2, "AbsTol", 1e-9);
            testCase.verifyEqual(metadata.IntegrationTime_s, 2 / testCase.LineFrequency(), "AbsTol", 1e-9);
            testCase.verifyTrue(metadata.FourWireMode);
            if SourceMode == "Current"
                testCase.verifyEqual(metadata.ComplianceLevel, "100 mV");
            else
                testCase.verifyEqual(metadata.ComplianceLevel, "0.1 mA");
            end
        end

        function testGetSweepUnitsString(testCase, SourceMode)
            %Sweep limits come from the instrument: its voltage protection limit, or the 2410's 1.05 A
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            [str, limits, xlabelStr, ylabelStr] = k.GetSweepUnitsString();

            testCase.verifyEqual(limits(1), -limits(2));
            testCase.verifyGreaterThan(limits(2), 0);
            headers = k.GetHeaders();
            testCase.verifyEqual(ylabelStr, headers(1));
            if SourceMode == "Current"
                testCase.verifyEqual(str, "A");
                testCase.verifyEqual(xlabelStr, "Source Current (A)");
                testCase.verifyEqual(limits, 1.05 * [-1 1]);
            else
                testCase.verifyEqual(str, "V");
                testCase.verifyEqual(xlabelStr, "Source Voltage (V)");
                testCase.verifyEqual(limits(2), abs(k.QueryDouble(":SOUR:VOLT:PROT?")), "RelTol", 1e-6);
            end
        end

        function testGetHeadersMatchDataRow(testCase, SourceMode, MeasMode)
            %Headers, units and the data row from Measure line up, in every combination
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            k.MeasMode = k.MeasType(MeasMode);
            testCase.SetSource(testCase.MidLevel(), true);

            [headers, units] = k.GetHeaders();
            dataRow = k.Measure();
            testCase.verifyEqual(numel(headers), numel(dataRow));
            testCase.verifyEqual(numel(units), numel(dataRow));
            testCase.verifyTrue(startsWith(headers(1), k.Name + " - " + MeasMode), "The quantity MeasMode names should be first");
            testCase.verifyTrue(endsWith(headers(end), "Compliance Limited"));
        end

    end

    %% Tests - source control
    methods (Test)

        function testSetSourceLevel(testCase, SourceMode)
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            level = testCase.MidLevel();

            testCase.SetSource(level, true);
            testCase.verifyTrue(testCase.OutputIsOn());
            testCase.verifyEqual(k.GetSourceLevel(), level, "RelTol", 1e-6);

            testCase.SetSource(level / 2, false);
            testCase.verifyFalse(testCase.OutputIsOn());
            testCase.verifyEqual(k.GetSourceLevel(), level / 2, "RelTol", 1e-6);
            testCase.verifyNoInstrumentErrors();
        end

        function testSetSourceLevelToZero(testCase, SourceMode)
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            testCase.SetSource(testCase.MidLevel(), true);
            testCase.SetSource(0, true);
            testCase.verifyEqual(k.GetSourceLevel(), 0, "AbsTol", 1e-12);
            testCase.verifyTrue(testCase.OutputIsOn());
        end

        function testSetNewSweepStepValueTurnsOutputOn(testCase, SourceMode)
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            level = testCase.MidLevel();

            testCase.verifyFalse(testCase.OutputIsOn());
            k.SetNewSweepStepValue(level);
            testCase.verifyTrue(testCase.OutputIsOn());
            testCase.verifyEqual(k.GetSourceLevel(), level, "RelTol", 1e-6);
        end

        function testSetSourceLevelInvalidSourceMode(testCase)
            k = testCase.Instrument;
            k.SourceMode = categorical("None");
            testCase.verifyError(@() k.SetSourceLevel(0, false), "Keithley2410:InvalidSourceMode");
        end

        function testSourceLevelIsNotChangedByMeasure(testCase, SourceMode)
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            level = testCase.MidLevel();
            testCase.SetSource(level, true);
            k.Measure();
            testCase.verifyEqual(k.GetSourceLevel(), level, "RelTol", 1e-6);
        end

    end

    %% Tests - measuring
    methods (Test)

        function testMeasure(testCase, SourceMode, MeasMode)
            %A reading of the resistor, in every source mode and MeasMode combination
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            k.MeasMode = k.MeasType(MeasMode);
            level = testCase.MidLevel();
            testCase.SetSource(level, true);

            row = testCase.DataRowFields(k.Measure());

            testCase.verifyVI(row.Voltage, row.Current, level, "Measure " + SourceMode + " / " + MeasMode);
            testCase.verifyEqual(row.SourceLevel, level, "RelTol", 1e-6, "Source level column");
            testCase.verifyEqual(row.Compliance, 0, "Compliance flag");
            if MeasMode == "Resistance"
                testCase.verifyResistance(row.Resistance, "Measured resistance");
            else
                testCase.verifyTrue(isnan(row.Resistance));
            end
            testCase.verifyNoInstrumentErrors();
        end

        function testMeasureTurnsOutputOnIfOff(testCase, SourceMode)
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            testCase.SetSource(testCase.MidLevel(), false);
            testCase.verifyFalse(testCase.OutputIsOn());

            row = testCase.DataRowFields(k.Measure());

            testCase.verifyTrue(testCase.OutputIsOn());
            testCase.verifyResistance(row.Resistance, "Measured resistance");
            testCase.verifyNoInstrumentErrors();
        end

        function testMeasureNegativeSource(testCase, SourceMode)
            %Negative source gives negative V and I, and the same positive resistance
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            level = -testCase.MidLevel();
            testCase.SetSource(level, true);

            row = testCase.DataRowFields(k.Measure());

            testCase.verifyVI(row.Voltage, row.Current, level, "Negative source");
            testCase.verifyResistance(row.Resistance, "Resistance at negative source");
            testCase.verifyLessThan(row.Voltage, 0);
            testCase.verifyLessThan(row.Current, 0);
        end

        function testMeasureZeroSource(testCase, SourceMode)
            %With nothing sourced, nothing flows: just the instrument's small offsets
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            testCase.SetSource(0, true);

            row = testCase.DataRowFields(k.Measure());

            testCase.verifyEqual(row.Voltage, 0, "AbsTol", 1e-3);
            testCase.verifyEqual(row.Current, 0, "AbsTol", 1e-6);
            testCase.verifyEqual(row.Compliance, 0);
        end

        function testMeasureStepsAreLinear(testCase, SourceMode)
            %Step the source the way a Sweep Control does, up to the test limit and
            %back through zero to negative: V against I should be a straight line of slope R
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            levels = linspace(-testCase.MaxLevel(), testCase.MaxLevel(), 9);
            voltages = zeros(size(levels));
            currents = zeros(size(levels));
            for i = 1 : numel(levels)
                k.SetNewSweepStepValue(levels(i));
                row = testCase.DataRowFields(k.Measure());
                voltages(i) = row.Voltage;
                currents(i) = row.Current;
                testCase.verifyEqual(row.SourceLevel, levels(i), "AbsTol", 1e-12, "Source level column, step " + i);
            end

            fit = polyfit(currents, voltages, 1);
            testCase.verifyResistance(fit(1), "Resistance from the slope of V against I");
            residuals = voltages - polyval(fit, currents);
            testCase.verifyLessThan(max(abs(residuals)), 0.005 * max(abs(voltages)), "Largest deviation from a straight line");
            testCase.verifyEqual(fit(2), 0, "AbsTol", 1e-3, "Intercept of V against I");
            testCase.verifyNoInstrumentErrors();
        end

        function testMeasureIsRepeatable(testCase, SourceMode)
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            testCase.SetSource(testCase.MidLevel(), true);
            resistances = zeros(1, 10);
            for i = 1 : numel(resistances)
                row = testCase.DataRowFields(k.Measure());
                resistances(i) = row.Resistance;
            end
            testCase.verifyLessThan(std(resistances) / mean(resistances), 0.005, "Scatter of 10 resistance readings");
        end

        function testMeasureWithOffsetComp(testCase, SourceMode)
            %Offset-compensated resistance: measured at zero and at the source level.
            %The source must be put back to its level, and the output left on
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            k.OffsetComp = true;
            level = testCase.MidLevel();
            testCase.SetSource(level, true);

            row = testCase.DataRowFields(k.Measure());

            testCase.verifyResistance(row.Resistance, "Offset-compensated resistance");
            testCase.verifyEqual(row.SourceLevel, level, "RelTol", 1e-6, "Source level column");
            testCase.verifyVI(row.Voltage, row.Current, level, "Offset comp");
            [readLevel, enabled] = k.GetSourceLevel();
            testCase.verifyEqual(readLevel, level, "RelTol", 1e-6, "Source level should be restored after the zero reading");
            testCase.verifyTrue(enabled);
            testCase.verifyNoInstrumentErrors();
        end

        function testOffsetCompNeedsResistanceMode(testCase, OtherMeasMode)
            %Only Resistance MeasMode can offset-compensate: the others must error, not give wrong data
            k = testCase.Instrument;
            k.MeasMode = k.MeasType(OtherMeasMode);
            k.OffsetComp = true;
            testCase.SetSource(testCase.MidLevel(), true);
            testCase.verifyError(@() k.Measure(), "Keithley2410:OffsetCompNotResistanceMode");
        end

        function testReadData(testCase, SourceMode)
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            level = testCase.MidLevel();
            testCase.SetSource(level, true);

            [voltage, current, resistance] = k.ReadData();

            testCase.verifyVI(voltage, current, level, "ReadData");
            testCase.verifyResistance(resistance, "ReadData resistance");
        end

        function testReadDataResistanceIsNaNUnlessResistanceMode(testCase, OtherMeasMode)
            k = testCase.Instrument;
            k.MeasMode = k.MeasType(OtherMeasMode);
            testCase.SetSource(testCase.MidLevel(), true);
            [~, ~, resistance] = k.ReadData();
            testCase.verifyTrue(isnan(resistance));
        end

        function testMeasureSingleShotData(testCase)
            %MEAS? reconfigures the instrument (it sets its own ohms source level
            %and range) so only the resistor's own values can be checked. The
            %instrument's compliance still limits what it can drive
            k = testCase.Instrument;
            testCase.SetSource(testCase.MidCurrent_A, true);

            [voltage, current, resistance] = k.MeasureSingleShotData();

            testCase.verifyResistance(resistance, "MEAS? resistance");
            testCase.verifyEqual(voltage / current, testCase.ResistorOhms, "RelTol", testCase.ResistorRelTol, "V / I from MEAS?");
            testCase.verifyLessThanOrEqual(abs(current), testCase.MaxTestCurrent_A * 1.05, "MEAS? must not drive more than the test limit");
        end

    end

    %% Tests - compliance
    methods (Test)

        function testIsAtComplianceLimitFalseNormally(testCase, SourceMode)
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            testCase.SetSource(testCase.MidLevel(), true);
            k.ReadData();
            testCase.verifyFalse(k.IsAtComplianceLimit());
        end

        function testComplianceLimitIsDetected(testCase, SourceMode)
            %Lower the compliance below what the resistor needs: the flag goes up
            %and the compliance quantity is held at its limit. (Limits are only
            %ever lowered, so this can't pass more than the normal tests)
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            level = testCase.MidLevel();
            if SourceMode == "Current"
                limit = 0.02;       %50 uA would need 54 mV
                k.WriteCommand(":SENS:VOLT:PROT " + limit);
            else
                limit = 40e-6;      %0.05 V would need 46 uA
                k.WriteCommand(":SENS:CURR:PROT " + limit);
            end
            testCase.SetSource(level, true);

            row = testCase.DataRowFields(k.Measure());

            testCase.verifyEqual(row.Compliance, 1, "Compliance flag column");
            testCase.verifyTrue(k.IsAtComplianceLimit());
            if SourceMode == "Current"
                testCase.verifyLessThanOrEqual(abs(row.Voltage), limit * 1.05, "Voltage should be held at the compliance limit");
            else
                testCase.verifyLessThanOrEqual(abs(row.Current), limit * 1.05, "Current should be held at the compliance limit");
            end
        end

        function testComplianceFlagClearsWhenLimitRaised(testCase, SourceMode)
            testCase.Initialise(SourceMode);
            k = testCase.Instrument;
            if SourceMode == "Current"
                k.WriteCommand(":SENS:VOLT:PROT 0.02");
            else
                k.WriteCommand(":SENS:CURR:PROT 40E-6");
            end
            testCase.SetSource(testCase.MidLevel(), true);
            k.Measure();
            testCase.assertTrue(k.IsAtComplianceLimit());

            if SourceMode == "Current"
                k.WriteCommand(":SENS:VOLT:PROT " + testCase.ComplianceVoltage_V);
            else
                k.WriteCommand(":SENS:CURR:PROT " + testCase.ComplianceCurrent_A);
            end
            row = testCase.DataRowFields(k.Measure());
            testCase.verifyEqual(row.Compliance, 0);
            testCase.verifyResistance(row.Resistance, "Resistance once out of compliance");
        end

    end

    %% Tests - status and triggering
    methods (Test)

        function testClearStatus(testCase)
            %Send a command the instrument rejects, to put an error in its queue
            k = testCase.Instrument;
            k.WriteCommand("NOTACOMMAND");
            reply = k.QueryString(":SYST:ERR?");
            testCase.assertFalse(startsWith(reply, "0,") || startsWith(reply, "+0,"), "Expected an error in the queue to clear, got: " + reply);

            k.WriteCommand("NOTACOMMAND");
            k.ClearStatus();
            testCase.verifyEmpty(testCase.ReadErrors(), "The error queue should be empty after ClearStatus");
        end

        function testSetLocalDoesNotDisturbInstrument(testCase)
            %Over GPIB this does nothing (the instrument only accepts it over RS-232):
            %it must not error or upset the connection
            k = testCase.Instrument;
            k.SetLocal();
            testCase.verifyMatches(k.QueryString("*IDN?"), "(?i)KEITHLEY");
            testCase.verifyNoInstrumentErrors();
        end

        function testArmTrigger(testCase)
            %Arms the trigger model for continuous readings with the output on. While
            %it runs the instrument does not answer queries, so abort straight away
            k = testCase.Instrument;
            testCase.SetSource(testCase.MidCurrent_A, false);

            k.ArmTrigger();
            k.WriteCommand(":ABOR");

            testCase.verifyTrue(testCase.OutputIsOn(), "ArmTrigger should turn the output on");
            testCase.verifyGreaterThan(k.QueryDouble(":ARM:SEQ:LAY:COUN?"), 1e37, "Arm count should be infinite");
            testCase.verifyNoInstrumentErrors();
        end

        function testFetchLatestData(testCase)
            %The first element of the latest reading - the voltage, from the data
            %elements Connect sets. Documented as a building block for triggered
            %measurements, so it should work after any reading
            k = testCase.Instrument;
            level = testCase.MidCurrent_A;
            testCase.SetSource(level, true);
            k.ReadData();

            latest = k.FetchLatestData();

            testCase.verifyEqual(latest, level * testCase.ResistorOhms, "RelTol", testCase.ResistorRelTol);
        end

    end
end
