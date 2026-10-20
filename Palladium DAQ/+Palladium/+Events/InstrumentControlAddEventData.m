classdef (ConstructOnLoad) InstrumentControlAddEventData < event.EventData
    %InstrumentControlAddEventData - Event data for adding an Instrument Control to an instrument.
    %Sent with the InstrumentController's DefaultEnabledInstrumentControlAdd
    %event when an instrument is added, for each of its Instrument Controls
    %that is enabled by default, so the GUI creates the control and its tab.

    %% Properties (Public)
    properties
        InstrumentRef           %The instrument to add the control to
        ControlDetailsStruct    %The control's definition, from DefineInstrumentControl: Name, ControlClassFileName, TabName, EnabledByDefault and UserData
    end

    %% Constructor
    methods
        function data = InstrumentControlAddEventData(instrRef, controlDetailsStruct)
            %Create the event data for one Instrument Control of an instrument.

            data.InstrumentRef = instrRef;
            data.ControlDetailsStruct = controlDetailsStruct;
        end
    end
end
