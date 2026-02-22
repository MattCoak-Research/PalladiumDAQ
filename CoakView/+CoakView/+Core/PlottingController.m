classdef PlottingController < handle
    %PlottingController

    properties
        PlotterSettings;
    end

    properties(GetAccess = public, SetAccess = private)    
        
    end

    properties(Access = private)
        Plotters = {};
        Controller;
    end

    events
       
    end

    methods

        %% Constructor
        function this = PlottingController(controller)
            this.Controller = controller;
        end

        %% CleanUpPlotters
        function CleanUpPlotters(this)
            %Remove any plotters that may have been deleted (as part of
            %e.g. an InstrumentControl tab that has been deleted from the
            %GUI), from the list to update
             for i = length(this.Plotters) : -1 : 1
                 if ~isvalid(this.Plotters{i})
                     this.Plotters(i) = [];
                 end
             end
        end

        %% ClearPlots
        function ClearPlots(this)
            for i = 1 : length(this.Plotters)
                this.Plotters{i}.ClearData();
            end
        end  

        %% CreateNewPlotter
        function pltr = CreateNewPlotter(this, parent, size)
            %Create plotter component
            pltr = CoakView.Components.PlotterPanel(parent);

            %Apply settings loaded from json file
            plotterSettings = this.PlotterSettings;
            plotterSettings.Size = size;
            pltr.ApplySettings(plotterSettings);

            %Subscribe to events
            addlistener(pltr, 'AxesSelectionChange', @(src,evnt)this.PlotterAxesSelectionChange(src));
            addlistener(pltr, 'SavePlot', @(src,evnt)this.SavePlot(evnt));
        end

        %% CreateNewSimplePlotter
        function pltr = CreateNewSimplePlotter(this, parent, size)
            %Create plotter component
            pltr = CoakView.Components.SimplePlotterPanel(parent);

            %Apply settings loaded from json file
            plotterSettings = this.PlotterSettings;
            plotterSettings.Size = size;
            pltr.ApplySettings(plotterSettings);

            %Subscribe to events
            addlistener(pltr, 'SavePlot', @(src,evnt)this.SavePlot(evnt));
        end

        %% RegisterPlotterObject
        function RegisterPlotterObject(this, pltr)
            %Add to the list of plotters
            if(isempty(this.Plotters))
                this.Plotters = {pltr};
            else
                this.Plotters = [this.Plotters, {pltr}];
            end

            %Update the variables avaliable to the plotter
            pltr.UpdateVariables(this.Controller.Headers);
        end

        %% PlotData
        function PlotData(this, newDataRow)
            %Check for any plotters that may have been closed by a
            %discourteous user - remove them from the list of plotters to
            %update if so.
            for i = length(this.Plotters) : - 1 : 1
                if(~isvalid(this.Plotters{i}))
                    this.Plotters(i) = [];
                end
            end

            for i = 1 : length(this.Plotters)
                pltr = this.Plotters{i};

                %If possible, just append the new row of data to the
                %existing plot (for speed). If e.g. the axis selections
                %have changed on this Plotter and it needs a full refresh,
                %the TryAppendData call will return false and we should
                %call the full UpdatePlot method instead
                if(~pltr.TryAppendData(newDataRow))
                    pltr.PlotData(this.Controller.DataTable);
                end
            end
        end         

        %% PlotterAxesSelectionChange
        function PlotterAxesSelectionChange(this, pltr)
            %This is needed for the case where we want to change the
            %displayed data in a Plotter, but the loop is not running.
            %While measurement loop is running, the Plotter will get an
            %Update call with new data every tick, and if it has
            %established that a button has been pressed and it needs to
            %e.g. change the data plotted on a y axis, it sets a bool flag
            %to do a plot refresh next update tick. If there are no ticks
            %this does not happen, so in that case, we hook into the
            %Plotter's event and fire a manual replot in the case that
            %measurements are stopped
            if this.Controller.TimingLoopController.State ~= "Running"
                %Have to pass whole data table back in - Plotters do not
                %store/copy these, that would be very expensive.
                %If the data table is empty, for now just do nothing -
                %might be clearer UX to clear the plot, but then again
                %might be annoying to delete the data for no obvious reason
                if ~isempty(this.Controller.DataTable)
                    pltr.PlotData(this.Controller.DataTable);
                end
            end
        end  

        %% SavePlot
        function SavePlot(this, eventData)
            try
                fig = eventData.Figure;
                this.Controller.DataWriter.SaveFigure(fig, this.Controller.FileWriteDetails.Directory, this.Controller.FileWriteDetails.FileName);

                %Display a status message in the logger
                this.Controller.Log("Info", "Plot saved", "Green", "Plot saved");
            catch err
                this.Controller.HandleError("Error saving figure", err);
            end
        end

        %% UpdatePlotVariableNames
        function UpdatePlotVariableNames(this, varNames)
            for i = 1 : length(this.Plotters)
                this.Plotters{i}.UpdateVariables(varNames);
            end
        end

    end

    methods(Access=private)

       
    end

end