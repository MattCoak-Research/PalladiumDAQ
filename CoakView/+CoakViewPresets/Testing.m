function Testing(coakView)
%Testing - Testing preset for CoakView for developing on office PCs - all
%debug, no hardware, testing new commands etc

%Programmatically sets various parameters and GUI
%preferences to suit a particular setup or experiment. 

%Settings and values
coakView.SetUpdateTime(0.2);


%Add the Lakeshore 370 temperature controller and configure it
ls370 = coakView.AddInstrument("Lakeshore370");
ls370.Connection_Type = CoakView.Enums.ConnectionType.Debug;
ls370.Ch_Name = "Sample Temperature (K)";


%Add the Lakeshore 340 temperature controller and configure it
ls350 = coakView.AddInstrument("Lakeshore350");
ls350.Connection_Type = CoakView.Enums.ConnectionType.Debug;
ls350.Ch_A_Name = "1K Plate Temperature (K)";
ls350.Ch_B_Name = "Sorb Temperature (K)";
ls350.ControlChannel = "B";



%Add a Keithley
k = coakView.AddInstrument("Keithley2000");
k.Connection_Type = CoakView.Enums.ConnectionType.Debug;
%Add the first listed control
[controlDetailsStructs] = k.GetAvailableControlOptions();
coakView.AddInstrumentControl(k, controlDetailsStructs(1));


%Add a Plotting tab for the lakeshore 370
pltr = coakView.AddNewPlottingTab(1, 1);
if ~ isempty(pltr)  %Catches if we are in a no-GUI View...
    pltr.SetDefaultXAxis("Time (mins)");
    pltr.SetDefaultYAxes("Sample Temperature (K)", [], [], []);
end

%Add a Plotting tab for the lakeshore 340
pltr = coakView.AddNewPlottingTab(1, 1);
if ~isempty(pltr)
    pltr.SetDefaultXAxis("Time (mins)");
    pltr.SetDefaultYAxes("1K Plate Temperature (K)", "Sorb Temperature (K)", [], []);
end


%Add a Plotting tab
coakView.AddNewPlottingTab(2, 2);


%Add a Plotting window
%coakView.AddNewPlottingWindow(1, 1);

end

