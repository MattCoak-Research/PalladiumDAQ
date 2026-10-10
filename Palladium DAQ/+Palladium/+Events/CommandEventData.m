classdef (ConstructOnLoad) CommandEventData < event.EventData
    %CommandEventData - Event data for an instrument command to run straight away.
    %Sent with the Sequence Editor's SingleCommandQueued event, to run one
    %command on an instrument (or one of its Instrument Controls) outside a
    %sequence. The Controller queues it to run on the next measurement tick.

    %% Properties (Public)
    properties
        InstrumentRef               %The instrument to run the command on
        CommandString               %The method call to run, e.g. "SetTemperature(10, 2)"
        ControlName                 %Name of the Instrument Control to run it on instead, or empty to run it on the instrument
        FunctionToRunOnComplete     %Function handle called when the command has completed, or [] for none
    end

    %% Constructor
    methods
        function data = CommandEventData(instrRef, commandStr, controlName, completeFunc)
            %Create the event data for one command.
            %
            %Inputs:
            %   instrRef     - the instrument to run the command on
            %   commandStr   - the method call to run, e.g. "SetTemperature(10, 2)"
            %   controlName  - name of an Instrument Control of that instrument to
            %                  run it on instead. Default "" (the instrument)
            %   completeFunc - function handle called when the command has
            %                  completed. Default [] (none)

            arguments
                instrRef (1,1) Palladium.Core.Instrument;
                commandStr {mustBeTextScalar};
                controlName = "";
                completeFunc = [];
            end

            data.InstrumentRef = instrRef;
            data.CommandString = commandStr;

            if isempty(char(controlName))
                data.ControlName = string.empty;
            else
                data.ControlName = controlName;
            end

            data.FunctionToRunOnComplete = completeFunc;
        end
    end
end
