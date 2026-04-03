classdef MiSTController < Palladium.Core.InstrumentControlBase
    %MiSTController - Logic controller add-on object to be added on to an
    %MiST Instrument object, where it will create a nice visualisation GUI
    %for each channel (ie 4 MiSTChannelDisplay controls)

    %% Properties (Private)
    properties (Access = private)
        GUIViews;
        NUM_CHANNELS = 4;
    end

    %% Constructor
    methods
        function this = MiSTController()
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function CreateInstrumentControlGUI(this, ~, tab, instrRef)
            %Create grid and TempControl component and position them in the
            %tab.
            grid = uigridlayout(tab, "ColumnWidth", {'1x'}, "RowHeight", {10, '1x', 10}, 'RowSpacing', 2);
            colSpec = {'1x'};
            for i = 1 : this.NUM_CHANNELS
                colSpec = [colSpec 'fit']; %#ok<AGROW>
            end
            colSpec = [colSpec '1x'];
            channelsGrid = uigridlayout(grid, "ColumnWidth", colSpec, "RowHeight", {'Fit', '1x'}, 'RowSpacing', 2);
            channelsGrid.Layout.Row = 2;
            channelsGrid.Layout.Column = 1;

            %Make a specific reference in the Instrument Class
            this.Instrument = instrRef;
            this.Instrument.MiSTControlPanel = this;

            %Make stuff for each channel
            for i = 1 : this.NUM_CHANNELS
                %Create a .mlapp custom GUI control and add it to the grid
                comp = Palladium.Instruments.Controls.MiSTChannelDisplayControl(channelsGrid);
                comp.ChannelIndex = i;
                this.GUIViews{i} = comp;
                comp.Layout.Row = 1;
                comp.Layout.Column = i;
                comp.SetTitle("Ch " + num2str(i));

                %Subscribe to events
                addlistener(comp, 'CurrentValueChanged', @(src,evnt)this.SetCurrentCommandGiven(src,evnt));
                addlistener(comp, 'GainValueChanged', @(src,evnt)this.SetGainValueCommandGiven(src,evnt));
            end


        end

        function Initialise(this, gainVals, enabledVals, currentVals) %#ok<INUSD>
            for i = 1 : this.NUM_CHANNELS
                this.GUIViews{i}.SetCurrent(currentVals(i));
                this.GUIViews{i}.SetGain(gainVals(i));
            end
        end

        function RemoveControl(this, instrRef)
            %Clean up references to this in the Lakeshore Instrument Class
            %so it doesn't think we have a heater control
            instrRef.MiSTControlPanel = [];

            %Delete GUI objects
            delete(this.GUIViews);
            this.GUIViews = [];
        end

        function SetCurrentCommandGiven(this, ~, eventData)
            %Pass event-triggered function call through to the Instrument
            index = eventData.Value(1);
            current_uA = eventData.Value(2);
            this.Instrument.SetSingleCurrentValue(index, current_uA);
        end

        function SetGainValueCommandGiven(this, ~, eventData)
            %Pass event-triggered function call through to the Instrument
            index = eventData.Value(1);
            gain = eventData.Value(2);
            this.Instrument.SetSingleGainValue(index, gain);
        end

        function UpdateDisplayedStatus(this, saturationPercent, enabledArray)
            for i = 1 : this.NUM_CHANNELS
                this.GUIViews{i}.UpdateSaturationPercent(saturationPercent(i));
                this.GUIViews{i}.UpdateEnabledStatus(enabledArray(i));
            end
        end

    end
end

