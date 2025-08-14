classdef InstrumentController < handle
    %INSTRUMENTCONTROLLER - logic/container/manager class for handling
    %instrument creation and management in CoakView, and liaising with
    %Instrument selection GUIs in the View
    
    properties (GetAccess = public, SetAccess = private)
        ListOfAvailableInstrumentClassNameStrings;
        SelectedInstrumentNames;
        SelectedInstruments;
    end

    
    properties (Access = private)
        Controller; %Reference back to the overall CoakView Controller that handles all the main logic - feed things back to there
        View;   %FrontEnd or GUI that this will plug into to display changes and trigger functions in here
    end

    properties (Access = private, Constant)
        Namespace string = "CoakView.Instruments";
        ControlsNamespace string = "CoakView.Instruments.Controls";
    end
    
    methods

        %% Constructor
        function this = InstrumentController(controller, view)
            this.Controller = controller;
            this.View = view;
        end

        %% AddEnabledByDefaultInstrumentControls
        function AddEnabledByDefaultInstrumentControls(this, instr)
            cdsList = instr.GetAvailableControlOptions();

            if isempty(cdsList)
                return;
            end

            for i=1 : length(cdsList)
                cds = cdsList(i);

                if cds.EnabledByDefault
                    this.Controller.AddInstrumentControl(instr, cds);
                end
            end
        end
     
        
        %% AddInstrument
        function instRef = AddInstrument(this, instrStringToAdd)
            %Add an instrument just from a string of the name of its class

            %Check for error cases like empty list box selection
            if(isempty(instrStringToAdd))
                instRef = [];
                return;
            end

            %Make sure the instrName is valid, and other error checking
            assert(isstring(instrStringToAdd), "Instrument name must be a string");
            assert(~isempty(this.ListOfAvailableInstrumentClassNameStrings), "List of loaded instrument classes to select from is empty - file paths messed up?");
            assert(any(contains(this.ListOfAvailableInstrumentClassNameStrings, instrStringToAdd, "IgnoreCase", false)), string(instrStringToAdd) + " not found in list of avaliable Instruments");
          

            %Make an instance of the selected datasource class
            instRef = CoakView.Utilities.FileLoading.PluginLoading.InstantiateClass(this.Namespace, instrStringToAdd);
            
            %Give the newly created instrument a number at the end of its
            %name ie Lakeshore350_1
            instRef.Name = CoakView.Utilities.FileLoading.PluginLoading.GetIncrementedInstrName(instRef, this.SelectedInstruments);
            
            %Add the new instrument, and the name of its class, to the
            %lists of each held in this class (will also be done in the
            %View, which hopefully will match!)
            if(isempty(this.SelectedInstrumentNames))
                this.SelectedInstrumentNames = instrStringToAdd;
                this.SelectedInstruments = {instRef};                
            else
                this.SelectedInstrumentNames = [this.SelectedInstrumentNames, instrStringToAdd];
                this.SelectedInstruments = [this.SelectedInstruments, {instRef}];
            end
            
            %Update the View
            this.View.OnInstrumentAdded(instrStringToAdd, instRef);
        end    

        %% AddInstrumentControl
        function controlClassRef = AddInstrumentControl(this, controller, tab, instrRef, controlDetailsStruct)
            
            %Make an instance of the selected datasource class
            controlClassRef = CoakView.Utilities.FileLoading.PluginLoading.InstantiateClass(this.ControlsNamespace, controlDetailsStruct.ControlClassFileName);      
            controlClassRef.ControlDetailsStruct = controlDetailsStruct;

            %Tell the control class to create the required GUI etc
            controlClassRef.CreateInstrumentControlGUI(controller, tab, instrRef);

            %Register the control class with the instrument
            instrRef.RegisterControlObject(controlClassRef);
        end
          
        %% GetInstruments
        function instRefs = GetInstruments(this)            
            instRefs = this.SelectedInstruments;
        end

        %% LoadInstrumentClasses
        function LoadInstrumentClasses(this, folderPath)
            classNames = CoakView.Utilities.FileLoading.PluginLoading.LoadPluginNames(folderPath);
            this.PopulateInstrumentList(classNames);
        end

        %% PopulateInstrumentList
        function PopulateInstrumentList(this, cellArrayOfInstrumentNameStrings)
            %Update the stored list of instrument classes that can be
            %loaded, so we can check against it later for e.g. verification
            %and error checking
            this.ListOfAvailableInstrumentClassNameStrings = cellArrayOfInstrumentNameStrings;

            %Pass through to the View
            this.View.PopulateInstrumentList(cellArrayOfInstrumentNameStrings);
        end     
              
        %% RemoveInstrument
        function RemoveInstrument(this, instrumentRef)
            if isempty(instrumentRef)
                return;
            end

            %Update the View (before we delete the reference!)
            this.View.OnInstrumentRemoved(instrumentRef);

            %Remove it from the list held here
            for i = 1 : length(this.SelectedInstruments)
                if strcmp(this.SelectedInstruments{i}.Name, instrumentRef.Name)
                    this.SelectedInstruments(i) = [];
                    this.SelectedInstrumentNames(i) = [];
                    break;
                end
            end

            %Remove the instrument class reference from memory
            delete(instrumentRef);
        end

        %% RemoveInstrumentControl
        function RemoveInstrumentControl(this, instrRef, controlDetailsStruct)
       
            %Get a reference to the InstrumentControlBase object assigned
            %to this Instrument, of this name
            controlClassName = controlDetailsStruct.Name;
            objsList = instrRef.GetRegisteredControlObjectsFromName(controlClassName);
          
            %Error checking
            assert(~isempty(objsList), "Could not find control to remove on Instrument " + instrRef.Name);
            assert(isscalar(objsList), "Expected to find exactly 1 InstrumentControl..");
            controlClass = objsList(1);

            %Send the remove command
            controlClass.RemoveControl(instrRef);

            %De-register the control class with the instrument
            instrRef.RemoveControlObject(controlClassName);

            %Delete the reference
            delete(controlClass);
        end
    end
    
    
end

