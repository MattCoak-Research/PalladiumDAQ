function Testing(palladium, gui)
%Testing - Testing preset for Palladium for developing on office PCs - all
%debug, no hardware, testing new commands etc

%Programmatically sets various parameters and GUI
%preferences to suit a particular setup or experiment. 

%Settings and values
palladium.SetUpdateTime(0.2);


%Add the Lakeshore 370 temperature controller and configure it
ls370 = palladium.AddInstrument("Lakeshore370");
ls370.Connection_Type = Palladium.Enums.ConnectionType.Debug;
ls370.Ch_Name = "Sample Temperature (K)";


%Add the Lakeshore 340 temperature controller and configure it
ls350 = palladium.AddInstrument("Lakeshore350");
ls350.Connection_Type = Palladium.Enums.ConnectionType.Debug;
ls350.Ch_A_Name = "1K Plate Temperature (K)";
ls350.Ch_B_Name = "Sorb Temperature (K)";
ls350.ControlChannel = "B";



%Add a Keithley
k = palladium.AddInstrument("Keithley2000");
k.Connection_Type = Palladium.Enums.ConnectionType.Debug;
%Add the first listed control
gui.AddInstrumentControl(k, k.GetControlOption("Sweep Control"));


%Add a Plotting tab for the lakeshore 370
% pltr = gui.AddNewPlottingTab(1, 1);
% if ~ isempty(pltr)  %Catches if we are in a no-GUI View...
%     pltr.SetDefaultXAxis("Time (mins)");
%     pltr.SetDefaultYAxes("Sample Temperature (K)", [], [], []);
% end
% 
% %Add a Plotting tab for the lakeshore 340
% pltr = gui.AddNewPlottingTab(1, 1);
% if ~isempty(pltr)
%     pltr.SetDefaultXAxis("Time (mins)");
%     pltr.SetDefaultYAxes("1K Plate Temperature (K)", "Sorb Temperature (K)", [], []);
% end
% 
% 
% %Add a Plotting tab
% gui.AddNewPlottingTab(2, 2);


%Add a Plotting window
%gui.AddNewPlottingWindow(1, 1);

end

