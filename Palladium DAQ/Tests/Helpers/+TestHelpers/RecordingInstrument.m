classdef RecordingInstrument < Palladium.Core.Instrument
    %RecordingInstrument - Simulated instrument for tests, that records the arguments its methods are called with.
    %Used to check how sequence instrument commands, such as
    %Record(10, "Sample A"), are turned into method calls.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Recording Test Instrument";     %Full name, displayed in the GUI
        LastCall = "";                              %Name of the last method called with Record or RecordNothing
        LastArgs = {};                              %Arguments of the last call to Record, as a cell array
    end

    %% Properties (Public, Set Observable)
    properties(Access = public, SetObservable)
        Name = "Recorder";                                          %Instrument name
        Connection_Type = Palladium.Enums.ConnectionType.Debug;     %Simulated - no hardware
    end

    %% Constructor
    methods
        function this = RecordingInstrument()
            %Simulated only
            this.DefineSupportedConnectionTypes("Debug");
        end
    end

    %% Methods (Public)
    methods (Access = public)
        function [Headers, Units] = GetHeaders(this)
            %One data column
            Headers = this.Name + " - Value";
            Units = "";
        end

        function dataRow = Measure(~)
            %A fixed reading
            dataRow = 0;
        end

        function Record(this, varargin)
            %Record the arguments this is called with
            this.LastCall = "Record";
            this.LastArgs = varargin;
        end

        function RecordNothing(this)
            %A method with no arguments
            this.LastCall = "RecordNothing";
            this.LastArgs = {};
        end
    end
end
