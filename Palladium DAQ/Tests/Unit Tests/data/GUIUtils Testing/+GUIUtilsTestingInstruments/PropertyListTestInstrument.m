classdef PropertyListTestInstrument < Palladium.Core.Instrument
    %PropertyListTestInstrument - Instrument for tests only: checks which properties the Instrument Settings panel shows.
    %Used by test_GUIUtils (test_ComputePropertyList_WithInstrument), which
    %checks that GUIUtils.ComputePropertyList lists its public SetObservable
    %properties - including a struct one - and leaves out
    %PropertyThatIsNotSetObservable. Not a real instrument, and not part of
    %Palladium DAQ.

    %% Properties (Public)
    properties (Access = public)
        FullName = "Property List Test Instrument"              %Full name, displayed in the GUI
        PropertyThatIsNotSetObservable = "Test"                 %Public but not SetObservable - must not be listed
    end

    %% Properties (Public, Set Observable)
    properties (Access = public, SetObservable)
        Name = "PropertyListTest"                               %Instrument name
        Connection_Type = Palladium.Enums.ConnectionType.Debug  %Simulated - no hardware
        TestProperty = struct("Name", "Walker", "Mass", 3000)   %A struct-valued setting - must be listed
    end

    %% Constructor
    methods
        function this = PropertyListTestInstrument()
            %Simulated only, with a Sweep Control on offer

            this.DefineSupportedConnectionTypes(["Debug", "GPIB", "Ethernet", "Serial", "USB", "VISA"]);
            this.DefineInstrumentControl(Name = "Sweep Control", ClassName = "SweepController_Stepped", TabName = "Sweep Control", EnabledByDefault = false);
        end
    end

    %% Methods (Public)
    methods (Access = public)
        function [headers, units] = GetHeaders(this)
            %Two columns, matching Measure

            headers = [this.Name + " - Resistance_Ohms", this.Name + " - Current_A"];
            units = ["Ohms", "A"];
        end

        function dataRow = Measure(~)
            %Fixed values

            dataRow = [500 0.1];
        end
    end
end
