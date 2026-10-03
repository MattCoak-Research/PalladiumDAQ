classdef StubInstrument < Palladium.Core.Instrument
    %StubInstrument - Minimal concrete Instrument for testing the
    %Palladium.Core.Instrument base class. Overrides the hardware-facing
    %protected methods to just record that they were called, and exposes
    %the protected state tests need to inspect (as *ForTest methods).

    %% Properties (Public)
    properties (Access = public)
        FullName = "Stub Instrument";
    end

    %% Properties (Public, Set Observable)
    properties (Access = public, SetObservable)
        Name = "Stub";
        Connection_Type = Palladium.Enums.ConnectionType.Debug;
    end

    %% Properties (Public) - test controls
    properties (Access = public)
        Recorder;                   %Shared InstrumentTestingInstruments.CallRecorder (optional)
        DataRowToReturn = [1 2];    %Returned by Measure
        MetadataToReturn = [];      %Returned by CollectMetaData
        PropertiesToIgnore = {};    %Returned by GetPropertiesToIgnore
        ThrowOnConnect = false;     %Make the Connect* overrides error
        ConnectedVia = "";          %Which Connect* method ran
        UseBaseConnectionMethods = false;       %Run the real Instrument Connect* methods instead of just recording the call
        UseBaseCollectMetaData = false;         %Run the real (default) Instrument.CollectMetaData
        UseBaseGetPropertiesToIgnore = false;   %Run the real (default) Instrument.GetPropertiesToIgnore
        AppliedSettings = {};       %Every settings value passed to ApplySettings
        InitialisedCount = 0;       %Times OnInitialised ran
    end

    %% Methods (Public)
    methods (Access = public)

        function [Headers, Units] = GetHeaders(this)
            Headers = [this.Name + " - A", this.Name + " - B"];
            Units = ["V", "A"];
        end

        function dataRow = Measure(this)
            this.Log("Measure");
            dataRow = this.DataRowToReturn;
        end

        function metadataStruct = CollectMetaData(this)
            if this.UseBaseCollectMetaData
                metadataStruct = CollectMetaData@Palladium.Core.Instrument(this);
            else
                metadataStruct = this.MetadataToReturn;
            end
        end

        %% Test access to protected state
        function ConvertToCategoricalForTest(this, varargin)
            this.ConvertToCategorical(varargin{:});
        end

        function catOut = ConvertToCategoricalOutputForTest(this, inputStr, catNames)
            catOut = this.ConvertToCategorical(inputStr, catNames);
        end

        function DefineControlForTest(this, varargin)
            this.DefineInstrumentControl(varargin{:});
        end

        function settings = GetConnectionSettingsForTest(this)
            settings = this.ConnectionSettings;
        end

        function handle = GetDeviceHandleForTest(this)
            handle = this.DeviceHandle;
        end

        function settings = GetSettingsToApplyForTest(this)
            settings = this.SettingsToApply;
        end

        function simulatedData = GetSimulatedDataForTest(this)
            simulatedData = this.SimulatedData;
        end

        function val = RetrieveSimulatedDataValueForTest(this, varargin)
            val = this.RetrieveSimulatedDataValue(varargin{:});
        end

        function SetConnectionSettingsForTest(this, settings)
            this.ConnectionSettings = settings;
        end

        function SetDeviceHandleForTest(this, handle)
            this.DeviceHandle = handle;
        end

        function SetSimulatedDataForTest(this, simulatedData)
            this.SimulatedData = simulatedData;
        end

    end

    %% Methods (Protected)
    methods (Access = protected)

        function ApplySettings(this, settings)
            this.AppliedSettings{end + 1} = settings;
        end

        function ConnectGPIB(this)
            if this.UseBaseConnectionMethods
                ConnectGPIB@Palladium.Core.Instrument(this);
            else
                this.RecordConnection("GPIB");
            end
        end

        function ConnectSerial(this)
            if this.UseBaseConnectionMethods
                ConnectSerial@Palladium.Core.Instrument(this);
            else
                this.RecordConnection("Serial");
            end
        end

        function ConnectTCPIP(this)
            if this.UseBaseConnectionMethods
                ConnectTCPIP@Palladium.Core.Instrument(this);
            else
                this.RecordConnection("Ethernet");
            end
        end

        function ConnectVISA(this)
            if this.UseBaseConnectionMethods
                ConnectVISA@Palladium.Core.Instrument(this);
            else
                this.RecordConnection("VISA");
            end
        end

        function propertiesToIgnore = GetPropertiesToIgnore(this)
            if this.UseBaseGetPropertiesToIgnore
                propertiesToIgnore = GetPropertiesToIgnore@Palladium.Core.Instrument(this);
            else
                propertiesToIgnore = this.PropertiesToIgnore;
            end
        end

        function OnInitialised(this)
            this.InitialisedCount = this.InitialisedCount + 1;
        end

    end

    %% Methods (Private)
    methods (Access = private)

        function Log(this, entry)
            if ~isempty(this.Recorder)
                this.Recorder.Record(entry);
            end
        end

        function RecordConnection(this, via)
            if this.ThrowOnConnect
                error("StubInstrument:ConnectFailed", "Stub connection failure");
            end
            this.ConnectedVia = via;
        end

    end
end
