classdef InstrumentCommand < Palladium.Sequence.Commands.Command
    %COMMAND 

    %% Properties (Public)
    properties(Access = public)
        Instrument;
        CommandString;
        ControlName = string.empty;
        Target; %Either the instrument or the control, if a control 
    end

    %% Constructor
    methods
        function this = InstrumentCommand(instrument, command, controlName, Settings)
            arguments
                instrument (1,1) Palladium.Core.Instrument;
                command {mustBeTextScalar};
                controlName = string.empty;
                Settings.FunctionOnComplete = [];
            end

            this.Instrument = instrument;
            this.CommandString = command;
            this.ControlName = controlName;
            this.FunctionOnComplete = Settings.FunctionOnComplete;

            %Set the target to either the instrument or its control, if
            %that is not empty
            if isempty(controlName)
                this.Target = this.Instrument;
            else
                this.Target = this.Instrument.GetRegisteredControlObjectsFromName(controlName);
            end

            this.IsCompleteFn = this.GetCompleteFn(this.Target);
        end
    end

    %% Methods (Public)
    methods(Access = public)

        
    end

    %% Methods (Private)
    methods(Access = private)

        function completeFn = GetCompleteFn(this, target)
            completeFn = target.GetCommandCompleteFn(this.CommandString);
        end

    end
end