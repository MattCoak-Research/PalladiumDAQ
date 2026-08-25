classdef PythonInstrument < Palladium.Core.Instrument
    %PYTHONINSTRUMENT Wrapper for an Instrument.py python-defined
    %instrument.
    %This is an Instrument, and will be handled by Palladium as one, but it
    %contains a reference to a Python class object that does all the actual
    %logic.

    %% Properties (Public)
    properties
        PyInstr = [];
    end

    methods
        function obj = PythonInstrument()
            obj@Palladium.Core.Instrument();
        end

        function outputArg = method1(obj,inputArg)
            %METHOD1 Summary of this method goes here
            %   Detailed explanation goes here
            outputArg = obj.Property1 + inputArg;
        end
    end
end