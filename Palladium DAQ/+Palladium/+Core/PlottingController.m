classdef PlottingController < handle
    %PlottingController

    %% Properties (Public)
    properties
        PlotterSettings;
    end

    %% Properties (Private)
    properties(Access = private)
        Plotters = {};
    end

    %% Constructor
    methods
        function this = PlottingController()
        end
    end

    %% Methods (Public)
    methods(Access = public)

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

        function ClearPlots(this)
            for i = 1 : length(this.Plotters)
                this.Plotters{i}.ClearData();
            end
        end

        function pltr = CreateNewPlotter(this, parent, size)
            %Create plotter component
            pltr = Palladium.Components.PlotterPanel(parent);

            %Apply settings loaded from json file
            plotterSettings = this.PlotterSettings;
            plotterSettings.Size = size;
            pltr.ApplySettings(plotterSettings);
        end

        function pltr = CreateNewSimplePlotter(this, parent, size)
            %Create plotter component
            pltr = Palladium.Components.SimplePlotterPanel(parent);

            %Apply settings loaded from json file
            plotterSettings = this.PlotterSettings;
            plotterSettings.Size = size;
            pltr.ApplySettings(plotterSettings);
        end

        function RegisterPlotterObject(this, pltr, headers)
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
            for i = 1 : length(this.Plotters)
                this.Plotters{i}.UpdateVariables(varNames);
            end
        end

    end

end