classdef PluginLoading
    %PluginLoading - Static functions for finding and creating instruments by name, and for presets.
    %The InstrumentController finds the instrument classes
    %(`LoadClassNamesInNamespace`), creates them by name
    %(`InstantiateClass`) and gives each a unique name
    %(`GetIncrementedInstrName`). The Sequence Editor lists the commands an
    %instrument or Instrument Control offers (`GetInstrumentMethods`,
    %`GetInstrumentControlMethods`). Presets - JSON files of instruments,
    %their settings and plots - are saved with `SavePresetToJson` and
    %loaded with `ApplyPresetFromJson`; see [Presets and config](../presets-and-config.md).

    %% Methods (Static, Public)
    methods (Static, Access = public)

        function ApplyPresetFromJson(controller, gui, jsonFilePath)
            %Apply a preset JSON file: add its instruments with their settings and Instrument Controls, and its plots.
            %Instruments are added in order, with their Name set first so
            %their Instrument Controls are named after it. Text settings
            %are converted to the property's enumeration where one matches
            %(e.g. Connection_Type to `Palladium.Enums.ConnectionType`).
            %Plotting tabs and windows are only added if there is a GUI.
            %Problems with one entry are logged as warnings and that entry
            %is skipped
            %
            %Inputs:
            %   controller   - the Palladium.Core.Controller
            %   gui          - the main GUI, or [] for none
            %   jsonFilePath - the preset file

            if ~isfile(jsonFilePath)
                error('ApplyPresetFromJsonError:FileNotFound', 'Preset file not found: %s', jsonFilePath);
            end

            txt = fileread(jsonFilePath, Encoding = "UTF-8");
            data = jsondecode(txt);

            % Top-level preset fields
            if isfield(data, 'UpdateTime')
                try
                    controller.TimingLoopController.SetUpdateTime(data.UpdateTime);
                catch
                    Palladium.Logging.Logger.Log("Warning", "Preset: failed to set the update time from " + string(jsonFilePath));
                end
            end

            % Instruments
            if isfield(data, 'Instruments')
                for ii = 1 : numel(data.Instruments)
                    %Pull out the next instrument in the loop. Might be a
                    %cell array of structs or just an array, so check that
                    %to be safe with the indexing
                    if iscell(data.Instruments)
                        instSpec = data.Instruments{ii};
                    else
                        instSpec = data.Instruments(ii);
                    end

                    %Validate
                    if ~isfield(instSpec, 'Type')
                        Palladium.Logging.Logger.Log("Warning", "Preset: instrument entry " + ii + " has no Type - skipping it"); continue;
                    end

                    %Grab the Name first, as we need to set that before any
                    %Controls get added or they will not auto-rename
                    if isfield(instSpec, 'Properties') && ~isempty(instSpec.Properties) && isfield(instSpec.Properties, 'Name')
                        %Add the Instrument with a custom Name
                        instr = controller.InstrumentController.AddInstrument(string(instSpec.Type), "Name", instSpec.Properties.Name);
                    else
                        %Add the Instrument
                        instr = controller.InstrumentController.AddInstrument(string(instSpec.Type));
                    end

                    %Warn and break if that has come back empty
                    if isempty(instr)
                        Palladium.Logging.Logger.Log("Warning", "Preset: could not add instrument " + string(instSpec.Type));
                        continue;
                    end

                    %Set Instrument Properties
                    if isfield(instSpec, 'Properties') && ~isempty(instSpec.Properties)
                        props = instSpec.Properties;
                        names = fieldnames(props);

                        %Loop over each property
                        for k = 1:numel(names)
                            propName = names{k};
                            propVal = props.(propName);

                            %A setting the driver no longer has (e.g. the
                            %Lakeshore 370's HeaterResistance, now read from
                            %the instrument) is skipped, not an error that
                            %stops the whole preset loading
                            if ~isprop(instr, propName)
                                Palladium.Logging.Logger.Log("Warning", "Preset: " + string(instr.Name) + " has no setting " + string(propName) + " - skipping it");
                                continue;
                            end

                            % Conversion rules
                            if ischar(propVal) || isstring(propVal)
                                s = char(propVal);
                                % Try enum lookup: Palladium.Enums.<PropName>.<Value>
                                try
                                    % Example: Connection_Type => ConnectionType enum class
                                    enumClass = propName;
                                    enumClass = strrep(enumClass, '_', ''); % crude normalization
                                    fullEnum = ['Palladium.Enums.' enumClass];
                                    % If property expects a MeasType call
                                    if strcmpi(propName, 'MeasMode') && ismethod(instr, 'MeasType')
                                        instr.(propName) = instr.MeasType(s);
                                    else
                                        % try dynamic enum conversion if class exists
                                        if exist(fullEnum, 'class') == 8
                                            instr.(propName) = eval([fullEnum '.' s]);
                                        else
                                            instr.(propName) = propVal;
                                        end
                                    end
                                catch
                                    instr.(propName) = propVal;
                                end
                            else
                                % numeric, logical, struct, etc.
                                instr.(propName) = propVal;
                            end
                        end
                    end

                    % Instrument Controls - optional nested Controls array inside instrument spec
                    if isfield(instSpec, 'Controls') && ~isempty(instSpec.Controls)
                        for ci = 1:numel(instSpec.Controls)
                            ctrlSpec = instSpec.Controls(ci);
                            try
                                % If the control entry is a simple string, add by name
                                if ischar(ctrlSpec) || isstring(ctrlSpec)
                                    controller.InstrumentController.AddInstrumentControlFromName(instr, char(ctrlSpec), gui);
                                elseif isstruct(ctrlSpec)
                                    % Expect field 'Name' (control option name) and optional ControlName/TabName
                                    if ~isfield(ctrlSpec, 'Name')
                                        Palladium.Logging.Logger.Log("Warning", "Preset: Instrument Control entry " + ci + " for instrument " + string(instSpec.Type) + " has no Name - skipping it");
                                        continue;
                                    end
                                    settings = struct();
                                    if isfield(ctrlSpec, 'ControlName'), settings.ControlName = ctrlSpec.ControlName; end
                                    if isfield(ctrlSpec, 'TabName'), settings.TabName = ctrlSpec.TabName; end
                                    
                                    % Call AddInstrumentControl with name and settings
                                    % convert settings to name-value call
                                    if isfield(settings, 'ControlName') && isfield(settings, 'TabName')
                                        controller.InstrumentController.AddInstrumentControlFromName(instr, string(ctrlSpec.Name), gui, ControlName = settings.ControlName, TabName = settings.TabName);
                                    elseif isfield(settings, 'ControlName')
                                        controller.InstrumentController.AddInstrumentControlFromName(instr, string(ctrlSpec.Name), gui, ControlName = settings.ControlName);
                                    elseif isfield(settings, 'TabName')
                                        controller.InstrumentController.AddInstrumentControlFromName(instr, string(ctrlSpec.Name), gui, TabName = settings.TabName);
                                    else
                                        controller.InstrumentController.AddInstrumentControlFromName(instr, string(ctrlSpec.Name), gui);
                                    end
                                else
                                    Palladium.Logging.Logger.Log("Warning", "Preset: unknown Instrument Control entry for instrument " + string(instSpec.Type) + " - skipping it");
                                end
                            catch ex
                                Palladium.Logging.Logger.Log("Warning", "Preset: could not add an Instrument Control to instrument " + string(instSpec.Type) + ": " + string(ex.message));
                            end
                        end
                    end
                end
            end

            % Plotting Tabs
            if isfield(data, 'PlottingTabs') && ~isempty(gui)
                for ii = 1:numel(data.PlottingTabs)
                    %Retrieve the next object to apply. May be a cell or
                    %simple array, index accordingly to be safe
                    if iscell(data.PlottingTabs)
                        tabSpec = data.PlottingTabs{ii};
                    else
                        tabSpec = data.PlottingTabs(ii);
                    end

                    %Retrieve rows and columns numbers
                    r = getfieldwithdefault(tabSpec, 'Row', 1);
                    c = getfieldwithdefault(tabSpec, 'Col', 1);

                    %Add the tab
                    listOfPlotters = gui.AddNewPlottingTab(r, c);

                    %Apply plot settings
                    applyPlotSettings(listOfPlotters, tabSpec, r, c);
                end
            end

            % Plotting Windows (optional)
            if isfield(data, 'PlottingWindows') && ~isempty(gui)
                for ii = 1:numel(data.PlottingWindows)
                    %Retrieve the next object to apply. May be a cell or
                    %simple array, index accordingly to be safe
                    if iscell(data.PlottingWindows)
                        winSpec = data.PlottingWindows{ii};
                    else
                        winSpec = data.PlottingWindows(ii);
                    end

                    %Retrieve number of rows and columns info
                    r = getfieldwithdefault(winSpec, 'Row', 1);
                    c = getfieldwithdefault(winSpec, 'Col', 1);

                    %Add the window
                    listOfPlotters = gui.AddNewPlottingWindow(r, c);

                    %Apply plot settings
                    applyPlotSettings(listOfPlotters, winSpec, r, c);
                end
            end

            %Internal helper functions
            function v = getfieldwithdefault(s, name, def)
                if isfield(s, name)
                    v = s.(name);
                else
                    v = def;
                end
            end

            function applyPlotSettings(listOfPlotters, spec, r, c)
                %Set default x axis if given
                if isfield(spec, 'DefaultXAxis')
                    %We have multiple plotterpanels, in a rowxcol grid,
                    %to set settings for
                    for i = 1 : c
                        for j = 1 : r
                            idx = (j-1)*c + i;
                            xAx = string(spec.DefaultXAxis);%If it's a single element, it'll be a char.. and then length() goes wrong, counts the chars instead of reporting one element

                            %Allow only defining one or a subset of the
                            %axes, don't force all 4 in a 2x2 for
                            %example, but make sure not to get an
                            %IndexOutOfRange
                            if idx <= length(xAx) && strlength(xAx(idx)) > 0
                                listOfPlotters(idx).SetDefaultXAxis(xAx(idx));
                            end
                        end
                    end
                end

                %Set default y axes
                if isfield(spec, 'DefaultYAxes')
                    %Retrieve value for convenience
                    yaxes = spec.DefaultYAxes;
                    %We have multiple plotterpanels, in a rowxcol grid,
                    %to set settings for
                    for i = 1 : c
                        for j = 1 : r
                            idx = (j-1)*c + i;
                            if idx <= length(yaxes)
                                %Fetch option to apply (note y axes are
                                %nested one further than x, it's an array
                                %of arrays as we have 4 y axes on a Plotter
                                if iscell(yaxes)
                                    if ischar(yaxes{idx}) || isstring(yaxes{idx})
                                        ya = string(yaxes{idx});
                                    elseif iscell(yaxes{idx})
                                        % Robust conversion to a string array
                                        ya = strings(size(yaxes{idx}));
                                        for kkk = 1:numel(yaxes{idx})
                                            v = yaxes{idx}{kkk};
                                            % unwrap single-level nested cell
                                            if iscell(v) && isscalar(v)
                                                v = v{1};
                                            end

                                            if isempty(v)
                                                ya(kkk) = "" ;                     % or string(missing) if you prefer missing
                                            elseif ischar(v) || isstring(v)
                                                ya(kkk) = string(v);
                                            elseif isnumeric(v) || islogical(v)
                                                ya(kkk) = string(v);               % numeric -> textual representation
                                            else
                                                % fallback for unexpected types
                                                try
                                                    ya(kkk) = string(v);
                                                catch
                                                    ya(kkk) = string(missing);
                                                end
                                            end
                                        end
                                    else
                                        ya = [];
                                    end
                                else
                                    ya = string(yaxes(idx));
                                end

                                %Prepopulate 4 options as empty, then decode as many as are given in the
                                yaxStrings = {[], [], [], []};
                                for kk = 1:numel(ya)
                                    %Assign into pre-emptied array
                                    % Skip missing or empty string elements
                                    if ismissing(ya(kk)) || strlength(ya(kk)) == 0
                                        continue;
                                    end

                                    %Make sure we don't have more than 4 axes
                                    if kk > 4
                                        Palladium.Logging.Logger.Log("Warning", "Preset: a plot has more than 4 y axes - only the first 4 are used");
                                        break;
                                    end

                                    % Assign string
                                    yaxStrings{kk} = string(ya(kk));
                                end

                                %Set the default y axes now we've decoded the info
                                listOfPlotters(idx).SetDefaultYAxes(yaxStrings{1},yaxStrings{2},yaxStrings{3},yaxStrings{4});
                            end
                        end
                    end
                end
            end

        end



        function exists = CheckClassExistsInNamespace(namespaceName, className)
            %Check whether a namespace has a class of the given name.
            %Errors if the namespace isn't on the path, or has no classes
            %
            %Inputs:
            %   namespaceName - the namespace, e.g. "Palladium.Instruments"
            %   className     - the class name without the namespace, e.g. "Keithley2000"
            %
            %Outputs:
            %   exists - true if the class is there

            arguments
                namespaceName   {mustBeTextScalar};
                className       {mustBeTextScalar};
            end

            %First, check that this is actually a real namespace that
            %exists on the path
            assert(Palladium.Utilities.PluginLoading.CheckNamespaceExists(namespaceName), "CheckClassExistsInNameSpace:NoSuchNamespace", "%s", "Namespace " + string(namespaceName) + " not found. Is it added to the Path?");

            %Get the metadata of the given namespace from its name
            metaData = matlab.metadata.Namespace.fromName(namespaceName);

            %Check for an empty namespace (valid, but containing no classes)
            if isempty(metaData.ClassList)
                error("CheckClassExistsInNameSpace:EmptyNamespace", "%s", "No classes found in Namespace " + string(namespaceName));
            end

            %Pull out the class names, will be e.g.
            %"Palladium.Instruments.TestInstrument", as an array
            classesInNamespace = string({metaData.ClassList.Name});

            %Check if the className is found anywhere in that list, return
            %result
            exists = any(strcmp(classesInNamespace, namespaceName + "." + className));
        end

        function existsAlready = CheckForExistingInstrName(newName, itemsData)
            %Check whether any of a list of instruments already has a given Name.
            %
            %Inputs:
            %   newName   - the name
            %   itemsData - the instruments (cell array)
            %
            %Outputs:
            %   existsAlready - true if one has that Name

            %Check if the instruments array is empty, that's an easy false
            if(isempty(itemsData))
                existsAlready = false;
                return;
            end

            %Get names of existing instruments
            for n = 1 : length(itemsData)
                existingNames(n) = string(itemsData{n}.Name); %#ok<AGROW>
            end

            %Check for duplicate
            if(any(strcmp(existingNames, newName)))
                existsAlready = true;
                return;
            end

            %Assign output - we got to the end without returning
            existsAlready = false;
        end

        function exists = CheckNamespaceExists(namespaceName)
            %Check whether a namespace exists on the path.
            %
            %Inputs:
            %   namespaceName - the namespace, e.g. "Palladium.Instruments"
            %
            %Outputs:
            %   exists - true if it exists

            arguments
                namespaceName {mustBeTextScalar};
            end

            %Check if the namespace exists on the path https://uk.mathworks.com/matlabcentral/answers/1889757-is-there-exist-functionality-for-packages-namespaces
            exists = ~isempty(meta.package.fromName(namespaceName));
        end

        function NewName = GetIncrementedInstrName(instr, itemsData)
            %A unique name for a new instrument: its Name with the first free number added, e.g. K2000_1, K2000_2.
            %The user can change it afterwards
            %
            %Inputs:
            %   instr     - the new instrument
            %   itemsData - the instruments already added (cell array)
            %
            %Outputs:
            %   NewName - the name to give it

            %Preallocate name
            NewName = instr.Name;

            %Check if the instruments array is empty, just append 1 if so
            if(isempty(itemsData))
                NewName = NewName + "_1";
                return;
            end

            %Get names of existing instruments
            for n = 1 : length(itemsData)
                existingNames(n) = string(itemsData{n}.Name); %#ok<AGROW>
            end

            %Initialise some variables
            i = 1;
            tmpName = NewName + "_" + num2str(i);

            %Loop while we have duplicates, incrementing the number each
            %time, until name+i is not an existing name
            while(any(strcmp(existingNames, tmpName)))
                i = i + 1;
                tmpName = NewName + "_" + num2str(i);
            end

            %Assign output
            NewName = tmpName;
        end

        function meths = GetInstrumentControlMethods(instrRef, controlName)
            %The commands an Instrument Control offers to sequences, e.g. "SweepRun" - for the Sequence Editor's menus.
            %Its public methods, as signatures without `this` and outputs,
            %leaving out MATLAB's handle methods and Palladium's internal
            %ones (event handlers and the like)
            %
            %Inputs:
            %   instrRef    - the instrument the control belongs to
            %   controlName - the control's name
            %
            %Outputs:
            %   meths - the method signatures (string array)

            controlRef = instrRef.GetRegisteredControlObjectsFromName(controlName);


            builtInNamesToExclude = ["addlistener", "delete", "eq", "findobj", "findprop", "ge", "gt", "isvalid",...
                "le", "listener", "lt", "ne", "notify"];

            instrNamesToExclude = ["CreateInstrumentControlGUI", "DataRowCollected", "GetCommandCompleteFn", "GetName", "MeasurementsInitialised", "MeasurementsPaused", "MeasurementsResumed", "MeasurementsStarted", "MeasurementsStopped",...
                "OnParametersChanged", "OnSweepAbort", "OnSweepComplete", "OnSweepRun", "PlotterAxesSelectionChange",  "RegisterEventListener", "RegisterCommandCompleteQuery",...
                "RemoveControl", "SweepDataChanged", "UnsubscribeFromEvents"];

            meths = Palladium.Utilities.PluginLoading.GetClassMethodsClean(controlRef, builtInNamesToExclude, instrNamesToExclude);
        end

        function meths = GetInstrumentMethods(instrRef)
            %The commands an instrument offers to sequences, e.g. "SetSourceLevel(level, enable)" - for the Sequence Editor's menus.
            %Its public methods, as signatures without `this` and outputs,
            %leaving out MATLAB's handle methods and the Instrument base
            %class's internal ones (connecting, headers, Instrument Controls
            %and the like)
            %
            %Inputs:
            %   instrRef - the instrument
            %
            %Outputs:
            %   meths - the method signatures (string array)

            builtInNamesToExclude = ["addlistener", "delete", "eq", "findobj", "findprop", "ge", "gt", "isvalid",...
                "le", "listener", "lt", "ne", "notify"];

            instrNamesToExclude = ["CollectMetaData", "Connect", "ConnectionFailedMessage", "DefineSupportedConnectionTypes", "Disconnect", "GetAvailableControlOptions", "GetCommandCompleteFn", "GetControlOption", "GetHeaders",...
                "GetRegisteredControlNames", "GetRegisteredControlObjects", "GetRegisteredControlObjectsFromName", "GetSupportedConnectionTypes",...
                "GrabMetadataString", "RegisterControlObject", "RegisterCommandCompleteQuery", "RemoveControlObject", "ShowProperty"];

            meths = Palladium.Utilities.PluginLoading.GetClassMethodsClean(instrRef, builtInNamesToExclude, instrNamesToExclude);
        end

        function classInstance = InstantiateClass(namespace, className)
            %Create an object of a class from its name, with no constructor arguments.
            %
            %Inputs:
            %   namespace - the namespace, e.g. "Palladium.Instruments", or empty for none
            %   className - the class name, e.g. "Keithley2000"
            %
            %Outputs:
            %   classInstance - the new object

            if(isempty(namespace))
                classPath = className;
            else
                classPath = namespace + "." + className;
            end

            fnHandle = str2func(classPath);
            classInstance = fnHandle();
        end

        function classInstance = InstantiateEnum(namespace, className, enumValueString)
            %Get an enumeration member from the enumeration's name and the member's name.
            %
            %Inputs:
            %   namespace       - the namespace, e.g. "Palladium.Enums", or empty for none
            %   className       - the enumeration, e.g. "ConnectionType"
            %   enumValueString - the member, e.g. "GPIB"
            %
            %Outputs:
            %   classInstance - the member

            if(isempty(namespace))
                classPath = className;
            else
                classPath = namespace + "." + className;
            end

            fnHandle = str2func(classPath);
            classInstance = fnHandle(enumValueString);
        end

        function classNames = LoadClassNamesInNamespace(namespaceString)
            %The names of all the classes in a namespace, without the namespace.
            %For example "Palladium.Instruments" gives ["Keithley2000",
            %"Keithley2410", ...]. Warns and gives [] if the namespace has no
            %classes (e.g. it isn't on the path)
            %
            %Inputs:
            %   namespaceString - the namespace
            %
            %Outputs:
            %   classNames - the class names (string array)

            arguments
                namespaceString string {mustBeTextScalar};
            end

            classData = namespaceClasses(namespaceString);

            if isempty(classData)
                Palladium.Logging.Logger.Log("Warning", "Namespace " + namespaceString + " is empty, no classes found. Not on the path?");
                classNames = [];
                return;
            end

            for i = 1 : length(classData)
                str = string(classData(i).Name);
                classNames(i) = erase(str, namespaceString + ".");
            end
        end

        function SavePresetToJson(controller, instrController, gui, jsonFilePath)
            %Save the instruments added, their settings and Instrument Controls, and the plots, as a preset JSON file.
            %The file can be loaded with ApplyPresetFromJson. Each
            %instrument's GUI-editable (public SetObservable) settings are
            %saved, and the Instrument Controls added by hand - not those
            %its driver adds by default. Plotting tabs and windows, with
            %their default axes, are saved if there is a GUI
            %
            %Inputs:
            %   controller      - the Palladium.Core.Controller, for the update time
            %   instrController - its InstrumentController, for the instruments
            %   gui             - the main GUI, or [] for none
            %   jsonFilePath    - the file to write (".json" is added if missing)

            % Build top-level preset
            preset = struct();

            %Clean up filepath
            jsonFilePath = Palladium.Utilities.PathUtils.EnsureExtension(jsonFilePath, ".json");

            %% Programme-wide general settings
            preset.UpdateTime = controller.TimingLoopController.TargetUpdateTime;

            %% Instruments
            instList = instrController.GetInstruments();    % expected array or cell of instrument objects
          
            if isempty(instList)
                preset.Instruments = [];
            else
                % normalize to cell array for safe iteration
                if ~iscell(instList), instList = num2cell(instList); end
                nI = numel(instList);
                instOut = cell(1,nI);
                for ii = 1:nI
                    instr = instList{ii};
                    instSpec = struct();
                    if isprop(instr, 'Type')
                        type = string(instr.Type);
                    elseif ismethod(instr, 'GetType')
                        type = string(instr.GetType());
                    else
                        type = string(class(instr)); % fallback
                    end

                    %Remove namespace part of string
                    instSpec.Type = erase(type, "Palladium.Instruments.");

                    % Properties: enumerate public properties if possible
                    props = struct();
                    meta = metaclass(instr);
                    for p = 1:numel(meta.PropertyList)
                        prop = meta.PropertyList(p);
                        % Only include public, non-dependent properties that are set-observable
                        if isequal(prop.GetAccess, 'public') && ~prop.Dependent && prop.SetObservable
                            pname = prop.Name;
                            try
                                val = instr.(pname);
                                props.(pname) = val;
                            catch
                                % skip unreadable properties
                            end
                        end
                    end
                    if ~isempty(fieldnames(props))
                        instSpec.Properties = props;
                    end

                    % Controls: attempt to obtain registered control names/objects
                    try
                        if ismethod(instr, "GetRegisteredControlNames")
                            ctrlNames = instr.GetRegisteredControlNames();
                        elseif ismethod(instr, "GetRegisteredControlObjectsFromName")
                            % fall back to nothing
                            ctrlNames = [];
                        else
                            ctrlNames = [];
                        end
                    catch
                        ctrlNames = [];
                    end

                    if ~isempty(ctrlNames)
                        % represent controls as array of structs with Name only (other properties optional)
                        ctrls = [];
                        for ci = 1:numel(ctrlNames)
                            ctrlName = string(ctrlNames{ci});

                            %Only retrieve controls that are not auto-added
                            instrCtrlStruct = instr.GetControlOption(ctrlName);
                            if ~ instrCtrlStruct.EnabledByDefault
                                if isempty(ctrls)
                                    ctrls = {struct('Name', ctrlName)};
                                else
                                    ctrls{end + 1} = struct('Name', ctrlName); %#ok<AGROW>
                                end
                            end
                        end
                        instSpec.Controls = ctrls;
                    end

                    instOut{ii} = instSpec;
                end
                % convert cell->struct array for JSON encoding
                preset.Instruments = vertcat(instOut{:});
            end

            %% Plotting Tabs and Windows
            if ~isempty(gui)
                [tabs, wins] = gui.GetPlottingWindowsAndTabs();
                preset.PlottingTabs = [];
                preset.PlottingWindows = [];
                if ~isempty(tabs)
                    for i = 1 : length(tabs)
                        ptabData = buildPlotSpecs(tabs{i});

                        if isempty(preset.PlottingTabs)
                            preset.PlottingTabs = ptabData;
                        else
                            preset.PlottingTabs = [preset.PlottingTabs ptabData];
                        end
                    end

                end

                if ~isempty(wins)
                    for i = 1 : length(wins)
                        if isvalid(wins{i})
                            pwinData = buildPlotSpecs(wins{i});

                            if isempty(preset.PlottingWindows)
                                preset.PlottingWindows = pwinData;
                            else
                                preset.PlottingWindows = [preset.PlottingWindows pwinData];
                            end
                        end
                    end

                end
            else
                preset.PlottingTabs = [];
                preset.PlottingWindows = [];
            end

            %% Write JSON
            jsonText = jsonencode(preset, PrettyPrint=true);
            fid = fopen(jsonFilePath, 'w', 'n', 'UTF-8');
            if fid == -1
                error('SavePresetToJson:FileOpen', 'Unable to open %s for writing', jsonFilePath);
            end
            fwrite(fid, jsonText, 'char');
            fclose(fid);

            % Helper to build plotting specs array
            function out = buildPlotSpecs(item)
                %item is either or a window or a tab, with PlotterPanels
                %added to it
                if isempty(item)
                    out = [];
                    return;
                end

                out = struct();

                %Grab the plotterpanels added to this object
                pp = findobj(item, "Type", 'Palladium.Components.PlotterPanel');

                %%Grab the grid layout
                g = findobj(item, "Type", 'uigridlayout');
                out.Row = length(g.RowHeight);
                out.Col = length(g.ColumnWidth);

                if isempty(pp)
                    Palladium.Logging.Logger.Log("Warning", "Saving preset: a plotting tab or window has no plots in it");
                    return;
                end

                %One entry per plotter, in the order ApplyPresetFromJson
                %applies them: along each row of the grid in turn. "" for
                %a plotter with no x axis, so later plotters keep their
                %places
                xAxes = strings(1, out.Row * out.Col);
                yAxes = repmat({strings(1, 0)}, 1, out.Row * out.Col);
                for j = 1 : length(pp)
                    pltr = pp(j);
                    idx = (pltr.Layout.Row - 1) * out.Col + pltr.Layout.Column;

                    % DefaultXAxis / DefaultYAxes extraction
                    [x, y] = pltr.GetDefaultAxes();
                    if ~isempty(x)
                        xAxes(idx) = x;
                    end
                    yAxes{idx} = y;
                end
                out.DefaultXAxis = xAxes;
                out.DefaultYAxes = yAxes;
            end
        end

    end

    %% Methods (Static, Private)
    methods (Static, Access = private)

        function meths = GetClassMethodsClean(classRef, builtInNamesToExclude, extraNamesToExclude)
            %A class's method signatures, without `this`, outputs, the constructor and the names given.
            %Shared by GetInstrumentMethods and GetInstrumentControlMethods
            %
            %Inputs:
            %   classRef              - an object of the class
            %   builtInNamesToExclude - MATLAB's methods to leave out (string array)
            %   extraNamesToExclude   - Palladium's methods to leave out (string array)
            %
            %Outputs:
            %   meths - the signatures, e.g. "SetField(field, rate)" (string array)

            methodNames = methods(classRef);
            methodSigs = methods(classRef, "-full");

            className = class(classRef);
            parts = strsplit(className, '.');
            constructorName = string(parts(end));

            meths = [];

            for i = 1 : length(methodNames)

                mn = methodNames{i};
                if ~isempty(mn)
                    if ~any(strcmp(builtInNamesToExclude, mn)) && ~any(strcmp(extraNamesToExclude, mn))
                        if ~ strcmp(mn, constructorName)
                            meths = [meths, CleanMethodSignature(string(mn), string(methodSigs{i}))]; %#ok<AGROW>  %Can't know in advance how many will pass criteria
                        end
                    end
                end
            end

            function cleanSig = CleanMethodSignature(mName, mSig)
                %The signature as a command: the name and its arguments,
                %without the output (eg this = Keithley2000()), 'this' or
                %trailing unused (~) arguments, eg ScanAbort(this, ~, ~) ->
                %ScanAbort. A ~ before a used argument stays, as it holds
                %that argument's place. With no arguments left, no brackets
                %either - a command needs none
                argStr = extractAfter(mSig, mName);
                if ~startsWith(strtrim(argStr), "(")
                    cleanSig = mName;
                    return;
                end

                args = strtrim(split(extractBetween(argStr, "(", ")"), ","));
                args = args(args ~= "" & args ~= "this");
                while ~isempty(args) && args(end) == "~"
                    args(end) = [];
                end

                if isempty(args)
                    cleanSig = mName;
                else
                    cleanSig = mName + "(" + join(args, ", ") + ")";
                end
            end
        end

    end
end
