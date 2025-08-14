classdef InstrumentControlBase < handle
    %InstrumentControlBase - Base class for a Logic controller add-on object to be added on to an
    %Instrument object, eg LakeshoreHeaterControl.m
    
    properties
        ControlDetailsStruct;
    end
    
    properties (Access = private)
    end

    methods (Abstract)  
        CreateInstrumentControlGUI(this, controller, tab, instrRef);
        RemoveControl(this);
    end
    
    methods

        %% Constructor
        function this = InstrumentControlBase()
        end        

        %% GetName
        function name = GetName(this)
            name = this.ControlDetailsStruct.Name;
        end
        
    end

    methods (Access = private)
       
    end
end

