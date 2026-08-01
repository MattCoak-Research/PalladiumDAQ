classdef CommandEncoder < handle
    %COMMANDENCODER 
    %Handles parsing sequence text into Command objects, and creating those
    %strings
    %
    %Sequence text looks like:
    %[WAIT] 2.5 Sec

    %% Properties (Constant, Public)
    properties(Constant, Access=public)
        Enc_Wait = "WAIT";
        Enc_Instr = "INSTR";
    end

    %% Properties (Public)
    properties
        
    end

    %% Properties (Private)
    properties(Access=private)

    end
  
    %% Constructor
    methods

        function this = CommandEncoder()
        end

    end

    %% Methods (Public)
    methods(Access=public)

        function str = CommandToString(this, com)
            classType = extractAfter(class(com), 'Commands.');

            switch(classType)
                case("InstrumentCommand")
                    str = Palladium.Sequence.CommandEncoder.Enc_Instr;
                case("WaitCommand")
                    waitVal = com.Wait_seconds;
                    waitDisplayUnit = com.WaitDisplayUnit;
                    str = this.BuildWaitCommand(WaitValue=waitVal, WaitUnit=waitDisplayUnit);
                otherwise 
                    error("Unrecognised command class type in CommandEncoder: " + string(classType));
            end

        end

        function com = StringToCommand(this, str)
            arguments
                this;
                str {mustBeTextScalar};
            end
            
            typeStr = extractBetween(str, '[', ']');
            assert(~isempty(typeStr), "Type String not found");

            commandStr = extractAfter(str, ']');
            commandStr = strtrim(commandStr);

            % Parse the command string based on the provided type
            switch typeStr{1}
                case this.Enc_Wait
                    [waitVal_Sec, waitUnits] = this.ParseWaitCommand(commandStr);
                    com = Palladium.Sequence.Commands.WaitCommand(waitVal_Sec, "WaitDisplayUnits", waitUnits);
                case this.Enc_Instr
                    com = InstrumentCommand(Settings.CommandStr);
                otherwise
                    error("Unrecognised command type string: " + string(typeStr{1}));
            end

        end

    end

    %% Methods (Private)
    methods(Access=private)
        
        function str = BuildWaitCommand(this, Settings)
            arguments
                this;
                Settings.WaitValue (1,1) double;
                Settings.WaitUnit {mustBeTextScalar} = "sec";
            end

            %Convert to lower case so we don't have to worry about Sec not
            %being recognised as sec
            waitUnit = lower(Settings.WaitUnit);

            switch(waitUnit)
                case("sec")
                    val = Settings.WaitValue;
                case("min")
                    val = Settings.WaitValue / 60;
                case("hr")
                    val = Settings.WaitValue / 3600;
                otherwise
                    error("Unrecognised wait unit: " + Settings.WaitUnit);
            end

            %Round to 3dp, stop it getting silly
            val = round(val, 3);

            %Build the command
            str = "[" + Palladium.Sequence.CommandEncoder.Enc_Wait + "]" + " " + num2str(val) + " " + Settings.WaitUnit;
        end

        function [waitVal_Sec, waitUnit] = ParseWaitCommand(this, str)
   
            ss = strsplit(str, " ");
            val = str2double(ss{1});
            waitUnit = ss{2};

            switch(waitUnit)
                case("sec")
                    waitVal_Sec = val;
                case("min")
                    waitVal_Sec = val * 60;
                case("hr")
                    waitVal_Sec = val * 3600;
                otherwise
                    error("Unrecognised wait unit: " + Settings.WaitUnit);
            end

        end

    end

end