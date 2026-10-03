classdef test_Instrument < matlab.unittest.TestCase
    % TEST_INSTRUMENT Tests for the Palladium.Core.Instrument base class.
    % Instrument is Abstract, so a minimal concrete implementation
    % (InstrumentTestingInstruments.StubInstrument, in the data folder) is
    % used to exercise the inherited functionality, with a fake device
    % handle standing in for real hardware.
    %
    % Not covered, as they need a real instrument or network connection:
    % the bodies of ConnectGPIB, ConnectSerial, ConnectTCPIP and
    % ConnectVISA (the StubInstrument overrides them to record that
    % Connect dispatched to them).

    %% Properties
    properties
        TestingDir = fullfile("..", "data", "Instrument Testing");
        Instrument;
        NumSamples = 20000;     %Large enough that sample statistics are tightly constrained
    end

    %% Properties (TestParameter)
    properties (TestParameter)
        %Which Connect* method each ConnectionType should dispatch to. USB
        %has no connection code of its own, it uses the VISA one
        ConnectDispatch = struct( ...
            "Ethernet", struct("Type", "Ethernet", "ConnectedVia", "Ethernet"), ...
            "GPIB", struct("Type", "GPIB", "ConnectedVia", "GPIB"), ...
            "Serial", struct("Type", "Serial", "ConnectedVia", "Serial"), ...
            "VISA", struct("Type", "VISA", "ConnectedVia", "VISA"), ...
            "USB", struct("Type", "USB", "ConnectedVia", "VISA"));

        %Which of the four address properties are shown in the GUI for each
        %ConnectionType ("" = none of them)
        VisibleAddressProperty = struct( ...
            "Debug", struct("Type", "Debug", "Visible", ""), ...
            "Ethernet", struct("Type", "Ethernet", "Visible", "IP_Address"), ...
            "GPIB", struct("Type", "GPIB", "Visible", "GPIB_Address"), ...
            "Serial", struct("Type", "Serial", "Visible", "Serial_Address"), ...
            "VISA", struct("Type", "VISA", "Visible", "VISA_Address"), ...
            "USB", struct("Type", "USB", "Visible", "VISA_Address"));   %USB connects through VISA

        %Every command-sending method, which must all refuse to run without
        %a connection
        NotConnectedCall = struct( ...
            "QueryString", struct("Call", @(instr) instr.QueryString("X?"), "ErrorId", "QueryStringError:NotConnected"), ...
            "QueryDouble", struct("Call", @(instr) instr.QueryDouble("X?"), "ErrorId", "QueryDoubleError:NotConnected"), ...
            "ReadString", struct("Call", @(instr) instr.ReadString(), "ErrorId", "ReadStringError:NotConnected"), ...
            "WriteCommand", struct("Call", @(instr) instr.WriteCommand("X"), "ErrorId", "WriteCommandError:NotConnected"));
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)

        function SeedRandomNumberGenerator(testCase)
            %Fix the seed so the statistical checks are deterministic, and
            %restore the previous generator state on completion
            testCase.addTeardown(@rng, rng);
            rng(1);
        end

        function PathSetup(testCase)
            %Add the stub instrument fixtures to the Path temporarily. The
            %fixture removes them again on test completion
            import matlab.unittest.fixtures.PathFixture
            testCase.applyFixture(PathFixture(testCase.TestingDir, IncludeSubfolders=true));
        end

    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)

        function CreateInstrument(testCase)
            testCase.Instrument = InstrumentTestingInstruments.StubInstrument();
        end

    end

    %% Tests
    methods (Test)

        %% Constructor and defaults
        function test_Constructor_DefaultPropertyValuesTest(testCase)
            testCase.verifyEqual(testCase.Instrument.GPIB_Address, 0);
            testCase.verifyEqual(testCase.Instrument.IP_Address, '192.0.0.0.0');
            testCase.verifyEqual(testCase.Instrument.Serial_Address, 'COM12');
            testCase.verifyEqual(testCase.Instrument.VISA_Address, "VISA_ADDRESS");
            testCase.verifyFalse(testCase.Instrument.SimulationMode);
            testCase.verifyEmpty(testCase.Instrument.LastFullDataRow);
            testCase.verifyEmpty(testCase.Instrument.FullHeadersRow);
            testCase.verifyEmpty(testCase.Instrument.FileWriteDetails);
        end

        function test_Constructor_DefaultConnectionSettingsTest(testCase)
            settings = testCase.Instrument.GetConnectionSettingsForTest();

            testCase.verifyEqual(settings.GPIB_BoardIndex, 0);
            testCase.verifyEqual(settings.Port, 5025);
            testCase.verifyEqual(settings.GPIB_Terminators, ["CR/LF", "CR/LF"]);
            testCase.verifyEqual(settings.GPIB_Timeout, 10);
            testCase.verifyEqual(settings.SerialSettings, struct("BaudRate", 9600, "DataBits", 8, "Parity", 'none', "StopBits", 2, "Terminator", 'LF'));
        end

        function test_Constructor_AbstractClassCannotBeInstantiatedTest(testCase)
            testCase.verifyError(@() Palladium.Core.Instrument(), "MATLAB:class:abstract");
        end

        %% Address property validation
        function test_GPIBAddress_AcceptsValuesInRangeTest(testCase)
            testCase.Instrument.GPIB_Address = 0;
            testCase.verifyEqual(testCase.Instrument.GPIB_Address, 0);

            testCase.Instrument.GPIB_Address = 30;
            testCase.verifyEqual(testCase.Instrument.GPIB_Address, 30);
        end

        function test_GPIBAddress_RejectsOutOfRangeTest(testCase)
            testCase.verifyError(@() testCase.setProperty("GPIB_Address", 31), "MATLAB:validators:mustBeBetweenScalarBounds");
            testCase.verifyError(@() testCase.setProperty("GPIB_Address", -1), "MATLAB:validators:mustBeBetweenScalarBounds");
        end

        function test_GPIBAddress_RejectsNonIntegerTest(testCase)
            testCase.verifyError(@() testCase.setProperty("GPIB_Address", 2.5), "MATLAB:validators:mustBeInteger");
        end

        function test_TextAddresses_AcceptCharAndStringTest(testCase)
            testCase.Instrument.IP_Address = "10.0.0.1";
            testCase.Instrument.Serial_Address = 'COM3';
            testCase.Instrument.VISA_Address = 'USB0::0x05E6::INSTR';

            testCase.verifyEqual(testCase.Instrument.IP_Address, "10.0.0.1");
            testCase.verifyEqual(testCase.Instrument.Serial_Address, 'COM3');
            testCase.verifyEqual(testCase.Instrument.VISA_Address, 'USB0::0x05E6::INSTR');
        end

        function test_TextAddresses_RejectNonScalarTextTest(testCase)
            testCase.verifyError(@() testCase.setProperty("IP_Address", ["a", "b"]), "MATLAB:validators:mustBeTextScalar");
            testCase.verifyError(@() testCase.setProperty("Serial_Address", ["a", "b"]), "MATLAB:validators:mustBeTextScalar");
            testCase.verifyError(@() testCase.setProperty("VISA_Address", ["a", "b"]), "MATLAB:validators:mustBeTextScalar");
        end

        %% PropertyChanged event
        function test_PropertyChanged_FiresOncePerObservablePropertyChangeTest(testCase)
            %GUIs rely on this event to refresh when a property is edited
            eventCount = 0;
            listener = addlistener(testCase.Instrument, "PropertyChanged", @(~, ~) count());
            testCase.addTeardown(@delete, listener);

            testCase.Instrument.GPIB_Address = 5;
            testCase.verifyEqual(eventCount, 1, "GPIB_Address");
            testCase.Instrument.IP_Address = "10.0.0.1";
            testCase.verifyEqual(eventCount, 2, "IP_Address");
            testCase.Instrument.Serial_Address = "COM3";
            testCase.verifyEqual(eventCount, 3, "Serial_Address");
            testCase.Instrument.VISA_Address = "VISA::X";
            testCase.verifyEqual(eventCount, 4, "VISA_Address");
            testCase.Instrument.Name = "Renamed";
            testCase.verifyEqual(eventCount, 5, "Name");
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.VISA;
            testCase.verifyEqual(eventCount, 6, "Connection_Type");

            function count()
                eventCount = eventCount + 1;
            end
        end

        function test_PropertyChanged_EventDataIdentifiesTheInstrumentTest(testCase)
            %InstrumentController uses AffectedObject to find which
            %Instrument changed
            received = [];
            listener = addlistener(testCase.Instrument, "PropertyChanged", @(~, evnt) store(evnt));
            testCase.addTeardown(@delete, listener);

            testCase.Instrument.GPIB_Address = 5;

            testCase.verifyClass(received, "event.PropertyEvent");
            testCase.verifySameHandle(received.AffectedObject, testCase.Instrument);

            function store(evnt)
                received = evnt;
            end
        end

        function test_PropertyChanged_DoesNotFireForNonObservablePropertyTest(testCase)
            eventCount = 0;
            listener = addlistener(testCase.Instrument, "PropertyChanged", @(~, ~) count());
            testCase.addTeardown(@delete, listener);

            testCase.Instrument.FullName = "Something else";
            testCase.Instrument.LastFullDataRow = [1 2 3];
            testCase.Instrument.FullHeadersRow = ["a" "b" "c"];

            testCase.verifyEqual(eventCount, 0);

            function count()
                eventCount = eventCount + 1;
            end
        end

        %% Connect
        function test_Connect_DebugEntersSimulationModeTest(testCase)
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.Debug;

            output = evalc("testCase.Instrument.Connect()");

            testCase.verifyTrue(testCase.Instrument.SimulationMode);
            testCase.verifySubstring(output, "Connected to simulated Stub instrument.");
            testCase.verifyEqual(testCase.Instrument.ConnectedVia, "", "Debug must not try to make a real connection");
        end

        function test_Connect_DispatchesToConnectionMethodForTypeTest(testCase, ConnectDispatch)
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType(ConnectDispatch.Type);

            testCase.Instrument.Connect();

            testCase.verifyEqual(testCase.Instrument.ConnectedVia, ConnectDispatch.ConnectedVia);
            testCase.verifyFalse(testCase.Instrument.SimulationMode);
        end

        function test_Connect_UnsupportedTypeErrorsTest(testCase)
            testCase.Instrument.Connection_Type = "Bogus";

            testCase.verifyErrorWithMessage(@() testCase.Instrument.Connect(), "ConnectError:UnsupportedConnectionType", "Unsupported connection type: Bogus");
        end

        function test_Connect_ErrorsFromConnectionMethodPropagateTest(testCase)
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.GPIB;
            testCase.Instrument.ThrowOnConnect = true;

            testCase.verifyError(@() testCase.Instrument.Connect(), "StubInstrument:ConnectFailed");
        end

        %% Initialise
        function test_Initialise_SuccessTest(testCase)
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.Debug;

            output = evalc("[success, msg] = testCase.Instrument.Initialise();"); %#ok<NASGU>

            testCase.verifyTrue(success);
            testCase.verifyEqual(msg, "");
            testCase.verifyTrue(testCase.Instrument.SimulationMode);
        end

        function test_Initialise_CallsOnInitialisedOnceOnSuccessTest(testCase)
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.GPIB;

            testCase.Instrument.Initialise();

            testCase.verifyEqual(testCase.Instrument.InitialisedCount, 1);
        end

        function test_Initialise_FailureReportsDetailsAndSkipsOnInitialisedTest(testCase)
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.GPIB;
            testCase.Instrument.ThrowOnConnect = true;

            [success, msg] = testCase.Instrument.Initialise();

            testCase.verifyFalse(success);
            testCase.verifySubstring(msg, "Could not connect to Instrument");
            testCase.verifySubstring(msg, "Stub Instrument");   %FullName
            testCase.verifySubstring(msg, "Stub");              %Name
            testCase.verifySubstring(msg, "GPIB");              %Connection type
            testCase.verifySubstring(msg, "Stub connection failure");
            testCase.verifyEqual(testCase.Instrument.InitialisedCount, 0);
        end

        function test_Initialise_FailureMessageIsMultilineTest(testCase)
            %The message is shown to the user, so its line breaks must be
            %real newlines rather than the two characters backslash-n
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.GPIB;
            testCase.Instrument.ThrowOnConnect = true;

            [~, msg] = testCase.Instrument.Initialise();

            expectedStart = "Could not connect to Instrument:" + newline + "Stub Instrument - Stub" + newline + "Connection type GPIB" + newline + newline + "Error message: ";
            testCase.verifyTrue(startsWith(msg, expectedStart), "Unexpected message layout: " + msg);
            testCase.verifyFalse(contains(msg, "\n"), "Message contains a literal backslash-n");
        end

        function test_Initialise_UnsupportedTypeFailsGracefullyTest(testCase)
            testCase.Instrument.Connection_Type = "Bogus";

            [success, msg] = testCase.Instrument.Initialise();

            testCase.verifyFalse(success);
            testCase.verifySubstring(msg, "Unsupported connection type: Bogus");
        end

        %% Close
        function test_Close_DebugReportsDisconnectTest(testCase)
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.Debug;

            output = evalc("testCase.Instrument.Close()");

            testCase.verifySubstring(output, "Disconnected from simulated Stub instrument.");
        end

        function test_Close_NotConnectedDoesNotErrorTest(testCase)
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.GPIB;

            output = evalc("testCase.Instrument.Close()");

            testCase.verifySubstring(output, "Tried to close Stub but it is not connected");
        end

        function test_Close_ClearsDeviceHandleTest(testCase)
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.GPIB;
            testCase.Instrument.SetDeviceHandleForTest(InstrumentTestingInstruments.FakeDeviceHandle());

            testCase.Instrument.Close();

            testCase.verifyEmpty(testCase.Instrument.GetDeviceHandleForTest());
        end

        %% Real Ethernet connection - to a local echo server, no hardware needed
        function test_Connect_EthernetOpensTcpConnectionTest(testCase)
            server = testCase.startEchoServer();

            testCase.connectOverEthernet(testCase.Instrument, server.Port);

            handle = testCase.Instrument.GetDeviceHandleForTest();
            testCase.verifyClass(handle, "tcpclient");
            testCase.verifyEqual(handle.Port, server.Port);
            testCase.verifyEqual(string(handle.Address), "127.0.0.1");
            testCase.verifyEqual(string(handle.ByteOrder), "big-endian");
        end

        function test_Connect_EthernetReusesExistingConnectionTest(testCase)
            server = testCase.startEchoServer();
            second = InstrumentTestingInstruments.StubInstrument();
            testCase.connectOverEthernet(testCase.Instrument, server.Port);

            output = evalc("testCase.connectOverEthernet(second, server.Port)");

            testCase.verifySubstring(output, "Existing connection to Stub found, using that");
            testCase.verifyTrue(isequal(second.GetDeviceHandleForTest(), testCase.Instrument.GetDeviceHandleForTest()), ...
                "Second Instrument should share the first one's connection rather than opening another");
        end

        function test_Initialise_EthernetConnectsAndSucceedsTest(testCase)
            server = testCase.startEchoServer();
            testCase.prepareEthernet(testCase.Instrument, server.Port);

            [success, msg] = testCase.Instrument.Initialise();
            testCase.addTeardown(@() testCase.closeIfConnected(testCase.Instrument));

            testCase.verifyTrue(success);
            testCase.verifyEqual(msg, "");
            testCase.verifyNotEmpty(testCase.Instrument.GetDeviceHandleForTest());
            testCase.verifyEqual(testCase.Instrument.InitialisedCount, 1);
        end

        function test_QueryString_RoundTripsOverEthernetTest(testCase)
            server = testCase.startEchoServer();
            testCase.connectOverEthernet(testCase.Instrument, server.Port);

            response = testCase.Instrument.QueryString("HELLO");

            testCase.verifyEqual(response, 'HELLO');
            testCase.verifyEqual(server.Received.Entries, "HELLO");
        end

        function test_QueryDouble_RoundTripsOverEthernetTest(testCase)
            server = testCase.startEchoServer();
            testCase.connectOverEthernet(testCase.Instrument, server.Port);

            testCase.verifyEqual(testCase.Instrument.QueryDouble("42.5"), 42.5);
        end

        function test_WriteCommandAndReadString_RoundTripOverEthernetTest(testCase)
            server = testCase.startEchoServer();
            testCase.connectOverEthernet(testCase.Instrument, server.Port);

            testCase.Instrument.WriteCommand("PING");
            response = testCase.Instrument.ReadString();

            testCase.verifyEqual(strtrim(response), 'PING');
            testCase.verifyEqual(server.Received.Entries, "PING");
        end

        function test_Close_ReleasesEthernetConnectionTest(testCase)
            server = testCase.startEchoServer();
            testCase.connectOverEthernet(testCase.Instrument, server.Port);
            testCase.verifyTrue(testCase.waitFor(@() server.Server.Connected), "Server never saw the client connect");

            testCase.Instrument.Close();

            testCase.verifyEmpty(testCase.Instrument.GetDeviceHandleForTest());
            testCase.verifyTrue(testCase.waitFor(@() ~server.Server.Connected), "Server still shows the client connected after Close");
        end

        %% Supported connection types
        function test_GetSupportedConnectionTypes_DefaultsToAllTypesTest(testCase)
            types = testCase.Instrument.GetSupportedConnectionTypes();

            expected = enumeration("Palladium.Enums.ConnectionType");
            testCase.verifyEqual(sort(string(types(:))), sort(string(expected(:))));
        end

        function test_DefineSupportedConnectionTypes_RestrictsTypesTest(testCase)
            testCase.Instrument.DefineSupportedConnectionTypes(["Debug", "GPIB"]);

            types = testCase.Instrument.GetSupportedConnectionTypes();

            testCase.verifyEqual(string(types(:)), ["Debug"; "GPIB"]);
        end

        function test_DefineSupportedConnectionTypes_AcceptsEnumValuesTest(testCase)
            testCase.Instrument.DefineSupportedConnectionTypes(Palladium.Enums.ConnectionType.Serial);

            types = testCase.Instrument.GetSupportedConnectionTypes();

            testCase.verifyEqual(types, Palladium.Enums.ConnectionType.Serial);
        end

        function test_DefineSupportedConnectionTypes_RejectsUnknownTypeTest(testCase)
            testCase.verifyError(@() testCase.Instrument.DefineSupportedConnectionTypes(["Debug", "Nonsense"]), "MATLAB:validation:UnableToConvert");
        end

        %% Device I/O - connected
        function test_QueryString_SendsCommandAndStripsWhitespaceTest(testCase)
            handle = testCase.connectFakeHandle();
            handle.QueryResponse = "  +1.5E+00 " + newline;

            response = testCase.Instrument.QueryString("MEAS?");

            testCase.verifyEqual(response, '+1.5E+00');
            testCase.verifyEqual(handle.QueriedCommands, "MEAS?");
        end

        function test_QueryDouble_SendsCommandAndParsesNumberTest(testCase)
            handle = testCase.connectFakeHandle();
            handle.QueryResponse = "+1.5E+00" + newline;

            value = testCase.Instrument.QueryDouble("MEAS?");

            testCase.verifyEqual(value, 1.5);
            testCase.verifyEqual(handle.QueriedCommands, "MEAS?");
        end

        function test_QueryDouble_NonNumericResponseGivesNaNTest(testCase)
            handle = testCase.connectFakeHandle();
            handle.QueryResponse = "not a number";

            testCase.verifyTrue(isnan(testCase.Instrument.QueryDouble("MEAS?")));
        end

        function test_ReadString_ReturnsResponseUntouchedTest(testCase)
            handle = testCase.connectFakeHandle();
            handle.ReadResponse = "DONE" + newline;

            data = testCase.Instrument.ReadString();

            testCase.verifyEqual(data, ['DONE', newline]);
            testCase.verifyEqual(handle.ReadCount, 1);
        end

        function test_WriteCommand_SendsCommandTest(testCase)
            handle = testCase.connectFakeHandle();

            testCase.Instrument.WriteCommand("OUTP ON");
            testCase.Instrument.WriteCommand("OUTP OFF");

            testCase.verifyEqual(handle.WrittenCommands, ["OUTP ON", "OUTP OFF"]);
        end

        function test_DeviceIO_RejectsNonScalarCommandsTest(testCase)
            testCase.connectFakeHandle();

            testCase.verifyError(@() testCase.Instrument.QueryString(["a", "b"]), "MATLAB:validation:IncompatibleSize");
            testCase.verifyError(@() testCase.Instrument.QueryDouble(["a", "b"]), "MATLAB:validation:IncompatibleSize");
            testCase.verifyError(@() testCase.Instrument.WriteCommand(["a", "b"]), "MATLAB:validation:IncompatibleSize");
        end

        %% Device I/O - not connected
        function test_DeviceIO_ErrorsWhenNotConnectedTest(testCase, NotConnectedCall)
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.GPIB;

            testCase.verifyErrorWithMessage(@() NotConnectedCall.Call(testCase.Instrument), NotConnectedCall.ErrorId, "Device Handle is empty");
        end

        %% Device I/O - simulation mode
        function test_QueryString_SimulationModeReturnsNullTest(testCase)
            testCase.enterSimulationMode();

            testCase.verifyEqual(testCase.Instrument.QueryString("MEAS?"), 'null');
        end

        function test_ReadString_SimulationModeReturnsNullTest(testCase)
            testCase.enterSimulationMode();

            testCase.verifyEqual(testCase.Instrument.ReadString(), 'null');
        end

        function test_QueryDouble_SimulationModeReturnsValueAround100Test(testCase)
            testCase.enterSimulationMode();

            value = testCase.Instrument.QueryDouble("MEAS?");

            testCase.verifyGreaterThanOrEqual(value, 100);
            testCase.verifyLessThan(value, 101);
        end

        function test_WriteCommand_SimulationModeDoesNothingTest(testCase)
            testCase.enterSimulationMode();

            %No device handle exists in simulation mode, so this would error
            %if it tried to send anything
            testCase.verifyWarningFree(@() testCase.Instrument.WriteCommand("OUTP ON"));
        end

        %% Settings
        function test_SettingsInput_IsAppliedByCheckForSettingsToApplyTest(testCase)
            settings = struct("Setpoint", 4.2);

            testCase.Instrument.SettingsInput(settings);
            testCase.Instrument.CheckForSettingsToApply();

            testCase.verifyEqual(testCase.Instrument.AppliedSettings, {settings});
        end

        function test_SettingsInput_IsClearedOnceAppliedTest(testCase)
            testCase.Instrument.SettingsInput(struct("Setpoint", 4.2));
            testCase.Instrument.CheckForSettingsToApply();

            testCase.verifyEmpty(testCase.Instrument.GetSettingsToApplyForTest());

            %Nothing pending, so a second check must not apply anything again
            testCase.Instrument.CheckForSettingsToApply();
            testCase.verifyLength(testCase.Instrument.AppliedSettings, 1);
        end

        function test_SettingsInput_NewInputIgnoredWhileOneIsPendingTest(testCase)
            first = struct("Setpoint", 1);
            second = struct("Setpoint", 2);

            testCase.Instrument.SettingsInput(first);
            testCase.Instrument.SettingsInput(second);
            testCase.Instrument.CheckForSettingsToApply();

            testCase.verifyEqual(testCase.Instrument.AppliedSettings, {first});
        end

        function test_SettingsInput_AcceptedAgainAfterPreviousWasAppliedTest(testCase)
            first = struct("Setpoint", 1);
            second = struct("Setpoint", 2);

            testCase.Instrument.SettingsInput(first);
            testCase.Instrument.CheckForSettingsToApply();
            testCase.Instrument.SettingsInput(second);
            testCase.Instrument.CheckForSettingsToApply();

            testCase.verifyEqual(testCase.Instrument.AppliedSettings, {first, second});
        end

        function test_CheckForSettingsToApply_DoesNothingWhenNoneGivenTest(testCase)
            testCase.Instrument.CheckForSettingsToApply();

            testCase.verifyEmpty(testCase.Instrument.AppliedSettings);
        end

        %% ShowProperty
        function test_ShowProperty_OnlyShowsAddressForConnectionTypeTest(testCase, VisibleAddressProperty)
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType(VisibleAddressProperty.Type);
            addressProperties = ["GPIB_Address", "IP_Address", "Serial_Address", "VISA_Address"];

            shown = addressProperties(arrayfun(@(p) testCase.Instrument.ShowProperty(p), addressProperties));

            if VisibleAddressProperty.Visible == ""
                testCase.verifyEmpty(shown);
            else
                testCase.verifyEqual(shown, VisibleAddressProperty.Visible);
            end
        end

        function test_ShowProperty_ShowsOtherPropertiesForAllTypesTest(testCase)
            for type = enumeration("Palladium.Enums.ConnectionType")'
                testCase.Instrument.Connection_Type = type;

                testCase.verifyTrue(testCase.Instrument.ShowProperty("Name"), "Name hidden for " + string(type));
                testCase.verifyTrue(testCase.Instrument.ShowProperty("SomeInstrumentSpecificProperty"));
            end
        end

        function test_ShowProperty_HidesPropertiesReturnedByGetPropertiesToIgnoreTest(testCase)
            testCase.Instrument.PropertiesToIgnore = {"Name", "Other"};
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.GPIB;

            testCase.verifyFalse(testCase.Instrument.ShowProperty("Name"));
            testCase.verifyFalse(testCase.Instrument.ShowProperty("Other"));
            testCase.verifyTrue(testCase.Instrument.ShowProperty("Connection_Type"));
            testCase.verifyTrue(testCase.Instrument.ShowProperty("GPIB_Address"), "Address shown for this connection type must be unaffected");
        end

        function test_GetPropertiesToIgnore_DefaultIgnoresNothingTest(testCase)
            testCase.Instrument.UseBaseGetPropertiesToIgnore = true;
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.GPIB;

            testCase.verifyTrue(testCase.Instrument.ShowProperty("Name"));
            testCase.verifyTrue(testCase.Instrument.ShowProperty("Connection_Type"));
        end

        function test_ShowProperty_UnsupportedConnectionTypeErrorsTest(testCase)
            testCase.Instrument.Connection_Type = "Bogus";

            testCase.verifyErrorWithMessage(@() testCase.Instrument.ShowProperty("Name"), "ShowPropertyError:UnsupportedConnectionType", "Unsupported connection type: Bogus");
        end

        %% Metadata
        function test_GrabMetadataString_EmptyWhenNoMetadataTest(testCase)
            testCase.verifyEmpty(testCase.Instrument.GrabMetadataString());
        end

        function test_CollectMetaData_DefaultIsEmptyTest(testCase)
            %Instruments that don't override CollectMetaData add nothing to
            %the data file header
            testCase.Instrument.UseBaseCollectMetaData = true;

            testCase.verifyEmpty(testCase.Instrument.CollectMetaData());
            testCase.verifyEmpty(testCase.Instrument.GrabMetadataString());
        end

        function test_GrabMetadataString_BuildsSettingsLineFromStructTest(testCase)
            testCase.Instrument.MetadataToReturn = struct("Frequency", 100, "Mode", "AC", "Range", [1 2 3]);

            line = testCase.Instrument.GrabMetadataString();

            testCase.verifyEqual(line, "Stub Settings: Frequency = 100 || Mode = AC || Range = 1 2 3");
        end

        function test_GrabMetadataString_RejectsNonStructMetadataTest(testCase)
            testCase.Instrument.MetadataToReturn = 5;

            testCase.verifyErrorWithMessage(@() testCase.Instrument.GrabMetadataString(), "GrabMetadataStringError:MetadataNotStruct", "not Struct on Instrument Stub");
        end

        %% Instrument Control definitions
        function test_GetAvailableControlOptions_EmptyByDefaultTest(testCase)
            testCase.verifyEmpty(testCase.Instrument.GetAvailableControlOptions());
        end

        function test_DefineInstrumentControl_StoresDetailsStructTest(testCase)
            testCase.Instrument.DefineControlForTest(Name="Sweep Control", ClassName="SweepController_Stepped", TabName="Sweep Tab");

            options = testCase.Instrument.GetAvailableControlOptions();

            testCase.verifyEqual(options, struct( ...
                "Name", "Sweep Control", ...
                "ControlClassFileName", "SweepController_Stepped", ...
                "TabName", "Sweep Tab", ...
                "EnabledByDefault", false, ...
                "UserData", []));
        end

        function test_DefineInstrumentControl_StoresOptionalSettingsTest(testCase)
            userData = struct("Channel", 3);

            testCase.Instrument.DefineControlForTest(Name="Heater", ClassName="HeaterControl", TabName="Heater", EnabledByDefault=true, UserData=userData);

            options = testCase.Instrument.GetAvailableControlOptions();
            testCase.verifyTrue(options.EnabledByDefault);
            testCase.verifyEqual(options.UserData, userData);
        end

        function test_DefineInstrumentControl_AppendsInOrderTest(testCase)
            testCase.Instrument.DefineControlForTest(Name="First", ClassName="A", TabName="T1");
            testCase.Instrument.DefineControlForTest(Name="Second", ClassName="B", TabName="T2");
            testCase.Instrument.DefineControlForTest(Name="Third", ClassName="C", TabName="T3");

            options = testCase.Instrument.GetAvailableControlOptions();

            testCase.verifyEqual(string({options.Name}), ["First", "Second", "Third"]);
        end

        function test_DefineInstrumentControl_RequiresNameTest(testCase)
            testCase.verifyError(@() testCase.Instrument.DefineControlForTest(ClassName="A", TabName="T"), "MATLAB:nonExistentField");
        end

        function test_DefineInstrumentControl_RejectsNonLogicalEnabledByDefaultTest(testCase)
            testCase.verifyError(@() testCase.Instrument.DefineControlForTest(Name="A", ClassName="B", TabName="T", EnabledByDefault=[true false]), "MATLAB:validation:IncompatibleSize");
        end

        function test_GetControlOption_ReturnsMatchingStructTest(testCase)
            testCase.Instrument.DefineControlForTest(Name="First", ClassName="A", TabName="T1");
            testCase.Instrument.DefineControlForTest(Name="Second", ClassName="B", TabName="T2");

            option = testCase.Instrument.GetControlOption("Second");

            testCase.verifyEqual(option.ControlClassFileName, "B");
            testCase.verifyEqual(option.TabName, "T2");
        end

        function test_GetControlOption_UnknownNameListsAvailableOptionsTest(testCase)
            testCase.Instrument.DefineControlForTest(Name="First", ClassName="A", TabName="T1");
            testCase.Instrument.DefineControlForTest(Name="Second", ClassName="B", TabName="T2");

            testCase.verifyErrorWithMessage(@() testCase.Instrument.GetControlOption("Missing"), "GetControlOptionError:NotFound", ...
                "Could not find Control Detail Struct with name Missing. Supported options: First, Second");
        end

        function test_GetControlOption_ErrorsWhenNoControlsDefinedTest(testCase)
            testCase.verifyError(@() testCase.Instrument.GetControlOption("Anything"), "GetControlOptionError:NotFound");
        end

        %% Registered Instrument Control objects
        function test_RegisteredControls_EmptyByDefaultTest(testCase)
            testCase.verifyEmpty(testCase.Instrument.GetRegisteredControlNames());
            testCase.verifyEmpty(testCase.Instrument.GetRegisteredControlObjects());
            testCase.verifyEmpty(testCase.Instrument.GetRegisteredControlObjectsFromName("Anything"));
        end

        function test_RegisterControlObject_ControlIsRetrievableTest(testCase)
            control = testCase.registerControl("Sweep");

            testCase.verifyEqual(testCase.Instrument.GetRegisteredControlNames(), "Sweep");
            testCase.verifyEqual(testCase.Instrument.GetRegisteredControlObjectsFromName("Sweep"), control);
        end

        function test_GetRegisteredControlObjects_ReturnsObjectsAndDetailsStructsInOrderTest(testCase)
            first = testCase.registerControl("First");
            second = testCase.registerControl("Second");

            [objects, detailsStructs] = testCase.Instrument.GetRegisteredControlObjects();

            testCase.verifyEqual(objects, [first, second]);
            testCase.verifyEqual(string({detailsStructs.Name}), ["First", "Second"]);
        end

        function test_GetRegisteredControlNames_ReturnsAllNamesTest(testCase)
            testCase.registerControl("First");
            testCase.registerControl("Second");

            testCase.verifyEqual(testCase.Instrument.GetRegisteredControlNames(), ["First", "Second"]);
        end

        function test_GetRegisteredControlObjectsFromName_OnlyReturnsMatchesTest(testCase)
            testCase.registerControl("First");
            second = testCase.registerControl("Second");

            testCase.verifyEqual(testCase.Instrument.GetRegisteredControlObjectsFromName("Second"), second);
            testCase.verifyEmpty(testCase.Instrument.GetRegisteredControlObjectsFromName("Third"));
        end

        function test_RegisterControlObject_RejectsDuplicateNameTest(testCase)
            testCase.registerControl("Sweep");

            testCase.verifyErrorWithMessage(@() testCase.registerControl("Sweep"), "RegisterControlObjectError:DuplicateName", ...
                "A Control object of name Sweep has already been added to Instrument Stub");
            testCase.verifyEqual(testCase.Instrument.GetRegisteredControlNames(), "Sweep", "Failed registration must not add the control");
        end

        function test_RemoveControlObject_RemovesOnlyNamedControlTest(testCase)
            testCase.registerControl("First");
            second = testCase.registerControl("Second");
            testCase.registerControl("Third");

            testCase.Instrument.RemoveControlObject("First");
            testCase.Instrument.RemoveControlObject("Third");

            testCase.verifyEqual(testCase.Instrument.GetRegisteredControlObjects(), second);
        end

        function test_RemoveControlObject_UnknownNameDoesNothingTest(testCase)
            testCase.registerControl("Sweep");

            testCase.Instrument.RemoveControlObject("Missing");

            testCase.verifyEqual(testCase.Instrument.GetRegisteredControlNames(), "Sweep");
        end

        function test_RemoveControlObject_NameCanBeRegisteredAgainTest(testCase)
            testCase.registerControl("Sweep");
            testCase.Instrument.RemoveControlObject("Sweep");

            testCase.registerControl("Sweep");

            testCase.verifyEqual(testCase.Instrument.GetRegisteredControlNames(), "Sweep");
        end

        %% UpdateAndMeasure
        function test_UpdateAndMeasure_ReturnsMeasuredDataRowTest(testCase)
            testCase.Instrument.DataRowToReturn = [4 5 6];

            dataRow = testCase.Instrument.UpdateAndMeasure(["h1", "h2", "h3"]);

            testCase.verifyEqual(dataRow, [4 5 6]);
        end

        function test_UpdateAndMeasure_UpdatesControlsThenMeasuresThenUpdatesDataTest(testCase)
            recorder = InstrumentTestingInstruments.CallRecorder();
            testCase.Instrument.Recorder = recorder;
            testCase.registerControl("A", recorder);
            testCase.registerControl("B", recorder);

            testCase.Instrument.UpdateAndMeasure(["h1", "h2"]);

            testCase.verifyEqual(recorder.Entries, ["Update:A", "Update:B", "Measure", "UpdateData:A", "UpdateData:B"]);
        end

        function test_UpdateAndMeasure_PassesDataRowAndHeadersToControlsTest(testCase)
            testCase.Instrument.DataRowToReturn = [7 8];
            control = testCase.registerControl("A");
            headers = ["h1", "h2"];

            testCase.Instrument.UpdateAndMeasure(headers);

            testCase.verifyEqual(control.LastDataRow, [7 8]);
            testCase.verifyEqual(control.LastHeaders, headers);
            testCase.verifyEqual(control.UpdateCount, 1);
        end

        function test_UpdateAndMeasure_WorksWithNoControlsTest(testCase)
            recorder = InstrumentTestingInstruments.CallRecorder();
            testCase.Instrument.Recorder = recorder;

            testCase.Instrument.UpdateAndMeasure("h");

            testCase.verifyEqual(recorder.Entries, "Measure");
        end

        function test_UpdateAndMeasure_RemovedControlIsNoLongerUpdatedTest(testCase)
            control = testCase.registerControl("A");
            testCase.Instrument.RemoveControlObject("A");

            testCase.Instrument.UpdateAndMeasure("h");

            testCase.verifyEqual(control.UpdateCount, 0);
        end

        %% ConvertToCategorical
        function test_ConvertToCategorical_ReturnsCategoricalTest(testCase)
            result = testCase.Instrument.ConvertToCategoricalOutputForTest("B", ["A", "B", "C"]);

            testCase.verifyClass(result, "categorical");
            testCase.verifyEqual(string(result), "B");
            testCase.verifyEqual(categories(result), {'A'; 'B'; 'C'});
        end

        function test_ConvertToCategorical_UnknownValueListsCategoriesTest(testCase)
            testCase.verifyErrorWithMessage(@() testCase.Instrument.ConvertToCategoricalOutputForTest("Z", ["A", "B"]), "ConvertToCategoricalError:ValueNotInCategories", ...
                "Given value: Z was not found in the input category names: A B");
        end

        function test_ConvertToCategorical_RejectsNonScalarInputTest(testCase)
            testCase.verifyError(@() testCase.Instrument.ConvertToCategoricalOutputForTest(["A", "B"], ["A", "B"]), "MATLAB:validation:IncompatibleSize");
        end

        %% RetrieveSimulatedDataValue
        function test_RetrieveSimulatedDataValue_DefaultsToZeroTest(testCase)
            testCase.verifyEqual(testCase.Instrument.RetrieveSimulatedDataValueForTest("SourceLevel"), 0);
        end

        function test_RetrieveSimulatedDataValue_UsesGivenDefaultTest(testCase)
            testCase.verifyEqual(testCase.Instrument.RetrieveSimulatedDataValueForTest("SourceLevel", 7), 7);
        end

        function test_RetrieveSimulatedDataValue_StoresDefaultForLaterCallsTest(testCase)
            testCase.Instrument.RetrieveSimulatedDataValueForTest("SourceLevel", 7);

            %The first default sticks - a different one on a later call is ignored
            testCase.verifyEqual(testCase.Instrument.RetrieveSimulatedDataValueForTest("SourceLevel", 9), 7);
            testCase.verifyEqual(testCase.Instrument.GetSimulatedDataForTest(), struct("SourceLevel", 7));
        end

        function test_RetrieveSimulatedDataValue_ReturnsExistingValueTest(testCase)
            testCase.Instrument.SetSimulatedDataForTest(struct("SourceLevel", 3.5));

            testCase.verifyEqual(testCase.Instrument.RetrieveSimulatedDataValueForTest("SourceLevel", 9), 3.5);
        end

        function test_RetrieveSimulatedDataValue_MissingFieldKeepsOtherFieldsTest(testCase)
            testCase.Instrument.SetSimulatedDataForTest(struct("Other", 1));

            value = testCase.Instrument.RetrieveSimulatedDataValueForTest("SourceLevel", 4);

            testCase.verifyEqual(value, 4);
            testCase.verifyEqual(testCase.Instrument.GetSimulatedDataForTest(), struct("Other", 1, "SourceLevel", 4));
        end

        function test_RetrieveSimulatedDataValue_FieldsAreIndependentTest(testCase)
            testCase.Instrument.RetrieveSimulatedDataValueForTest("A", 1);
            testCase.Instrument.RetrieveSimulatedDataValueForTest("B", 2);

            testCase.verifyEqual(testCase.Instrument.RetrieveSimulatedDataValueForTest("A"), 1);
            testCase.verifyEqual(testCase.Instrument.RetrieveSimulatedDataValueForTest("B"), 2);
        end

        %% PrintIdentifier
        function test_PrintIdentifier_ReturnsAndPrintsDescriptionTest(testCase)
            output = evalc("identifier = testCase.Instrument.PrintIdentifier();");

            testCase.verifyEqual(identifier, "Palladium Instrument Stub Instrument");
            testCase.verifySubstring(output, "Palladium Instrument Stub Instrument");
        end

        %% Error messages containing user-supplied text
        function test_ErrorMessages_KeepFormatCharactersInNamesLiteralTest(testCase)
            %Names and paths can contain % and backslashes (eg Windows
            %paths). They must appear in error messages exactly as given,
            %not be treated as format specifiers or escape sequences
            trickyName = "Probe 50% C:\new\table %s";

            testCase.Instrument.FullName = trickyName;
            testCase.Instrument.Name = trickyName;
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.GPIB;
            testCase.verifyErrorWithMessage(@() testCase.Instrument.QueryString("X?"), "QueryStringError:NotConnected", trickyName);

            testCase.Instrument.DefineControlForTest(Name="Real", ClassName="A", TabName="T");
            testCase.verifyErrorWithMessage(@() testCase.Instrument.GetControlOption(trickyName), "GetControlOptionError:NotFound", trickyName);

            testCase.registerControl(trickyName);
            testCase.verifyErrorWithMessage(@() testCase.registerControl(trickyName), "RegisterControlObjectError:DuplicateName", trickyName);

            testCase.verifyErrorWithMessage(@() testCase.Instrument.ConvertToCategoricalOutputForTest(trickyName, ["A", "B"]), "ConvertToCategoricalError:ValueNotInCategories", trickyName);

            testCase.Instrument.Connection_Type = trickyName;
            testCase.verifyErrorWithMessage(@() testCase.Instrument.Connect(), "ConnectError:UnsupportedConnectionType", trickyName);
            testCase.verifyErrorWithMessage(@() testCase.Instrument.ShowProperty("Name"), "ShowPropertyError:UnsupportedConnectionType", trickyName);

            testCase.Instrument.MetadataToReturn = 5;
            testCase.verifyErrorWithMessage(@() testCase.Instrument.GrabMetadataString(), "GrabMetadataStringError:MetadataNotStruct", trickyName);
        end

        %% Default behaviours that implementations can override
        function test_SetNewSweepStepValue_WarnsWhenNotOverriddenTest(testCase)
            testCase.verifyWarning(@() testCase.Instrument.SetNewSweepStepValue(1), "SetNewSweepStepValueWarning:NotOverridden");
        end

        function test_RampMethods_DoNothingByDefaultTest(testCase)
            testCase.verifyWarningFree(@() testCase.Instrument.AbortRamp());
            testCase.verifyWarningFree(@() testCase.Instrument.SetRampingToTarget(1, 2, struct()));
        end

        %% GenerateSimulatedData - size and orientation
        function test_GenerateSimulatedData_DefaultsToSingleColumnTest(testCase)
            data = testCase.Instrument.GenerateSimulatedData(7);

            testCase.verifySize(data, [7, 1]);
            testCase.verifyTrue(all(isfinite(data), "all"));
        end

        function test_GenerateSimulatedData_OutputSizeTest(testCase)
            data = testCase.Instrument.GenerateSimulatedData(4, 3);

            testCase.verifySize(data, [4, 3]);
            testCase.verifyTrue(all(isfinite(data), "all"));
        end

        function test_GenerateSimulatedData_TransposeOutputSizeTest(testCase)
            %Transpose changes which dimension gets its own scale, not the
            %size of the output
            data = testCase.Instrument.GenerateSimulatedData(3, 4, Transpose=true);

            testCase.verifySize(data, [3, 4]);
            testCase.verifyTrue(all(isfinite(data), "all"));
        end

        %% GenerateSimulatedData - Baseline and Variance statistics
        function test_GenerateSimulatedData_ScalarBaselineAndVarianceTest(testCase)
            data = testCase.Instrument.GenerateSimulatedData(testCase.NumSamples, 1, Baseline=17, Variance=0.1);

            testCase.verifySize(data, [testCase.NumSamples, 1]);
            testCase.verifyMeanAndSpread(data, 17, 0.1);
        end

        function test_GenerateSimulatedData_ScalarBaselineAppliedToAllColumnsTest(testCase)
            data = testCase.Instrument.GenerateSimulatedData(testCase.NumSamples, 3, Baseline=50, Variance=2);

            for i = 1 : 3
                testCase.verifyMeanAndSpread(data(:, i), 50, 2);
            end
        end

        function test_GenerateSimulatedData_PerColumnBaselineAndVarianceTest(testCase)
            %Columns of very different magnitude, as for an instrument that
            %returns e.g. a resistance and a current together
            baselines = [1000, 1e-3];
            variances = [100, 1e-4];

            data = testCase.Instrument.GenerateSimulatedData(testCase.NumSamples, 2, Baseline=baselines, Variance=variances);

            testCase.verifySize(data, [testCase.NumSamples, 2]);
            for i = 1 : 2
                testCase.verifyMeanAndSpread(data(:, i), baselines(i), variances(i));
            end
        end

        function test_GenerateSimulatedData_TransposePerRowBaselineAndVarianceTest(testCase)
            baselines = [1000; 1e-3];
            variances = [100; 1e-4];

            data = testCase.Instrument.GenerateSimulatedData(2, testCase.NumSamples, Transpose=true, Baseline=baselines, Variance=variances);

            testCase.verifySize(data, [2, testCase.NumSamples]);
            for i = 1 : 2
                testCase.verifyMeanAndSpread(data(i, :), baselines(i), variances(i));
            end
        end

        function test_GenerateSimulatedData_ClampedToFiveStdDeviationsTest(testCase)
            %Unclamped normal draws exceed 5 standard deviations about once
            %in 1.7 million. With this seed, 1e7 values contain 3 such
            %outliers (max 5.16 sigma) unless they are clamped, so this
            %fails if the clamp is removed
            rng(1);
            baseline = 100;
            variance = 1;

            data = testCase.Instrument.GenerateSimulatedData(1e7, 1, Baseline=baseline, Variance=variance);

            testCase.verifyLessThanOrEqual(max(abs(data - baseline)), 5 * variance * (1 + 1e-12));
        end

        function test_GenerateSimulatedData_ClampedToFiveStdDeviationsTransposeTest(testCase)
            rng(1);
            baseline = 100;
            variance = 1;

            data = testCase.Instrument.GenerateSimulatedData(1, 1e7, Transpose=true, Baseline=baseline, Variance=variance);

            testCase.verifyLessThanOrEqual(max(abs(data - baseline)), 5 * variance * (1 + 1e-12));
        end

        %% GenerateSimulatedData - argument validation
        function test_GenerateSimulatedData_BaselineLengthMismatchTest(testCase)
            testCase.verifyError(@() testCase.Instrument.GenerateSimulatedData(5, 2, Baseline=[1 2 3]), "GenerateSimulatedDataError:BaselineLengthMismatch");
        end

        function test_GenerateSimulatedData_VarianceLengthMismatchTest(testCase)
            testCase.verifyError(@() testCase.Instrument.GenerateSimulatedData(5, 2, Variance=[1 2 3]), "GenerateSimulatedDataError:VarianceLengthMismatch");
        end

        function test_GenerateSimulatedData_TransposeLengthMismatchTest(testCase)
            %With Transpose the per-value arrays must match the number of
            %rows rather than columns
            testCase.verifyError(@() testCase.Instrument.GenerateSimulatedData(2, 5, Transpose=true, Baseline=[1 2 3]), "GenerateSimulatedDataError:BaselineLengthMismatch");
            testCase.verifyError(@() testCase.Instrument.GenerateSimulatedData(2, 5, Transpose=true, Variance=[1 2 3]), "GenerateSimulatedDataError:VarianceLengthMismatch");
        end

        function test_GenerateSimulatedData_NonIntegerSizeTest(testCase)
            testCase.verifyError(@() testCase.Instrument.GenerateSimulatedData(2.5, 2), "MATLAB:validators:mustBeInteger");
            testCase.verifyError(@() testCase.Instrument.GenerateSimulatedData(2, 1.5), "MATLAB:validators:mustBeInteger");
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function handle = connectFakeHandle(testCase)
            %Give the Instrument a fake device handle, as if Connect() had
            %opened a real connection, and return it to inspect/configure
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.GPIB;
            handle = InstrumentTestingInstruments.FakeDeviceHandle();
            testCase.Instrument.SetDeviceHandleForTest(handle);
        end

        function server = startEchoServer(testCase)
            %Start a TCP server on the loopback interface that echoes every
            %line it receives straight back, and records the lines. Lets the
            %real Ethernet code in Instrument run with no hardware
            server = struct("Server", [], "Port", [], "Received", InstrumentTestingInstruments.CallRecorder());

            %Pick a random unused port, without disturbing the seeded random
            %number sequence the statistical tests depend on
            previousRng = rng;
            restoreRng = onCleanup(@() rng(previousRng));
            for attempt = 1 : 20
                port = randi([49152, 65000]);
                try
                    server.Server = tcpserver("127.0.0.1", port);
                    server.Port = port;
                    break;
                catch
                end
            end
            testCase.assumeNotEmpty(server.Server, "Could not start a local TCP server (needs Instrument Control Toolbox and a free port)");
            testCase.addTeardown(@delete, server.Server);

            configureTerminator(server.Server, "LF");
            configureCallback(server.Server, "terminator", @(src, ~) echoLine(src, server.Received));
        end

        function prepareEthernet(~, instrument, port)
            %Point an Instrument's real Ethernet connection code at a local server
            instrument.UseBaseConnectionMethods = true;
            instrument.Connection_Type = Palladium.Enums.ConnectionType.Ethernet;
            instrument.IP_Address = "127.0.0.1";
            settings = instrument.GetConnectionSettingsForTest();
            settings.Port = port;
            instrument.SetConnectionSettingsForTest(settings);
        end

        function connectOverEthernet(testCase, instrument, port)
            testCase.prepareEthernet(instrument, port);
            instrument.Connect();
            testCase.addTeardown(@() testCase.closeIfConnected(instrument));
        end

        function closeIfConnected(~, instrument)
            if ~isempty(instrument.GetDeviceHandleForTest())
                instrument.Close();
            end
        end

        function success = waitFor(~, condition)
            %Poll until condition() is true, for up to 5 seconds
            timer = tic();
            success = condition();
            while ~success && toc(timer) < 5
                pause(0.05);
                success = condition();
            end
        end

        function enterSimulationMode(testCase)
            testCase.Instrument.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            evalc("testCase.Instrument.Connect()");   %Swallow the 'Connected to simulated..' message
        end

        function control = registerControl(testCase, name, recorder)
            control = InstrumentTestingInstruments.StubControl(name);
            if nargin > 2
                control.Recorder = recorder;
            end
            testCase.Instrument.RegisterControlObject(control);
        end

        function setProperty(testCase, propertyName, value)
            testCase.Instrument.(propertyName) = value;
        end

        function verifyErrorWithMessage(testCase, fcn, expectedId, expectedText)
            %Check both the identifier and (a substring of) the message of
            %the error thrown, for errors whose message carries useful
            %detail, like listing the valid options
            try
                fcn();
            catch err
                testCase.verifyEqual(string(err.identifier), string(expectedId));
                testCase.verifySubstring(string(err.message), expectedText);
                return;
            end

            testCase.verifyFail("Expected error " + expectedId + " but none was thrown");
        end

        function verifyMeanAndSpread(testCase, samples, expectedMean, expectedStd)
            %Check the sample mean and standard deviation match the
            %requested Baseline and Variance. Tolerances are set from the
            %statistical error on each estimate for NumSamples samples: 6
            %standard errors on the mean, and 5% on the standard deviation
            %(whose standard error is ~0.5% at this sample size).
            standardError = expectedStd / sqrt(numel(samples));

            testCase.verifyEqual(mean(samples, "all"), expectedMean, "AbsTol", 6 * standardError);
            testCase.verifyEqual(std(samples, 0, "all"), expectedStd, "RelTol", 0.05);
        end

    end

end

function echoLine(server, recorder)
    %TCP server callback: send every line received straight back
    line = readline(server);
    recorder.Record(line);
    writeline(server, line);
end
