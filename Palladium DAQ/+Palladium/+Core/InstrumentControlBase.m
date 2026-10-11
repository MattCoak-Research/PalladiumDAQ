classdef InstrumentControlBase < Palladium.Core.Entity & matlab.mixin.Heterogeneous
    %InstrumentControlBase - Abstract base class of every Instrument Control, such as a Sweep Control or heater panel.
    %An Instrument Control adds a GUI tab and logic to one instrument: a
    %Sweep Control, a Lakeshore heater panel or a magnet's control panel,
    %for example. Subclasses live in `Palladium.Instruments.Controls`, and
    %must implement `CreateInstrumentControlGUI` and `RemoveControl`.
    %
    %**Lifecycle**
    %
    %* **Offered**: an instrument driver offers the control by calling
    %  `DefineInstrumentControl` in its constructor.
    %* **Created**: when the control is added, the InstrumentController
    %  constructs it with no arguments, sets `ControlDetailsStruct`,
    %  `Controller` and `ProgrammeTargetUpdateTime`, then calls
    %  `CreateInstrumentControlGUI(controller, tab, instrRef)`. That builds
    %  the GUI in the tab, and must set `Instrument` to `instrRef`. The
    %  control is then registered with the instrument.
    %* **Measurement events**: the InstrumentController subscribes the
    %  control's `MeasurementsInitialised`, `MeasurementsStarted`,
    %  `MeasurementsPaused`, `MeasurementsResumed`, `MeasurementsStopped`
    %  and `TargetUpdateTimeChanged` handlers to the TimingLoopController's
    %  events, and `DataRowCollected` to its own. Each handler calls an
    %  `On*` hook (e.g. `OnMeasurementsStarted`, `OnMeasurementsPaused`),
    %  which subclasses override.
    %* **Each tick**: the instrument calls `Update` before its reading, and
    %  `UpdateData` with the reading straight after it. Once every
    %  instrument has been read, `DataRowCollected` gets the full data row.
    %* **Removed**: the InstrumentController unregisters the control from
    %  the instrument, calls `UnsubscribeFromEvents`, then `RemoveControl`,
    %  then deletes it.
    %
    %Use `AddGuardedListener` rather than `addlistener` for the GUI's events,
    %so errors in the callbacks reach the error handling. Controls that
    %write their own data files (e.g. sweep files) use
    %`InitialiseDataWriter`, `StartNewDataFile` and
    %`InsertEndMetadataIntoFile`.
    %
    %Heterogeneous, so an instrument can hold controls of different classes
    %in one array (e.g. a MagnetController and a SweepController_Ramp on a
    %Mercury IPS).

    %% Properties (Public)
    properties (Access = public)
        ControlDetailsStruct;               %The control's definition, from the instrument's DefineInstrumentControl: Name, ControlClassFileName, TabName, EnabledByDefault and UserData
        Controller;                         %Palladium.Core.Controller - set by InstrumentController when the control is added, used to route callback errors to the error handling
        FileNamePropertyDelimiters = "[]";  %The two characters that enclose a data column tag in a file name, e.g. "[Temperature (K)]" - see ProcessFileName
        DecimalPointReplacementCharacter = "p";   %Replaces "." in processed file names, e.g. "1.50" becomes "1p50"
        ProgrammeTargetUpdateTime;          %The measurement loop's target time between ticks (s), kept up to date by TargetUpdateTimeChanged
    end

    %% Properties (Protected)
    properties (Access = protected)
        Instrument;                 %The instrument this control is added to - subclasses set it in CreateInstrumentControlGUI
        AvailableHeaders = [];      %All data column headers, stored by MeasurementsInitialised when measurements start
        DataArray = [];             %Use to store entire array of dataRows taken during an operation - need it if we change axes on a Plotter mid-sweep
    end

    %% Properties (Private)
    properties (Access = private)
        EventListeners;             %Listeners added with RegisterEventListener, deleted by UnsubscribeFromEvents
    end

    %% Methods (Abstract, Public)
    methods (Abstract)
        %Build the control's GUI in its tab, and connect it to the instrument.
        %Called by the InstrumentController when the control is added,
        %after ControlDetailsStruct, Controller and
        %ProgrammeTargetUpdateTime are set. Implementations should set
        %`this.Instrument = instrRef`, and subscribe to the GUI's events
        %with AddGuardedListener
        %
        %Inputs:
        %   controller - the Palladium.Core.Controller, e.g. for
        %                `controller.AddNewPlotter`
        %   tab        - the GUI tab (or other container) to build the GUI in
        %   instrRef   - the instrument the control is added to
        CreateInstrumentControlGUI(this, controller, tab, instrRef);

        %Clean up when the control is removed, e.g. delete its GUI components.
        %Called by the InstrumentController after the control is
        %unregistered from the instrument and UnsubscribeFromEvents has
        %run; the control is deleted straight afterwards
        %
        %Inputs:
        %   instrRef - the instrument the control is being removed from
        RemoveControl(this, instrRef);
    end

    %% Constructor
    methods
        function this = InstrumentControlBase()
            %Create the control - subclass constructors must take no arguments.
            %The InstrumentController constructs controls by class name, then
            %sets them up through CreateInstrumentControlGUI
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function DataRowCollected(this, dataRow, headers) %#ok<INUSD>
            %Handle the full data row each tick, once every instrument has been read - override to use it.
            %Called from the InstrumentController's DataRowCollected event.
            %Use it to e.g. write sweep data that includes columns from
            %other instruments. Does nothing by default
            %
            %Inputs:
            %   dataRow - the data row of all instruments, starting with Time
            %   headers - the data column headers, matching dataRow
        end

        function name = GetName(this)
            %The control's name, from ControlDetailsStruct, e.g. "Sweep Control".
            %
            %Outputs:
            %   name - the Name given to DefineInstrumentControl

            name = this.ControlDetailsStruct.Name;
        end

        function MeasurementsInitialised(this, src, eventArgs)  %#ok<INUSD>
            %Store the data column headers when measurements are initialised, then call OnMeasurementsInitialised.
            %Listener for the TimingLoopController's MeasurementsInitialised
            %event, raised once the headers are known and before the first tick
            %
            %Inputs:
            %   src       - the TimingLoopController
            %   eventArgs - Palladium.Events.MeasurementsInitialisedEventData,
            %               holding the Headers

            headers = eventArgs.Headers;
            this.AvailableHeaders = headers;

            this.OnMeasurementsInitialised(headers);
        end

        function MeasurementsStarted(this, src, eventArgs) %#ok<INUSD>
            %Call OnMeasurementsStarted when the measurement loop starts.
            %Listener for the TimingLoopController's Started event

            this.OnMeasurementsStarted();
        end

        function MeasurementsPaused(this, src, eventArgs) %#ok<INUSD>
            %Call OnMeasurementsPaused when the measurement loop pauses.
            %Listener for the TimingLoopController's Paused event

            this.OnMeasurementsPaused();
        end

        function MeasurementsResumed(this, src, eventArgs) %#ok<INUSD>
            %Call OnMeasurementsResumed when the measurement loop resumes after a pause.
            %Listener for the TimingLoopController's Resumed event

            this.OnMeasurementsResumed();
        end

        function MeasurementsStopped(this, src, eventArgs) %#ok<INUSD>
            %Call OnMeasurementsStopped when the measurement loop stops.
            %Listener for the TimingLoopController's Stopped event

            this.OnMeasurementsStopped();
        end

        function PlotterAxesSelectionChange(this, pltr)
            %Replot DataArray on a plotter whose axes were changed while the control isn't running.
            %Hook this to a plotter's AxesSelectionChange event. While
            %running, the plotter replots itself on the next update, but
            %with no updates coming that never happens, so this replots
            %straight away. Does nothing if DataArray is empty. The subclass
            %must have a `Running` property
            %
            %Inputs:
            %   pltr - the plotter whose axes changed

            if ~this.Running
                %Have to pass whole data table back in - Plotters do not
                %store/copy these, that would be very expensive.
                %If the data table is empty, for now just do nothing -
                %might be clearer UX to clear the plot, but then again
                %might be annoying to delete the data for no obvious reason
                if ~isempty(this.DataArray)
                    pltr.PlotData(this.DataArray);
                end
            end
        end

        function PrintIdentifier(this)
            %Print the control's name and its instrument's name to the Command Window, for debugging.

            str = "Palladium Instrument Control " + this.GetName();
            disp(str);
            disp("Parent Instrument: " + this.Instrument.Name);
        end

        function RegisterEventListener(this, listnr)
            %Keep a listener, so UnsubscribeFromEvents deletes it when the control is removed.
            %Register any listener the control adds to objects that outlive
            %it, such as the instrument or a plotter
            %
            %Inputs:
            %   listnr - the listener handle, e.g. from AddGuardedListener

            if isempty(this.EventListeners)
                this.EventListeners = listnr;
            else
                this.EventListeners = [this.EventListeners, listnr];
            end
        end

        function TargetUpdateTimeChanged(this, ~, evnt)
            %Store the measurement loop's new target update time in ProgrammeTargetUpdateTime.
            %Listener for the TimingLoopController's TargetUpdateTimeChanged event
            %
            %Inputs:
            %   evnt - Palladium.Events.ValueChangedEventData, holding the
            %          new time (s) as Value

            this.ProgrammeTargetUpdateTime = evnt.Value;%In seconds
        end

        function UnsubscribeFromEvents(this)
            %Delete all the listeners kept by RegisterEventListener.
            %Called by the InstrumentController when the control is removed,
            %before RemoveControl

            if isempty(this.EventListeners)
                return;
            end
            try
                for i = length(this.EventListeners) : -1 : 1
                    delete(this.EventListeners(i));
                    this.EventListeners(i) = [];
                end
            catch err
                error("UnsubscribeFromEventsError:UnsubscribeFailed", "%s", "Error unsubscribing Instrument Control from event listeners: " + string(err.message));
            end
        end

        function Update(this) %#ok<MANU>
            %Do the control's work for this tick, before the instrument's reading - override to use it.
            %Called by the instrument's UpdateAndMeasure, just before
            %Measure. Does nothing by default
        end

        function UpdateData(this, dataRow, headers) %#ok<INUSD>
            %Handle the instrument's new reading, straight after it is taken - override to use it.
            %Called by the instrument's UpdateAndMeasure, just after
            %Measure. Does nothing by default
            %
            %Inputs:
            %   dataRow - this instrument's reading, from Measure
            %   headers - the data column headers of all instruments
        end
    end

    %% Methods (Protected)
    methods (Access = protected)

        function ltr = AddGuardedListener(this, src, eventName, callback)
            %Add an event listener whose errors go to the error handling - use instead of addlistener.
            %With a raw addlistener, MATLAB turns errors thrown in the
            %callback into an orange warning, even while the measurement
            %loop is running (see ErrorGuard). Errors are reported to
            %Controller, named after the control and event
            %
            %Inputs:
            %   src       - the object that raises the event
            %   eventName - name of the event
            %   callback  - function handle to call when it is raised
            %
            %Outputs:
            %   ltr - the listener handle, as from addlistener, to pass to
            %         RegisterEventListener if src outlives the control

            ltr = Palladium.Core.ErrorGuard.AddListener(src, eventName, callback, Controller = this.Controller, Context = "Error in " + this.GetName() + " (" + string(eventName) + ")");
        end

        function stringLine = CreateDataRowHeaderString(this)
            %Make a data file metadata line of every column's header and last value.
            %Uses the instrument's LastFullDataRow and FullHeadersRow. For
            %logging conditions such as the temperature at the start or end
            %of a sweep, in a file the control writes itself. Warns and
            %returns "" if there is no data row yet, e.g. before the first tick
            %
            %Outputs:
            %   stringLine - the metadata line, or ""

            dataRow = this.Instrument.LastFullDataRow;
            hdrsRow = this.Instrument.FullHeadersRow;

            %Error checking - return an empty line (so callers can still
            %write the rest of the file) if there is no data row yet, e.g.
            %a sweep started before the first measurement tick
            stringLine = "";
            if isempty(dataRow)
                warning("CreateDataRowHeaderStringWarning:EmptyDataRow", "%s", "Data row empty in " + this.Instrument.FullName + ", cannot log to file");
                return;
            end
            if isempty(hdrsRow)
                warning("CreateDataRowHeaderStringWarning:EmptyHeadersRow", "%s", "Headers row empty in "  + this.Instrument.FullName + ", cannot log to file");
                return;
            end

            stringLine = Palladium.DataWriting.DataWriter.BuildMetadataLineStringFromHeaderValuePair("", hdrsRow, dataRow);
        end

        function stringVal = GetParameterValueFromLastMeasurementRow(this, parameterName, Settings)
            %Get the last value of a data column as text, e.g. the temperature for a sweep file name.
            %Reads the instrument's LastFullDataRow, so at least one tick
            %must have run. Warns and returns "!!VAL-MISSING!!" if there is
            %no data yet, or no column of that name
            %
            %Inputs:
            %   parameterName - the column's header, e.g. "Temperature (K)"
            %   Format        - num2str format of the value. Default "%03.2f"
            %
            %Outputs:
            %   stringVal - the value, as text

            arguments
                this;
                parameterName {mustBeTextScalar};
                Settings.Format {mustBeTextScalar} = "%03.2f";
            end

            %Pull data and headers from Instrument. Note at least one
            %Update must have run prior to this, or it'll be unpopulated
            dataRow = this.Instrument.LastFullDataRow;
            hdrsRow = this.Instrument.FullHeadersRow;

            %Initialise to empty
            stringVal = "!!VAL-MISSING!!";

            %Error checking
            if isempty(dataRow)
                warning("GetParameterValueFromLastMeasurementRowWarning:EmptyDataRow", "%s", "Data row empty in " + this.Instrument.FullName + ", cannot GetParameterValueFromLastMeasurementRow");
                return;
            end
            if isempty(hdrsRow)
                warning("GetParameterValueFromLastMeasurementRowWarning:EmptyDataRow", "%s", "Data row empty in "  + this.Instrument.FullName + ", cannot GetParameterValueFromLastMeasurementRow");
                return;
            end

            %Check the provided Parameter Name is indeed one of the headers
            if ~any(contains(hdrsRow, parameterName))
                warning("GetParameterValueFromLastMeasurementRowWarning:ParameterNotFound", "%s", "Could not find parameter " + parameterName + " in the measurement headers file (InstrumentControlBase.GetParameterValueFromLastMeasurementRow).");
                return;
            end

            %Extract data
            idx = ismember(hdrsRow, parameterName);
            dat = dataRow(idx);
            stringVal = num2str(dat, Settings.Format);
        end

        function dataWriter = InitialiseDataWriter(this, fileNameSuffix, Settings)
            %Create the DataWriter for the control's own data file, e.g. a sweep file.
            %The file is named after the main data file with fileNameSuffix
            %added, and processed by ProcessFileName (so data column tags
            %are filled in). It always uses 'Increment File No.' mode, so
            %no file is overwritten. The instrument's FileWriteDetails are
            %not changed. Then call StartNewDataFile
            %
            %Inputs:
            %   fileNameSuffix - text added to the main data file's name,
            %                    e.g. " - Sweep [Temperature (K)]". Errors if
            %                    empty and WriteToFile is true, as the file
            %                    would take the main data file's name
            %   WriteToFile    - false if the file won't be saved, in which
            %                    case an empty suffix is allowed. Default true
            %
            %Outputs:
            %   dataWriter - a Palladium.DataWriting.DataWriter for the file

            arguments
                this;
                fileNameSuffix;
                Settings.WriteToFile (1,1) logical = true;
            end

            %An empty suffix would give the sweep file the same name as the
            %main data file, which is being written to at the same time -
            %the two would overwrite each other's data or fight over
            %permission to write to it
            if Settings.WriteToFile
                %Empty, blank, [] and empty string arrays all count as no name
                hasFileName = ~isempty(fileNameSuffix) && all(strlength(strtrim(string(fileNameSuffix))) > 0);
                assert(hasFileName, "InitialiseDataWriterError:EmptyFileNameSuffix", ...
                    "The sweep file name is empty, so it would be saved with the same name as the main data file. Enter a sweep file name, or switch off saving the sweep file.");
            end

            fileWriteDetails = this.Instrument.FileWriteDetails;
            fileWriteDetails.FileName = string(fileWriteDetails.FileName) + fileNameSuffix;
            fileWriteDetails.WriteMode = 'Increment File No.';
            fileWriteDetails.SaveFile = true;

            %Process the file name of e.g. a sweep. Make it a valid filename and do operations like: Grab a parameter - ie Temperature, Magnetic Field, to use to
            %e.g. automatically name a Sweep File when [Temperature (K)] - one of the data file headers - is
            %given as part of it's file name. Replaces . characeters with a
            %chosen replacement too
            fileWriteDetails.FileName = this.ProcessFileName(fileWriteDetails.FileName);

            dataWriter = Palladium.DataWriting.DataWriter(fileWriteDetails);
        end

        function InsertEndMetadataIntoFile(this, dataWriter)
            %Add the data row at the end of a sweep or scan to its data file's metadata.
            %Inserts a description line and the CreateDataRowHeaderString line
            %into the file's header
            %
            %Inputs:
            %   dataWriter - the file's DataWriter, from InitialiseDataWriter

            metadataDescLine = this.Instrument.FullName + " Scan - Measurement data at Scan End:";

            %Write the data row of all instruments/diagnostics at the end
            %of the sweep, for things like temperature, time
            dataRowMetadataLine = this.CreateDataRowHeaderString();

            dataWriter.InsertMetadataLines([metadataDescLine, dataRowMetadataLine]);
        end

        function InsertSmartTagRequest(~, src, evt, controller)
            %Let the user pick a data column to add to a file name as a tag, in a small dialogue.
            %Hook to a GUI's InsertSmartTag event. Shows a modal window to
            %choose a data column and number format; on OK, appends a tag
            %such as " [Sample Temperature (K),%6.2f]" to the name and sends
            %it back with `src.SetNewSweepName`. ProcessFileName later
            %replaces the tag with the column's value
            %
            %Inputs:
            %   src        - the GUI component that raised the event, which
            %                must have a SetNewSweepName method
            %   evt        - event data whose Value is the current file name
            %   controller - the Palladium.Core.Controller, for the headers
            %                and window icon

            controlGUIToSendDataBackTo = src;
            originalStr = evt.Value;
            newStr = originalStr;

            %Handle case of 1 header only
            if isscalar(controller.Headers)
                headers = string(controller.Headers{1});
            else
                headers = controller.Headers;
            end

            precisionStr = "%6.2f";
            parameterName = [];
            cancel = true;

            %Open and configure a little GUI
            optionsFig = uifigure(WindowStyle="modal", Position=[300,300, 400, 170], Icon=controller.WindowSettings.PalladiumIconPath);
            gr = uigridlayout(optionsFig, [4,4], "ColumnWidth", {10, 200, 20, 100, 10}, "RowHeight", {10, 30, 30, 10, 50, 10}, "RowSpacing", 2);

            l1 = uilabel(gr, Text="Data Column", HorizontalAlignment="Center", FontSize=14, FontName="Georgia");
            l1.Layout.Row = 2;
            l1.Layout.Column = 2;
            l2 = uilabel(gr, Text="Precision", HorizontalAlignment="Center", FontSize=14, FontName="Georgia");
            l2.Layout.Row = 2;
            l2.Layout.Column = 4;
            d = uidropdown(gr, FontSize=14, FontName="Georgia", Items= headers);
            d.Layout.Row = 3;
            d.Layout.Column = 2;
            pr = uieditfield(gr, "text", Value=precisionStr, HorizontalAlignment="Center", FontSize=14, FontName="Georgia");
            pr.Layout.Row = 3;
            pr.Layout.Column = 4;

            buttonsGrid = uigridlayout(gr, [1,5], "ColumnWidth", {'1x', 90, 20, 90, '1x'}, "RowHeight", {'1x'});
            buttonsGrid.Layout.Row = 5;
            buttonsGrid.Layout.Column = [1 5];

            okb = uibutton(buttonsGrid, Text="OK", FontSize=14, FontName="Georgia", ButtonPushedFcn=@(src,event) OK(d, pr));
            okb.Layout.Column = 2;
            canb = uibutton(buttonsGrid, Text="Cancel", FontSize=14, FontName="Georgia", ButtonPushedFcn=@(src,event) Cancel());
            canb.Layout.Column = 4;

            function OK(d,pr)
                precisionStr = pr.Value;
                parameterName = d.Value;
                cancel = false;
                delete(optionsFig);
            end

            function Cancel()
                cancel = true;
                delete(optionsFig);
            end

            % Wait until OK/Cancel is pressed
            uiwait(optionsFig);

            if ~cancel
                %Append to string
                newStr = newStr + " [" + string(parameterName) + "," + string(precisionStr) + "]";

                %Send the new string back to whatever GUI called this
                controlGUIToSendDataBackTo.SetNewSweepName(newStr);
            end
        end

        function OnMeasurementsInitialised(this, headers) %#ok<INUSD>
            %Called when measurements are initialised, before the first tick - override to use it.
            %Does nothing by default
            %
            %Inputs:
            %   headers - the data column headers of all instruments
        end

        function OnMeasurementsPaused(this)
            %Called when the measurement loop pauses - override to use it.
            %Does nothing by default
        end

        function OnMeasurementsResumed(this)
            %Called when the measurement loop resumes after a pause - override to use it.
            %Does nothing by default
        end

        function OnMeasurementsStarted(this)
            %Called when the measurement loop starts - override to use it.
            %Does nothing by default
        end

        function OnMeasurementsStopped(this)
            %Called when the measurement loop stops - override to use it.
            %Does nothing by default
        end

        function fileNameOut = ProcessFileName(this, fileName, Settings)
            %Fill in the data column tags in a file name, and replace its decimal points.
            %Each tag, such as "[Temperature (K)]" or "[Temperature (K),%6.2f]",
            %is replaced with the column's last value (see
            %GetParameterValueFromLastMeasurementRow), and the delimiters
            %(FileNamePropertyDelimiters) are removed. Then every "." in the
            %name becomes DecimalPointReplacementCharacter. Errors if a tag
            %has more than one comma
            %
            %Inputs:
            %   fileName      - the file name, with any tags
            %   DefaultFormat - num2str format for tags that don't give one.
            %                   Default "%03.2f"
            %
            %Outputs:
            %   fileNameOut - the processed file name

            arguments
                this;
                fileName {mustBeTextScalar};
                Settings.DefaultFormat {mustBeTextScalar} = "%03.2f";
            end

            delims = char(this.FileNamePropertyDelimiters);
            assert(length(delims) == 2, "ProcessFileNameError:InvalidDelimiters", "Delimeters string must be of 2 characters length");

            %This little snippet pulls out all text delimited by the
            %selected delimters (by Default [ ]) and returns a string array
            %of all the contents of those. ie "Sweep File [Temperature] at
            %field [Field] T" will return ["Temperature", "Field"]
            segments = extractBetween(fileName, delims(1), delims(2));

            fileNameOut = fileName;

            %If there are no segments to replace, we can just return
            if isempty(segments)
                return;
            end

            for i = 1 : length(segments)
                %Retrieve the corresponding property to this tag, as a
                %string

                %Expect (but do not demand) something formatted like
                %"Sample Temperature(K),%6f2" - ie the property, a comma
                %delimiter, and then the num2str format spec. If
                splitSegs = strsplit(segments(i), ",");

                if isscalar(splitSegs)
                    format = Settings.DefaultFormat;
                elseif length(splitSegs) == 2
                    format = strtrim(splitSegs(2));
                else
                    error("ProcessFileNameError:IncorrectStringFormat", "%s", "Incorrect string format, epxect something like " + "Sample Temperature(K),%6f2" + " or " + "Sample Temperature(K)");
                end

                newSeg = this.GetParameterValueFromLastMeasurementRow(strtrim(splitSegs(1)), "Format", format);

                %Replace the "[Tag]" bit of the string with this segment.
                fileNameOut = replace(fileNameOut, segments(i), newSeg);
            end

            %Remove the delimiters too
            fileNameOut = replace(fileNameOut, delims(1), "");
            fileNameOut = replace(fileNameOut, delims(2), "");

            %Replace any decimal points with hyphens, as . messes up file
            %names
            fileNameOut = replace(fileNameOut, ".", this.DecimalPointReplacementCharacter);
        end

        function StartNewDataFile(this, dataWriter, headers, extraMetadataLines, writeToFile)
            %Start the control's own data file, writing its headers and start-of-sweep metadata.
            %Takes the next free file number, then (if writeToFile) writes
            %the column headers with metadata lines: a description, the
            %CreateDataRowHeaderString line, the instrument's
            %GrabMetadataString line, and extraMetadataLines
            %
            %Inputs:
            %   dataWriter         - the file's DataWriter, from InitialiseDataWriter
            %   headers            - the file's column headers
            %   extraMetadataLines - string array of further metadata lines,
            %                        e.g. the sweep settings
            %   writeToFile        - false to only work out the file name,
            %                        writing nothing

            %This will increment the number of the filename etc
            dataWriter.ValidateFilePath();

            %Write the data row of all instruments/diagnostics at the start
            %of the sweep, for things like temperature, time
            dataRowMetadataLine = this.CreateDataRowHeaderString();

            %Write the metadata string for this instrument - frequencies,
            %voltages, settings etc
            metadataDescLine = this.Instrument.FullName + " Scan - Measurement data at Scan Start:";
            metadataLine = this.Instrument.GrabMetadataString();

            %Write to file  - we can set this as false so we still generate
            %all the names etc for the Sweep via the DataWriter, but never
            %actually write anything
            if (writeToFile)
                dataWriter.WriteHeaders(headers, "MetadataLines", [metadataDescLine, dataRowMetadataLine, metadataLine, extraMetadataLines]);
            end
        end

    end
end

