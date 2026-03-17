function ADR(palladium, gui)
%ADR - ADR preset for Palladium for the LG9 Adiabatic Demag Refrigerator cryostat.

%Programmatically sets various parameters and GUI
%preferences to suit a particular setup or experiment. 

%Settings and values
palladium.SetUpdateTime(0.5);


%Add the Lakeshore 372 temperature controller and configure it - for now I
%think 370 and 372 code is interchangable..
ls372 = palladium.AddInstrument("Lakeshore372", Name="Lakeshore372", ConnectionType="GPIB");
ls372.GPIB_Address = 11;
ls372.Ch_Name = "Sample Temperature (K)";

%Add the Lakeshore 350 temperature controller and configure it
ls350 = palladium.AddInstrument("Lakeshore350", Name="Lakeshore350", ConnectionType="GPIB");
ls350.GPIB_Address = 12;
ls350.Ch_A_Name = "1K Plate Temperature (K)";
ls350.Ch_B_Name = "Sorb Temperature (K)";
ls350.ControlChannel = "B";

%Add a Plotting Window for the lakeshore 370 and 350
pltr = gui.AddNewPlottingWindow(1, 1);
pltr.SetDefaultXAxis("Time (mins)");
pltr.SetDefaultYAxes("Sample Temperature (K)", "1K Plate Temperature (K)", [], []);

%Add demag magnet power supply
demagIPS = palladium.AddInstrument("Mercury120_10_IPS", Name = "Demag Magnet", ConnectionType="Serial");
demagIPS.Serial_Address = "COM4";

%Add sample magnet power supply
sampleIPS = palladium.AddInstrument("Mercury120_IPS", Name = "Sample Magnet", ConnectionType="Serial");
sampleIPS.GPIB_Address = 25;

%Add a Plotting tab for the magnets
pltr = gui.AddNewPlottingTab(1, 1);
pltr.SetDefaultXAxis("Time (mins)");
pltr.SetDefaultYAxes("Demag Magnet - Field (T)", [], [], []);

%Add a Plotting tab
gui.AddNewPlottingTab(1, 1);

end

