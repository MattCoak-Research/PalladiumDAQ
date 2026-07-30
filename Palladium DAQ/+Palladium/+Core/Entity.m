classdef(Abstract) Entity < handle
    %Instrument - Abstract (very abstract!) base class which both
    %Instrument and InstrumentControlBase (and hence all Instruments and
    %all InstrumentControls) inherit from. Has some shared functionalities

    %% Properties (Private)
    properties(Access = private)
        RegisteredCommandCompleteQueryStructs = [];
    end

    %% Methods (Public, Sealed)
    methods (Access = public, Sealed)

        function commandCompleteFn = GetCommandCompleteFn(this, commandStr)
            %This gets called by InstrumentCommand when Sequence Commands
            %are being given and we need to find out if they execute
            %immediately or we need a function to keep coming back and
            %evaluating every tick to see if it's done (ie setting PPMS to
            %a temperature).
            %Register functions with RegisterCommandCompleteQuery function

            commandCompleteFn = [];

            if isempty(this.RegisteredCommandCompleteQueryStructs)                
                return;
            end

            %Strip out the () arguments bit and just have the name
            commandStr = extractBefore(commandStr, '(');
            
            for i = 1 : length(this.RegisteredCommandCompleteQueryStructs)
                s = this.RegisteredCommandCompleteQueryStructs(i);

                if strcmp(s.CommandFunctionName, commandStr)
                    commandCompleteFn = s.FnHandle;
                    return;
                end
            end            

        end

        function RegisterCommandCompleteQuery(this, commandFunctionName, fnHandle)
            s.CommandFunctionName = commandFunctionName;
            s.FnHandle = fnHandle;

            if isempty(this.RegisteredCommandCompleteQueryStructs)
                this.RegisteredCommandCompleteQueryStructs = s;
            else
                this.RegisteredCommandCompleteQueryStructs = [this.RegisteredCommandCompleteQueryStructs, s];
            end
        end

    end
end