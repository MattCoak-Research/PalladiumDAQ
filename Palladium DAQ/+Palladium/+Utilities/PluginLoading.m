classdef PluginLoading
    %PluginLoading - Static class to expose helper methods for

    %% Methods (Static, Public)
    methods (Static, Access = public)

        function ApplyPresetFromJson(controller, gui, jsonFilePath)
            % Apply preset described in JSON file to palladium and gui objects.

            if ~isfile(jsonFilePath)
                error('Preset file not found: %s', jsonFilePath);
            end

            txt = fileread(jsonFilePath);
            data = jsondecode(txt);

            % Top-level preset fields
            if isfield(data, 'UpdateTime')
                try
                    controller.TimingLoopController.SetUpdateTime(data.UpdateTime);
                catch
                    warning('Failed to set UpdateTime from preset.');
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
                        warning('Instrument entry %d missing Type. Skipping.', ii); continue;
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

                    %Set Instrument Properties
                    if isfield(instSpec, 'Properties') && ~isempty(instSpec.Properties)
                        props = instSpec.Properties;
                        names = fieldnames(props);

                        %Loop over each property
                        for k = 1:numel(names)
                            propName = names{k};
                            propVal = props.(propName);

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
                                        warning('Control entry %d for instrument %s missing Name. Skipping.', ci, instSpec.Type);
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
                                    warning('Unknown control specification type for instrument %s. Skipping.', instSpec.Type);
                                end
                            catch ex
                                warning('Failed to add control for instrument %s: %s', instSpec.Type, ex.message);
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
                            if idx <= length(xAx)
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
                                        warning("More than 4 defined y axis options not supported");
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
            % CHECKCLASSEXISTSINNAMESPACE - Check if a class exists in a namespace
            %
            % Input arguments:
            % namespaceName - namespace/package name (string or char scalar)
            % className     - class name to check (string or char scalar)
            %
            % Output arguments:
            % exists        - logical true if class exists in the given
            % namespace
            arguments
                namespaceName   {mustBeTextScalar};
                className       {mustBeTextScalar};
            end

            %First, check that this is actually a real namespace that
            %exists on the path
            assert(Palladium.Utilities.PluginLoading.CheckNamespaceExists(namespaceName), "CheckClassExistsInNameSpace:NoSuchNamespace", "Namespace " + string(namespaceName) + " not found. Is it added to the Path?");

            %Get the metadata of the given namespace from its name
            metaData = matlab.metadata.Namespace.fromName(namespaceName);

            %Check for an empty namespace (valid, but containing no classes)
            if isempty(metaData.ClassList)
                error("CheckClassExistsInNameSpace:EmptyNamespace", "No classes found in Namespace " + string(namespaceName));
            end

            %Pull out the class names, will be e.g.
            %"Palladium.Instruments.TestInstrument", as an array
            classesInNamespace = string({metaData.ClassList.Name});

            %Check if the className is found anywhere in that list, return
            %result
            exists = any(strcmp(classesInNamespace, namespaceName + "." + className));
        end

        function existsAlready = CheckForExistingInstrName(newName, itemsData)
            %Check the list itemsData - presumed to be a list of
            %Instruments - and see if any have the Name newName

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
            % CHECKNAMESPACEEXISTS - Return true if a namespace with the name exists
            %
            % Input arguments:
            % namespaceName - name of the namespace (string or char scalar)
            %
            % Output arguments:
            % exists - logical true if namespaceName exists, false otherwise
            arguments
                namespaceName {mustBeTextScalar};
            end

            %Check if the namespace exists on the path https://uk.mathworks.com/matlabcentral/answers/1889757-is-there-exist-functionality-for-packages-namespaces
            exists = ~isempty(meta.package.fromName(namespaceName));
        end

        function NewName = GetIncrementedInstrName(instr, itemsData)
            %Prevent duplicate instrument names by appending 1,2,3 to the end
            %of them (can always be edited by user later) on instrument
            %creation
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

        function meths = GetClassMethodsClean(classRef, builtInNamesToExclude, extraNamesToExclude)
            %Private shared functionality between
            %GetInstrumentControlMethods and GetInstrumentMethods

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
                %Remove output signature eg this = Keithley2000() ->
                %Keithley2000()
                cleanSig = mName + extractAfter(mSig, mName);

                %Remove any 'this, ' or 'this'
                cleanSig = strrep(cleanSig, '(this, ', '(');
                cleanSig = strrep(cleanSig, '(this', '(');
            end
        end

        function meths = GetInstrumentControlMethods(instrRef, controlName)
            %Retrieve all the methods/functions that can be called on a
            %given instrument control, as a list of exectuable strings like
            %"RunSweep(arg1, arg2)". Used to populate context
            %menus in Sequence Editor

            controlRef = instrRef.GetRegisteredControlObjectsFromName(controlName);


            builtInNamesToExclude = ["addlistener", "delete", "eq", "findobj", "findprop", "ge", "gt", "isvalid",...
                "le", "listener", "lt", "ne", "notify"];

            instrNamesToExclude = ["CreateInstrumentControlGUI", "DataRowCollected", "GetCommandCompleteFn", "GetName", "MeasurementsInitialised", "MeasurementsPaused", "MeasurementsResumed", "MeasurementsStarted", "MeasurementsStopped",...
                "OnParametersChanged", "OnSweepAbort", "OnSweepComplete", "OnSweepRun", "PlotterAxesSelectionChange",  "RegisterEventListener", "RegisterCommandCompleteQuery",...
                "RemoveControl", "SweepDataChanged", "UnsubscribeFromEvents"];

            meths = Palladium.Utilities.PluginLoading.GetClassMethodsClean(controlRef, builtInNamesToExclude, instrNamesToExclude);
        end

        function meths = GetInstrumentMethods(instrRef)
            %Retrieve all the methods/functions that can be called on a
            %given instrument, as a list of exectuable strings like
            %"GetSourceLevel(level, enable)". Used to populate context
            %menus in Sequence Editor
            builtInNamesToExclude = ["addlistener", "delete", "eq", "findobj", "findprop", "ge", "gt", "isvalid",...
                "le", "listener", "lt", "ne", "notify"];

            instrNamesToExclude = ["CollectMetaData", "DefineSupportedConnectionTypes", "GetAvailableControlOptions", "GetCommandCompleteFn", "GetControlOption", "GetHeaders",...
                "GetRegisteredControlNames", "GetRegisteredControlObjects", "GetRegisteredControlObjectsFromName", "GetSupportedConnectionTypes",...
                "GrabMetadataString", "RegisterControlObject", "RegisterCommandCompleteQuery", "RemoveControlObject", "ShowProperty"];

            meths = Palladium.Utilities.PluginLoading.GetClassMethodsClean(instrRef, builtInNamesToExclude, instrNamesToExclude);
        end

        function classInstance = InstantiateClass(namespace, className)
            %Instantiate an instance of the named class (empty constructor)

            if(isempty(namespace))
                classPath = className;
            else
                classPath = namespace + "." + className;
            end

            fnHandle = str2func(classPath);
            classInstance = fnHandle();
        end

        function classInstance = InstantiateEnum(namespace, className, enumValueString)
            %Instantiate an instance of the named enum

            if(isempty(namespace))
                classPath = className;
            else
                classPath = namespace + "." + className;
            end

            fnHandle = str2func(classPath);
            classInstance = fnHandle(enumValueString);
        end

        function presetFn = InstantiatePreset(namespace, presetName)
            %Instantiate an instance of the named Preset (matlab function file, not a class)

            if(isempty(namespace))
                presetPath = presetName;
            else
                presetPath = namespace + "." + presetName;
            end

            presetFn = str2func(presetPath);
        end

        function classNames = LoadPluginNames(directory)
            %Get the names of all the classes in a plugin directory
            classNames = dir(fullfile(directory, '*.m'));
            classNames = string({classNames.name}');
            classNames = classNames.extractBefore(".m");    %Remove the .m at the end
        end

        function classNames = LoadClassNamesInNamespace(namespaceString)
            %Get a list (array of strings) of the names of all classes
            %defined in a namespace. e.g. running this with
            %"Palladium.Instruments" as the argument would give
            %["Palladium.Instruments.Keithley2000",
            %"Palladium.Instruments.Keithley2410",....
            arguments
                namespaceString string {mustBeTextScalar};
            end

            classData = namespaceClasses(namespaceString);

            if isempty(classData)
                warning("Namespace " + namespaceString + " is empty, no classes found. Not on the path?");
                classNames = [];
                return;
            end

            for i = 1 : length(classData)
                str = string(classData(i).Name);
                classNames(i) = erase(str, namespaceString + ".");
            end
        end

        function SavePresetToJson(controller, instrController, gui, jsonFilePath)
            % SavePresetToJson - Create a preset struct from runtime objects and write JSON.
            %   SavePresetToJson(palladium, gui, jsonFilePath)
            %   Produces JSON compatible with ApplyPresetFromJson.

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
                        if prop.GetAccess == "public" && ~prop.Dependent && prop.SetObservable
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
            % ADAPT: modify to match your gui view APIs to enumerate plotting tabs/windows and their settings
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
            fid = fopen(jsonFilePath, 'w');
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
                out.Column = length(g.ColumnWidth);

                if isempty(pp)
                    warning("Empty plotter holder");
                    return;
                end

                for j = 1 : length(pp)
                    pltr = pp(j);                   

                    % DefaultXAxis / DefaultYAxes extraction 
                    [x, y] = pltr.GetDefaultAxes();
                    out.DefaultXAxis = x;
                    out.DefaultYAxes = y;
                end
            end
        end

    end
end

