classdef MagnetController < CoakView.Core.InstrumentControlBase
    %MagnetController - Logic controller add-on object to be added on to an
    %Instrument object, where it will handle the logic of controlling a
    %superconducting magnet - for now an Oxford Mercury IPS120
    
    properties

    end

    properties (Access = private)
        GUIView;
    end
    
    methods

        %% Constructor
        function this = MagnetController()
        end

        %% CreateInstrumentControlGUI
        function CreateInstrumentControlGUI(this, controller, tab, instrRef)
            %Create grid and TempControl component and position them in the
            %tab. 
            grid = uigridlayout(tab, "ColumnWidth", {'fit', '1x'}, "RowHeight", {10, '1x', 10}, 'RowSpacing', 2);

            %Create a .mlapp custom GUI control and add it to the grid
            comp = CoakView.Instruments.Controls.MagnetControlPanel(grid);
            this.GUIView = comp;
            comp.Layout.Row = 2;
            comp.Layout.Column = 1;
            this.GUIView.SetName(instrRef.Name + " - Magnet Control");

            %Make a specific reference in the Instrument Class
            this.Instrument = instrRef;

            %Add a plotter as well underneath
            plotter = controller.AddNewPlotter(grid, Size="Medium");
            plotter.Layout.Row = 2;
            plotter.Layout.Column = 2;   

            %Set default displayed axes for the plotter
            plotter.SetDefaultXAxis("Time (mins)");

            %Subscribe to events
            addlistener(comp, 'HoldCommandGiven', @(src,evnt)this.HoldCommandGiven(src,evnt));            
            addlistener(comp, 'RampToZeroCommandGiven', @(src,evnt)this.RampToZeroCommandGiven(src,evnt));         
            addlistener(comp, 'ToSetPointCommandGiven', @(src,evnt)this.ToSetPointCommandGiven(src,evnt));          
            addlistener(comp, 'RampRateChanged', @(src,evnt)this.RampRateChanged(src,evnt));            
            addlistener(comp, 'SetPointChanged', @(src,evnt)this.SetPointChanged(src,evnt));                 
        end

        %% HoldCommandGiven
        function HoldCommandGiven(this, ~, ~)
            %Pass event-triggered function call through to the Instrument
            this.Instrument.SetState_Hold();
        end
 
        %% RampToZeroCommandGiven
        function RampToZeroCommandGiven(this, ~, ~)
            %Pass event-triggered function call through to the Instrument
            this.Instrument.SetState_RampToZero();
        end 
        
        %% ToSetPointCommandGiven
        function ToSetPointCommandGiven(this, ~, ~)
            %Pass event-triggered function call through to the Instrument
            this.Instrument.SetState_RampToSetPoint();
        end
  
        %% RampRateChanged
        function RampRateChanged(this, ~, eventData)
            %Pass event-triggered function call through to the Instrument
            rampRate_Tmin = eventData.Value;
            this.Instrument.SetRampRate_TeslaMin(rampRate_Tmin);
        end  

         %% RemoveControl
        function RemoveControl(this, instrRef)
            %Delete GUI objects
            delete(this.GUIView);
            this.GUIView = [];
        end

        %% SetPointChanged
        function SetPointChanged(this, ~, eventData)
            %Pass event-triggered function call through to the Instrument
            setPoint_T = eventData.Value;            
            this.Instrument.SetTargetField(setPoint_T);
        end

        %% Update
        function Update(this)
            %Do nothing - wait for UpdateData which happens after the
            %Measure command
        end

        %% UpdateData
        function UpdateData(this, dataRow, headers)
            statusStruct = this.Instrument.GatherStatusStructForControlPanel();
            this.UpdateDisplayedStatus(statusStruct);
        end

        %% UpdateDisplayedStatus
        function UpdateDisplayedStatus(this, statusStruct)
            this.GUIView.UpdateDisplayedStatus(statusStruct);
        end

    end

    methods (Access = private)

      
    end
end

