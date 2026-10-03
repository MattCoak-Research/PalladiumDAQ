classdef StubControl < Palladium.Core.InstrumentControlBase
    %StubControl - Minimal InstrumentControl that records the calls an
    %Instrument makes to its registered Controls

    properties (Access = public)
        Recorder;               %Shared InstrumentTestingInstruments.CallRecorder (optional)
        UpdateCount = 0;
        LastDataRow = [];
        LastHeaders = [];
    end

    methods
        function this = StubControl(name)
            this.ControlDetailsStruct = struct("Name", name);
        end

        function CreateInstrumentControlGUI(~, ~, ~, ~)
        end

        function RemoveControl(~, ~)
        end

        function Update(this)
            this.UpdateCount = this.UpdateCount + 1;
            this.Log("Update:" + this.GetName());
        end

        function UpdateData(this, dataRow, headers)
            this.LastDataRow = dataRow;
            this.LastHeaders = headers;
            this.Log("UpdateData:" + this.GetName());
        end

        %% Test access to protected InstrumentControlBase members
        function SetInstrumentForTest(this, instrument)
            this.Instrument = instrument;
        end

        function dataWriter = InitialiseDataWriterForTest(this, fileNameSuffix, varargin)
            dataWriter = this.InitialiseDataWriter(fileNameSuffix, varargin{:});
        end
    end

    methods (Access = private)
        function Log(this, entry)
            if ~isempty(this.Recorder)
                this.Recorder.Record(entry);
            end
        end
    end
end
