classdef LakeshoreHeaterControl < Palladium.Core.InstrumentControlBase
    %LakeshoreHeaterControl - Logic controller add-on object to be added on to an
    %Instrument object, where it will handle the logic of adding a
    %Lakeshore-style heater control panel for PID and setpoint settings.

    %% Properties (Private)
    properties (Access = private)
        GUIView;
        Plotter;
    end

    %% Constructor
    methods
        function this = LakeshoreHeaterControl()
        end
    end

    %% Methods (Public)
    methods (Access = public)

        function CreateInstrumentControlGUI(this, controller, tab, instrRef)
            %Create grid and TempControl component and position them in the
            %tab.
            grid = uigridlayout(tab, "ColumnWidth", {'1x', 'fit', '1x'}, "RowHeight", {10, 'fit', 10, '1x'}, 'RowSpacing', 2);

            %Create a .mlapp custom GUI control and add it to the grid
            comp = Palladium.Instruments.Controls.LakeshoreTempControl(grid);
            this.GUIView = comp;
            comp.Layout.Row = 2;
            comp.Layout.Column = 2;

            %Make a specific reference in the Lakeshore Instrument Class
            this.Instrument = instrRef;

            %Set instrument-model-specific options
            switch(this.Instrument.FullName)
                case("Lakeshore 340")
                    comp.SetTempControllerModel("340");
                case("Lakeshore 350")
                    comp.SetTempControllerModel("350");
                case("Lakeshore 370")
                    comp.SetTempControllerModel("370");
                case("Lakeshore 372")
                    comp.SetTempControllerModel("370"); %372 is the same as 370 here
                otherwise
                    error(l.FullName + " not currently supported in LakeshoreHeaterControl");
            end

            %Add a plotter as well underneath
            this.Plotter = controller.AddNewPlotter(grid, Size="Medium");
            this.Plotter.Layout.Row = 4;
            this.Plotter.Layout.Column = [1 3];   %Span columns

            %Set default displayed axes for the plotter
            this.Plotter.SetDefaultXAxis("Time (mins)");

            %Set instrument-specific default plotter var names etc
            this.UpdateVarNames();

            %Subscribe to events
            addlistener(comp, 'HeaterSettingsInput', @(src,evnt)this.HeaterSettingsInput(src,evnt));
        end

        function DisplayData(this, settingStruct, heaterPercent, heaterEnabled, heaterPower)
            %Pass through to GUI View
            this.GUIView.DisplayData(settingStruct, heaterPercent, heaterEnabled, heaterPower)
        end

        function HeaterSettingsInput(this, ~, eventData)
            %Pass event-triggered function call through to the Instrument
            this.Instrument.SettingsInput(eventData.Settings);
        end

        function RemoveControl(this, ~)
            %Delete GUI objects
            delete(this.GUIView);
            this.GUIView = [];
        end

        function UpdateData(this, dataRow, headers) %#ok<INUSD>
            [settings, heaterLevelPct, heaterEnabled, heaterPower] = this.Instrument.CollectHeaterControlSettings();
            this.DisplayData(settings, heaterLevelPct, heaterEnabled, heaterPower);
        end

        function UpdateVarNames(this)
            %Set instrument-model-specific options
            switch(this.Instrument.FullName)
                case("Lakeshore 340")
                    this.ConfigureForLS340(this.Instrument, this.Plotter);
                case("Lakeshore 350")
                    this.ConfigureForLS350(this.Instrument, this.Plotter);
                case("Lakeshore 370")
                    this.ConfigureForLS370(this.Instrument, this.Plotter);
                case("Lakeshore 372")
                    this.ConfigureForLS370(this.Instrument, this.Plotter);
                otherwise
                    error(l.FullName + " not currently supported in LakeshoreHeaterControl");
            end

        end
    end

    %% Methods (Private)
    methods (Access = private)

        function ConfigureForLS340(this, instrRef, pltr)
            %Set default displayed axes for the plotter
            controlChnl = string(instrRef.ControlChannel);
            switch(controlChnl)
                case("A")
                    %Commenting for now - these evaluate too early, and
                    %then the channel name has been changed by the time it
                    %is time to select the axis on the plotter. Need to
                    %trigger updates from an event on Name, ChannelName
                    %change etc...
                    %pltr.SetDefaultYAxis(1, string(instrRef.Ch_A_Name));
                case("B")
                    %pltr.SetDefaultYAxis(1, string(instrRef.Ch_B_Name));
            end

            %Set 2nd y axis to be the heater power, and set that to the RHS
            %axis
            %  pltr.SetDefaultYAxis(2, instrRef.Name + " Heater Power (W)");
            % pltr.SetAxisSide(2, "Right");
        end

        function ConfigureForLS350(this, instrRef, pltr)
            controlChnl = string(instrRef.ControlChannel);
            switch(controlChnl)
                case("A")
                    %   pltr.SetDefaultYAxis(1, string(instrRef.Ch_A_Name));
                case("B")
                    %  pltr.SetDefaultYAxis(1, string(instrRef.Ch_B_Name));
                case("C")
                    % pltr.SetDefaultYAxis(1, string(instrRef.Ch_C_Name));
                case("D")
                    % pltr.SetDefaultYAxis(1, string(instrRef.Ch_D_Name));
            end

            %Set some more default axes for the plotter
            %pltr.SetDefaultYAxis(2, instrRef.Name + " Heater Power (W)");
            % pltr.SetAxisSide(2, "Right");   %Set 2nd y axis to be the heater power, and set that to the RHS axis
        end

        function ConfigureForLS370(this, instrRef, pltr)   %LS372 treated as the same as 370
            %Set default displayed axes for the plotter
            %  pltr.SetDefaultYAxis(1, instrRef.Ch_Name);

            %Set some more default axes for the plotter
            % pltr.SetDefaultYAxis(2, instrRef.Name + " Heater Power (W)");
            % pltr.SetAxisSide(2, "Right");   %Set 2nd y axis to be the heater power, and set that to the RHS axis
        end
    end
end

