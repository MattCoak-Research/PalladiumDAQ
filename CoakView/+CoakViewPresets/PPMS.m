function PPMS(coakView)
%PPMS - COakVIew preset function for when interfacing with a remote computer controlling a PPMS cryostat.


%Add the PPMS and configure
ppms = coakView.AddInstrument("PPMS");
ppms.IP_Address = "147.188.43.118"; %ip address of ppms over eduroam
ppms.Name = "PPMS";

%Add a Plotting tab - this returns a list of all the plotters in it
pltrs = coakView.AddNewPlottingTab(2, 1);
pltrs(1).SetDefaultXAxis("Time (mins)");
pltrs(2).SetDefaultXAxis("Time (mins)");
pltrs(1).SetDefaultYAxes("PPMS - Temperature_K", [], [], []);
pltrs(2).SetDefaultYAxes("PPMS - Field_T", [], [], []);

end

