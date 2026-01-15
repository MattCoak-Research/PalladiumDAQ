classdef CoakView_NoGUI < handle
    %CoakView_NoGUI - a view/frontend implementation of CoakView that
    %doesn't have a GUI at all

    properties (Access = public)
        Controller; % Logic class that controls all the backend functionality for the GUI
    end

    properties (Access = private)
        DependentWindows = {}; %Windows such as Plotter windows, BN Displays etc, that we want to close when the main window is closed, so we should keep track of references to them all
    end

    methods

        %% Constructor
        function this = CoakView_NoGUI()

        end

        %% AddNewPlotter
        function pltr = AddNewPlotter(app, parent, size)
            %This is used by things like Instrument Control creating GUIs
            %and placing Plotters in exisiting Gridlayouts
            arguments
                app;
                parent;
                size = "Medium";
            end

            %Create the plotter
            pltr = app.CreateNewPlotter(parent, size);
        end

        %% AddNewSimplePlotter
        function pltr = AddNewSimplePlotter(app, parent, size)
            %This is used by things like Instrument Control creating GUIs
            %and placing Plotters in exisiting Gridlayouts
            arguments
                app;
                parent;
                size = "Medium";
            end

            %Create the plotter
            pltr = app.CreateNewSimplePlotter(parent, size);
        end 

        %% AddNewPlottingTab
        function [listOfPltrs tab] = AddNewPlottingTab(this, rows, columns)
            listOfPltrs = [];
            tab = [];
        end

        %% AddNewPlottingWindow
        function listOfPltrs = AddNewPlottingWindow(this, rows, columns)
            listOfPltrs = [];
        end

        %% ApplySettings
        function ApplySettings(this, pathSettings, windowSettings)
        end

        %% CloseProgressBar
        function CloseProgressBar(~)
            disp("Operation Complete");
        end

        %% CreateInstrumentControlTab
        function tab = CreateInstrumentControlTab(this, tabName)
            tab = this.CreateNewTab(tabName);
        end

        %% CreateNewTab
        function tab = CreateNewTab(this, title)
            disp("Can't really make a tab in a zero-GUI View.. (tried to make one called " + title +")");
        end

        %% DisplayUpdateTime
        function DisplayUpdateTime(this, timeInS)
        end

        %% GetUIFigureHandle
        function figHandle = GetUIFigureHandle(app)
            figHandle = [];
        end

        %% GrabPathData
        function [dir, fileName, description, ext] = GrabPathData(this)
            dir = [];
            fileName = [];
            description = [];
            ext = [];
        end

        %% GrabFileWriteModeData
        function [saveFile, fileWriteMode] = GrabFileWriteModeData(this)
            % saveFile = app.FilePathsPanel.SaveToFile;
            % fileWriteMode = app.FilePathsPanel.FileWriteOption;
        end

        %% FinalisePreset
        function FinalisePreset(this)

        end

        %% LoadInstrumentClasses
        function LoadInstrumentClasses(this, folderPath)
            % app.InstrumentBrowserPanel.LoadInstrumentClassesFromFolder(folderPath);
        end

        %% OnFileWriteOptionsChanged
        function OnFileWriteOptionsChanged(this, fileWriteDetails)

        end

        %% OnInstrumentAdded
        function OnInstrumentAdded(this, instrStringToAdd, instance)

        end

        %% OnInstrumentRemoved
        function OnInstrumentRemoved(comp, instrumentRef)

        end
  
        %% OnPaused
        function OnPaused(this)

        end

        %% OnResumed
        function OnResumed(this)

        end

        %% OnStarted
        function OnStarted(this)

        end

        %% OnStopped
        function OnStopped(this)

        end

        %% OnTargetUpdateTimeChanged
        function OnTargetUpdateTimeChanged(this, targetUpdateTime_s)
        end

        %% PlotterAxesSelectionChange
        function PlotterAxesSelectionChange(app, pltr, ~)
            %Just pass through to controller
            app.Controller.PlotterAxesSelectionChange(pltr);
        end

        %% PopulateInstrumentList
        function PopulateInstrumentList(this, cellArrayOfInstrumentNameStrings)
        end

        %% RefocusWindow
        function RefocusWindow(app)
            %yeah, this doesnt do much if there is no window
        end

        %% SavePlotPressed
        function SavePlotPressed(app, ~, eventData)
            app.Controller.SavePlot(eventData);
        end

        %% ShowGreenStatus
        function ShowGreenStatus(this, message)
        end

        %% ShowProgressBar
        function ShowProgressBar(app, message)
            arguments
                app
                message {mustBeTextScalar}
            end

           disp(string(message));
        end

        %% ShowRedStatus
        function ShowRedStatus(this, message)
        end

        %% ShowYellowStatus
        function ShowYellowStatus(this, message)
        end

        %% UnlockInput
        function UnlockInput(this)
            CoakView.Logging.Logger.Log("Debug", "Input unlocked");
        end     

        %% UpdateProgressBar
        function UpdateProgressBar(this, fraction, message)
            arguments
                this;
                fraction (1,1) {mustBeBetween(fraction, 0,1)};
                message {mustBeTextScalar}
            end
            
           disp(string(message) + " - " + num2str(fraction*100) + "%");
        end        

    end

    methods (Access = private)

        %% CreateNewPlotter
        function pltr = CreateNewPlotter(this, parent, size)
            %Create plotter component
            pltr = CoakView.Components.PlotterPanel(parent);

            %Apply settings loaded from json file
            plotterSettings = this.Controller.PlotterSettings;
            plotterSettings.Size = size;
            pltr.ApplySettings(plotterSettings);

            %Subscribe to events
            addlistener(pltr, 'AxesSelectionChange', @(src,evnt)this.PlotterAxesSelectionChange(src,evnt));
            addlistener(pltr, 'SavePlot', @(src,evnt)this.SavePlotPressed(src,evnt));
        end

        %% CreateNewSimplePlotter
        function pltr = CreateNewSimplePlotter(app, parent, size)
            %Create plotter component
            pltr = CoakView.Components.SimplePlotterPanel(parent);

            %Apply settings loaded from json file
            plotterSettings = app.Controller.PlotterSettings;
            plotterSettings.Size = size;
            pltr.ApplySettings(plotterSettings);

            %Subscribe to events
            addlistener(pltr, 'SavePlot', @(src,evnt)app.SavePlotPressed(src,evnt));
        end

    end
end

