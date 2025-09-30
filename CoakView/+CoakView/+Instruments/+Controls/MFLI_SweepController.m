classdef MFLI_SweepController < CoakView.Core.InstrumentControlBase
    %MFLI_SweepController - Logic controller add-on object to be added on to an
    %Instrument object, where it will handle the logic of controlling data
    %collection and independent logging of sweeps on a Zurich Instruments
    %MFLI
    
    properties

    end

    properties (Access = private)
        GUIView;
        DataWriter;
        FileNameSuffix = "_MFLI_SweepFile";
    end
    
    methods

        %% Constructor
        function this = MFLI_SweepController()
        end

        %% CreateInstrumentControlGUI
        function CreateInstrumentControlGUI(this, controller, tab, instrRef)
            %Create grid and TempControl component and position them in the
            %tab. 
            grid = uigridlayout(tab, "ColumnWidth", {'fit', '1x'}, "RowHeight", {10, '1x', 10}, 'RowSpacing', 2);

            %Create a .mlapp custom GUI control and add it to the grid
            comp = CoakView.Instruments.Controls.MFLISweepControlPanel(grid);
            this.GUIView = comp;
            comp.Layout.Row = 2;
            comp.Layout.Column = 1;
            this.GUIView.SetName(instrRef.Name + " - Sweep Control");

            %Make a specific reference in the Instrument Class
            this.Instrument = instrRef;
            this.Instrument.SweepControlPanel = this;

            %Add a SIMPLE plotter as well, to the right
            plotter = controller.AddNewSimplePlotter(grid, "Medium");
            plotter.Layout.Row = 2;
            plotter.Layout.Column = 2;   

            %Subscribe to events
            addlistener(comp, 'RunSingleSweep', @(src,evnt)this.RunSingleSweep(src,evnt));                 
        end       

         %% RemoveControl
        function RemoveControl(this, instrRef)
            %Clean up references to this in the Lakeshore Instrument Class
            %so it doesn't think we have a heater control
            instrRef.SweepControlPanel = [];

            %Delete GUI objects
            delete(this.GUIView);
            this.GUIView = [];
        end        

        %% RunSingleSweep
        function RunSingleSweep(this, src, evnt)
            this.Start();
        end

    end

    methods (Access = private)

       
      
        %% Start
        function Start(this)
            %Create or reset the data writer class
            this.DataWriter = this.InitialiseDataWriter(this.FileNameSuffix);

            %Built in functions in base class will write the data row of all instruments/diagnostics at the start
            %of the sweep, for things like temperature, time
            %Write the metadata string for this instrument - frequencies,
            %voltages, settings etc

            %Assemble some sweep metadata
            sweepMetadataDescLine = "Sweep Parameters:";
            sweepMetadataLine = this.CreateSweepMetaDataLine();

            %Get headers for the sweep data - not the same as overall
            %programme DataRow headers.
            headers = this.GetHeaders();

            %Create new file and write metadata and headers
            extraMetadataLines = [sweepMetadataDescLine, sweepMetadataLine];
            this.StartNewDataFile(this.DataWriter, headers, extraMetadataLines);
           

            %REMOVE
            this.SweepEnded();
        end

        %% SweepEnded
        function SweepEnded(this)
            this.InsertEndMetadataIntoFile(this.DataWriter);
        end

        %% CreateSweepMetaDataLine
        function stringLine = CreateSweepMetaDataLine(this)
            stringLine = "Sweep metadata Placeholder";
        end

        %% GetHeaders
        function headersString = GetHeaders(this)
            headers = ["Frequency_Hz", "R", "Theta", "X", "Y"];

            %Make a simple string of all these headers, tab seperated
            headersString = '';
            for i= 1 : length(headers)
                headersString = sprintf('%s%s\t', headersString, headers{i});
            end
        end
    end
end

