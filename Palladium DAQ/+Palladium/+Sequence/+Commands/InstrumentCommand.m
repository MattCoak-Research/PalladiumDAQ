classdef InstrumentCommand < Palladium.Sequence.Commands.Command
    %COMMAND 

    %% Properties (Public)
    properties(Access = public)
        Instrument;
        CommandString;
        ControlName = string.empty;
        FunctionOnComplete = [];
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
        end
    end

    %% Methods (Public)
    methods(Access = public)

        
    end
end