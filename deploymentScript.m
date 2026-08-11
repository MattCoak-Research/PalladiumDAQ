projectRoot = "/Users/a.j.lyttle@bham.ac.uk/Repos/github.com/MattCoak-Research/PalladiumDAQ";

% Create target build options object, set build properties and build.
buildOpts = compiler.build.StandaloneApplicationOptions(fullfile(projectRoot, "launchApplication.m"));
buildOpts.AdditionalFiles = fullfile(projectRoot, "Palladium DAQ", "Instrument Drivers");
buildOpts.AutoDetectDataFiles = true;
buildOpts.OutputDir = fullfile(projectRoot, "Palladium DAQ", "Release", "output", "build");
buildOpts.SupportPackages = "none";
buildOpts.ObfuscateArchive = false;
buildOpts.Verbose = true;
buildOpts.EmbedArchive = true;
buildOpts.ExecutableName = "PalladiumDAQ";
buildOpts.ExecutableVersion = "1.0.0";
buildOpts.TreatInputsAsNumeric = false;
buildResult = compiler.build.standaloneApplication(buildOpts);


% Create package options object, set package properties and package.
packageOpts = compiler.package.InstallerOptions(buildResult);
packageOpts.ApplicationName = "PalladiumDAQ";
packageOpts.AuthorName = "Matthew Coak";
packageOpts.InstallerName = "PalladiumDAQInstaller";
packageOpts.OutputDir = fullfile(projectRoot, "Palladium DAQ", "Release", "output", "package");
packageOpts.Verbose = true;
compiler.package.installer(buildResult, "Options", packageOpts);