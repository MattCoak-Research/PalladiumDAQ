classdef MetadataErrorInstrument < Palladium.Core.Instrument
    %MetadataErrorInstrument - Test-only simulated instrument whose metadata collection fails.
    %Connects and measures like any simulated instrument, but CollectMetaData
    %always errors - to test what happens when that fails as measurements
    %start. Only on the path in the tests that add this folder, so it is
    %never offered in the app.

    %% Properties (Public)
    properties(Access = public)
        FullName = "Metadata Error Test Instrument";   %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    properties(Access = public, SetObservable)
        Name = "MetaErr";                                       %Instrument name, used as the prefix of its data column headers
        Connection_Type = Palladium.Enums.ConnectionType.Debug; %Simulated only
    end

    %% Constructor
    methods
        function this = MetadataErrorInstrument()
            %Offer only the Debug connection type.

            this.DefineSupportedConnectionTypes("Debug");
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function metadataStruct = CollectMetaData(~) %#ok<STOUT>
            %Always error, as if the instrument's settings could not be read.

            error("MetadataErrorInstrument:Failed", "Test failure collecting metadata");
        end

        function [headers, units] = GetHeaders(this)
            %One column, a simulated value.

            headers = this.Name + " - Value";
            units = "";
        end

        function dataRow = Measure(this)
            %A simulated value.

            dataRow = this.GenerateSimulatedData(1, Baseline = 1, Variance = 0.1);
        end

    end
end
