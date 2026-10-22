classdef SetupControlsInstrument < Palladium.Instruments.Keithley2000
    %SetupControlsInstrument - A Keithley2000 that adds a button to the Instrument Options panel's setup controls area, for testing the panel.
    %Keeps the panel it was given in SetupParent, and asks for SetupHeight pixels.

    %% Properties (Public)
    properties (Access = public)
        SetupHeight = 70;       %Height asked for - 0 for no area
        SetupParent = [];       %The panel CreateSetupControls was last given
    end

    %% Methods (Public)
    methods (Access = public)
        function height = CreateSetupControls(this, parent)
            this.SetupParent = parent;
            if this.SetupHeight > 0
                uibutton(parent, "Text", "Do Something");
            end
            height = this.SetupHeight;
        end
    end
end
