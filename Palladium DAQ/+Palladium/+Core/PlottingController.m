classdef PlottingController < handle
    %PlottingController - Creates the plotters and keeps the registered ones up to date each tick.
    %Created by the Controller, which holds it as `PlottingController`; the
    %Controller's `AddNewPlotter` and `AddNewSimplePlotter` use it to make
    %plotters (e.g. for the main window or an Instrument Control's tab).
    %
    %Registered plotters (from `AddNewPlotter`) are kept in a list and
    %updated by the Controller: their variable names and data are reset
    %when measurements start (`UpdatePlotVariableNames`, `ClearPlots`), and
    %each tick `PlotData` adds the new data row. Simple plotters are not
    %registered; whatever made them sends them data itself. Plotters that
    %have been deleted, e.g. with their tab, are dropped from the list.

    %% Properties (Public)
    properties
        PlotterSettings;    %Plotter appearance settings (colours, markers, font size etc.), loaded from the config file by the Controller and applied to each new plotter
    end

    %% Properties (Private)
    properties(Access = private)
        Plotters = {};      %Cell array of the registered plotters, updated each tick
    end

    %% Constructor
    methods
        function this = PlottingController()
            %Create the PlottingController, with no plotters registered.
        end
    end

    %% Methods (Public)
    methods(Access = public)

        function CleanUpPlotters(this)
            %Remove deleted plotters (e.g. on an Instrument Control tab that was closed) from the list.

            for i = length(this.Plotters) : -1 : 1
                if ~isvalid(this.Plotters{i})
                    this.Plotters(i) = [];
                end
            end
        end

        function ClearPlots(this)
            %Clear the data from every registered plotter.

            for i = 1 : length(this.Plotters)
                this.Plotters{i}.ClearData();
            end
        end

        function pltr = CreateNewPlotter(this, parent, size)
            %Create a plotter in a container, with PlotterSettings applied.
            %Does not register it - see RegisterPlotterObject
            %
            %Inputs:
            %   parent - the container to put the plotter in
            %   size   - the plotter's size, e.g. "Medium"
            %
            %Outputs:
            %   pltr - the new Palladium.Components.PlotterPanel

            %Create plotter component
            pltr = Palladium.Components.PlotterPanel(parent);

            %Apply settings loaded from json file
            plotterSettings = this.PlotterSettings;
            plotterSettings.Size = size;
            pltr.ApplySettings(plotterSettings);
        end

        function pltr = CreateNewSimplePlotter(this, parent, size)
            %Create a simple plotter, with no axis drop-downs, in a container, with PlotterSettings applied.
            %
            %Inputs:
            %   parent - the container to put the plotter in
            %   size   - the plotter's size, e.g. "Medium"
            %
            %Outputs:
            %   pltr - the new Palladium.Components.SimplePlotterPanel

            %Create plotter component
            pltr = Palladium.Components.SimplePlotterPanel(parent);

            %Apply settings loaded from json file
            plotterSettings = this.PlotterSettings;
            plotterSettings.Size = size;
            pltr.ApplySettings(plotterSettings);
        end

        function RegisterPlotterObject(this, pltr, headers)
            %Add a plotter to the list updated each tick, and give it the data column headers.
            %
            %Inputs:
            %   pltr    - the plotter, from CreateNewPlotter
            %   headers - the data column headers it can plot

            %Add to the list of plotters
            if(isempty(this.Plotters))
                this.Plotters = {pltr};
            else
                this.Plotters = [this.Plotters, {pltr}];
            end

            %Update the variables avaliable to the plotter
            pltr.UpdateVariables(headers);
        end

        function PlotData(this, newDataRow, fullDataTable)
            %Add a new data row to every registered plotter, replotting all the data where needed.
            %Called by the Controller each tick. Each plotter appends the
            %row if it can, or replots fullDataTable if it needs a full
            %refresh, e.g. after its axes were changed. Deleted plotters are
            %first dropped from the list
            %
            %Inputs:
            %   newDataRow    - the new data row
            %   fullDataTable - all the data rows so far, including newDataRow

            %Note - was worried passing in fullDataTable every tick would
            %be very bad for performance, but apparantly MATLAB basically
            %passes large matrices in by reference so this has no cost! See
            %https://stackoverflow.com/questions/13078338/passing-arrays-without-overhead-preferably-by-reference-to-avoid-duplicati

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
                    pltr.PlotData(fullDataTable);
                end
            end
        end

        function UpdatePlotVariableNames(this, varNames)
            %Give every registered plotter a new set of data column headers to choose from.
            %Called by the Controller when measurements are initialised
            %
            %Inputs:
            %   varNames - the data column headers

            for i = 1 : length(this.Plotters)
                this.Plotters{i}.UpdateVariables(varNames);
            end
        end

    end

end
