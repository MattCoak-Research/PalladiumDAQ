function Example(coakView, gui)
%EXAMPLE - Example/template preset for CoakView. Edit it, save as
%'Filename' in the Presets folder, then use it by calling
%CoakView('Filename') to programmatically set various parameters and GUI
%preferences to suit a particular setup or experiment. All of this can be
%done in the GUI, this is solely for convenience.


%Add an instrument of specified type
coakView.AddInstrument("Keithley2000");


%Add an instrument of specified type then modify its properties
instr = coakView.AddInstrument("Lakeshore350");
instr.Connection_Type = CoakView.Enums.ConnectionType.Debug;
instr.Ch_A_Name = "1 K Pot Temp (K)";
instr.Ch_C_Name = "Sample Stage Temp (K)";


%Add an instrument of specified type  then modify its properties - adding a
%sweep control panel to it to show off
k24 = coakView.AddInstrument("Keithley24X0");
k24.SweepControl = true;
k24.MeasMode = k24.MeasType("Current"); %Example of how to set Categorical properties in Preset files


%Add a Plotting tab
pltr = gui.AddNewPlottingTab(1, 1);
pltr.SetDefaultXAxis("Time (mins)");
pltr.SetDefaultYAxes("Time (mins)", [], "K2000_1 - Resistance (Ohms)", []);
gui.AddNewPlottingTab(2, 2);


%Add a Plotting window
%gui.AddNewPlottingWindow(1, 1);

end

