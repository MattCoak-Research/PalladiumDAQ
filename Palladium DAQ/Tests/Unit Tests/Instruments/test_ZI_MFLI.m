classdef test_ZI_MFLI < matlab.unittest.TestCase
    %TEST_ZI_MFLI Tests the commands the ZI_MFLI driver sends, through a fake LabOne API (Tests/Unit Tests/data/ZI Testing/ziDAQ.m)
    %The driver is a RecordingZI_MFLI given a device ID, as if connected.
    %The fake records every ziDAQ call, and answers getDouble/getInt with
    %set replies.

    %% Properties
    properties
        Instrument;     %A RecordingZI_MFLI, "connected" to DeviceID
    end

    properties (Constant)
        DeviceID = 'dev1234';
    end

    %% Methods (TestClassSetup)
    methods (TestClassSetup)
        function pathSetup(testCase)
            dataFolder = fullfile(fileparts(mfilename("fullpath")), "..", "data");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(dataFolder, "Instrument Testing")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(dataFolder, "ZI Testing")));
        end
    end

    %% Methods (TestMethodSetup)
    methods (TestMethodSetup)
        function makeInstrument(testCase)
            ziDAQ("fake_reset");
            testCase.Instrument = InstrumentTestingInstruments.RecordingZI_MFLI();
            testCase.Instrument.SetDeviceHandleForTest(testCase.DeviceID);
        end
    end

    %% Methods (Test)
    methods (Test)
        function SweepIsStartedOnceTest(testCase)
            %Setting up a sweep doesn't start it - Sweep_Execute does, once.
            %It used to be started in both
            evalc("sweepHandle = testCase.Instrument.Sweep_InitialiseSweep();");
            testCase.verifyEqual(testCase.callCount("execute"), 0, "Not started when set up");

            testCase.Instrument.Sweep_Execute(sweepHandle);
            testCase.verifyEqual(testCase.callCount("execute"), 1);
            testCase.verifyEqual(testCase.callCount("trigger"), 1);
        end

        function SweepSettlingTimeIsInSecondsTest(testCase)
            %Sent as given - sweep/settling/time is in seconds. It used to
            %be multiplied by the filter time constant
            evalc("testCase.Instrument.Sweep_InitialiseSweep(SettleTime=0.5, Bandwidth=100);");

            calls = ziDAQ("fake_calls");
            settling = calls(cellfun(@(c) string(c{1}) == "set" && numel(c) >= 3 && string(c{3}) == "sweep/settling/time", calls));
            testCase.verifyNumElements(settling, 1);
            testCase.verifyEqual(settling{1}{4}, 0.5);
        end

        function ScopeInputsTest(testCase)
            %Signal Input 1 and Current Input 1 - Signal Output 1 isn't a
            %scope input (it was offered, as an index the MFLI doesn't have)
            testCase.Instrument.Scope_Initialise("FFT", ChannelIdx="CurrentInput1");
            testCase.verifyEqual(testCase.lastValueSet("/scopes/0/channels/0/inputselect"), 1);

            testCase.verifyError(@() testCase.Instrument.Scope_Initialise("FFT", ChannelIdx="SignalOutput1"), ...
                "MFLI_ConvertScopeInputNameToIndex_Error:InvalidChannelName");
        end

        function CurrentModeTest(testCase)
            %R (in A) and phase, the output and frequency - with no
            %resistance column, even with a current source set. Measure used
            %to error in Current mode
            mfli = Palladium.Instruments.ZI_MFLI();
            mfli.Connection_Type = Palladium.Enums.ConnectionType.Debug;
            evalc("mfli.Connect()");
            mfli.MeasurementMode = mfli.MeasType("Current");
            mfli.ConnectedCurrentSource = mfli.CurrentSource("200 uA/V");

            [headers, units] = mfli.GetHeaders();
            dataRow = mfli.Measure();

            testCase.verifyEqual(headers, "ZI MFLI - " + ["Current (A)", "Phase (Deg)", "Output Current (A)", "Frequency (Hz)"]);
            testCase.verifyEqual(units, ["A", "Deg", "A", "Hz"]);
            testCase.verifySize(dataRow, [1 4], "One value per column");
        end

        function ResistanceUnitsAreOhmSymbolTest(testCase)
            %As every other driver names them (it was "Ohm", then "Ohms")
            mfli = Palladium.Instruments.ZI_MFLI();
            mfli.ConnectedCurrentSource = mfli.CurrentSource("200 uA/V");

            [headers, units] = mfli.GetHeaders();

            testCase.verifyEqual(headers(end), "ZI MFLI - Resistance (Ω)");
            testCase.verifyEqual(units(end), "Ω");
        end

        function ScopeBandwidthLimitIsOnTest(testCase)
            %bwlimit 0 is on (averaging, avoiding aliasing), 1 is off - it
            %used to be set to 1
            testCase.Instrument.Scope_Initialise("FFT");

            testCase.verifyEqual(testCase.lastValueSet("/scopes/0/channels/0/bwlimit"), 0);
        end

        function RangeCheckCountsANegativeOffsetTest(testCase)
            %0.5 V amplitude with -0.6 V offset swings to 1.1 V, beyond the
            %1 V range - the check used to add the offset with its sign
            testCase.reply("/sigouts/0/amplitudes/1", 0.5);
            testCase.reply("/sigouts/0/offset", -0.6);
            testCase.verifyError(@() testCase.Instrument.SetRangeOutput(1), "MFLI_SetRangeOutput_Error:OutputOverload");

            %...but with +0.3 V it fits, and the range is set
            testCase.reply("/sigouts/0/offset", 0.3);
            testCase.Instrument.SetRangeOutput(1);
            testCase.verifyEqual(testCase.lastValueSet("/sigouts/0/range"), 1);
        end

        function ScopeTimeBaseReachesMaxFreqTest(testCase)
            %The slowest time base sampling at least twice maxFreq (60 MHz /
            %2^n). 5 kHz used to give 7.32 kHz sampling, reaching only 3.66 kHz
            timeBase = @Palladium.Instruments.ZI_MFLI.ScopeTimeBaseForMaxFreq;
            testCase.verifyEqual(timeBase(5e3), 12, "14.6 kHz sampling");
            testCase.verifyEqual(timeBase(900), 15, "1.83 kHz sampling");
            testCase.verifyEqual(timeBase(1), 15, "Slowest available");
            testCase.verifyEqual(timeBase(20e6), 0, "60 MHz sampling - it never used to pick the fastest");
            testCase.verifyEqual(timeBase(30e6), 0);
            testCase.verifyError(@() timeBase(31e6), "MFLI_Scope_SetScopeFreqMax_Error:FrequencyOutOfRange");

            testCase.Instrument.Scope_SetScopeFreqMax(5e3);
            testCase.verifyEqual(testCase.lastValueSet("/scopes/0/time"), 12);
        end

        function DAQTriggerIsSetOnceForTheDemodulatorTest(testCase)
            %Set once, on the demodulator given, with the signals recorded
            %from it too - the trigger was set twice, the second time always
            %to demodulator 1
            evalc("testCase.Instrument.DAQ_Initialise_Both(""X"", 1);");

            calls = ziDAQ("fake_calls");
            triggerSets = calls(cellfun(@(c) string(c{1}) == "set" && numel(c) >= 3 && string(c{3}) == "triggernode", calls));
            testCase.verifyNumElements(triggerSets, 1);
            testCase.verifyEqual(string(triggerSets{1}{4}), "/" + testCase.DeviceID + "/demods/1/sample.r");

            subscribed = string(cellfun(@(c) c{3}, calls(cellfun(@(c) string(c{1}) == "subscribe", calls)), "UniformOutput", false));
            testCase.verifyTrue(all(contains(subscribed, "/demods/1/")), "Everything recorded from demodulator 2: " + join(subscribed, ", "));
        end
    end

    %% Methods (Private)
    methods (Access = private)
        function reply(testCase, node, value)
            %Make getDouble/getInt of a node (e.g. "/sigouts/0/offset") return value
            ziDAQ("fake_reply", "/" + testCase.DeviceID + node, value);
        end

        function n = callCount(~, command)
            %How many ziDAQ calls of this command, e.g. "execute"
            calls = ziDAQ("fake_calls");
            n = sum(cellfun(@(c) string(c{1}) == command, calls));
        end

        function value = lastValueSet(testCase, node)
            %The last value set (setInt/setDouble) on a node, e.g. "/scopes/0/time"
            calls = ziDAQ("fake_calls");
            path = "/" + testCase.DeviceID + node;
            sets = calls(cellfun(@(c) any(string(c{1}) == ["setInt", "setDouble"]) && string(c{2}) == path, calls));
            testCase.assertNotEmpty(sets, "Nothing set on " + path);
            value = sets{end}{3};
        end
    end
end
