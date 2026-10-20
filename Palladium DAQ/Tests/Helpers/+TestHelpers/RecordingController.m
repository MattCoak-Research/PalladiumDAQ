classdef RecordingController < handle
    %RecordingController - Stand-in for Palladium.Core.Controller that records the messages the Logger shows in the GUI.
    %Pass it as the Logger's Controller to see what reaches the GUI's
    %status bar, which tests can't read from the Command Window (warnings
    %go to stderr, which evalc doesn't capture).

    %% Properties (Public)
    properties (Access = public)
        Messages = strings(0, 1);   %Each message shown, in order
        Colours = strings(0, 1);    %Its colour: "Green", "Yellow" or "Red"
    end

    %% Methods (Public)
    methods (Access = public)
        function ShowMessageInGUI(this, colour, message)
            %Record a message, as the Controller would show it.

            this.Colours(end+1, 1) = string(colour);
            this.Messages(end+1, 1) = string(message);
        end

        function tf = HasGUIWindow(~)
            %No real window.

            tf = false;
        end
    end
end
