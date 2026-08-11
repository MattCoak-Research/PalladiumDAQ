function plan = buildfile
plan = buildplan(localfunctions);
plan("test").Dependencies = "check";
plan("package").Dependencies = "test";
plan("deploy").Dependencies = "package";
end

function checkTask(~)
issues = codeIssues(["Palladium DAQ/+Palladium/", "Palladium DAQ/Tests/"], IncludeSubfolders=true);
if ~isempty(issues.Issues)
    disp(" ");
    disp("Code Issues Found:");
    disp(" ");
    disp(issues.Issues);
    disp(" ");
    disp(" ");
    % error("BuildFile:IssuesFound", "Code issues found.");
end
end

function testTask(~)
results = runtests("Palladium DAQ/Tests/Unit Tests/", IncludeSubfolders=true);
assertSuccess(results);
end

function packageTask(~)
opts = matlab.addons.toolbox.ToolboxOptions("PalladiumDAQ.prj");
verStruct = Palladium.ver();
opts.ToolboxVersion = string(verStruct.VersionString);
matlab.addons.toolbox.packageToolbox(opts);
end

function deployTask(~)
projectRoot = ""; %Was full path: "E:\OneDrive\OneDrive - University of Birmingham\Physics\Matlab\Palladium DAQ";

% Create target build options object, set build properties and build.
% AdditionalFiles - Additional files
% character vector | string scalar | cell array of character vectors | string array
% AutoDetectDataFiles - Flag to automatically include data files
% 'on' | on/off logical value
% CustomHelpTextFile - Path to help file
% character vector | string scalar
% EmbedArchive - Flag to embed deployable archive
% 'on' | on/off logical value
% ExecutableIcon - Path to icon image
% character vector | string scalar
% ExecutableName - Name of generated application
% character vector | string scalar
% ExecutableSplashScreen - Path to splash screen image
% character vector | string scalar
% ExecutableVersion - Executable version
% '1.0.0.0' | character vector | string scalar
% ExternalEncryptionKey - Paths to encryption key and loader files
% scalar struct
% ObfuscateArchive - Flag to obfuscate deployable archive
% 'off' | on/off logical value
% OutputDir - Path to output directory
% character vector | string scalar
% SecretsManifest - Path to JSON manifest file
% character vector | string scalar
% SupportPackages - Support packages
% 'autodetect' | 'none' | string scalar | cell array of character vectors | string array
% TreatInputsAsNumeric - Flag to interpret command line inputs
% 'off' | on/off logical value
% Verbose - Flag to control build verbosity
% 'off' | on/off logical value

%Define, then clear (ready to write to) output directory
exeDir = fullfile(projectRoot, "Palladium DAQ", "Release", "Standalone", "Build");
if exist(exeDir, "dir")
    rmdir(exeDir, "s");
end

%Define, then clear (ready to write to) output directory
packageDir = fullfile(projectRoot, "Palladium DAQ", "Release", "Standalone", "Package");
if exist(packageDir, "dir")
    rmdir(packageDir, "s");
end

%Retrieve version
verStruct = Palladium.ver();
verString = string(verStruct.VersionString);

%Set build options
buildOpts = compiler.build.StandaloneApplicationOptions(fullfile(projectRoot, "Palladium DAQ", "Palladium.m"));
buildOpts.AutoDetectDataFiles = true;
buildOpts.EmbedArchive = true;
buildOpts.ExecutableIcon = fullfile(projectRoot, "Palladium DAQ", "+Palladium", "+Components", "Graphics", "PalladiumDAQIcon.png");
buildOpts.ExecutableName = "PalladiumDAQ";
buildOpts.ExecutableVersion = verString;
buildOpts.OutputDir = exeDir;
buildOpts.ObfuscateArchive = false;
buildOpts.TreatInputsAsNumeric = false;
buildOpts.Verbose = true;

%Build the standalone .exe file (not yet the full installer) to the Build
%folder
buildResult = BuildStandalone(buildOpts);

%Build a debug version of the .exe which has a console window (just using
%the all platform version, on windows). This will not work for mac
%developers
BuildDebugStandalone(buildOpts);


%AdditionalFiles - Additional files
% character vector | string scalar | cell array of character vectors | string array
% AddRemoveProgramsIcon - Add or remove programs icon
% character vector | string scalar | string array
% ApplicationName - Application name
% "" | character vector | string scalar
% AuthorCompany - Company name
% "" | character vector | string scalar
% AuthorEmail - Email address
% "" | character vector | string scalar
% AuthorName - Name
% "" | character vector | string scalar
% DefaultInstallationDir - Default installation path
% character vector | string scalar
% Description - Detailed application description
% "" | character vector | string scalar
% InstallationNotes - Notes
% "" | character vector | string scalar
% InstallerIcon - Path to icon image
% character vector | string scalar
% InstallerLogo - Path to installer image
% character vector | string scalar
% InstallerName - Name of installer file
% MyAppInstaller | character vector | string scalar
% InstallerSplash - Path to splash screen image
% character vector | string scalar
% OptionalDependencies - Optional dependencies to include
% "all" | "none"
% OutputDir - Path to folder where the installer will be saved
% character vector | string scalar
% PackageType - Installer file type
% "auto" | "zip"
% RuntimeDelivery - MATLAB Runtime delivery option
% "web" | "installer" | "none"
% Shortcut - Path to shortcut
% "" | character vector | string scalar
% Summary - Summary description of application
% "" | character vector | string scalar
% Version - Version of installed application
% "1.0" | character vector | string scalar
% Verbose - Flag to control output verbosity
% "off" | on/off logical value

% Create package options object, set package properties and package.
packageOpts = compiler.package.InstallerOptions(buildResult);
packageOpts.ApplicationName = "Palladium DAQ";
packageOpts.AuthorName = "Matthew Coak";
packageOpts.AuthorCompany = "University of Birmingham";
packageOpts.InstallerIcon = fullfile(projectRoot, "Palladium DAQ", "+Palladium", "+Components", "Graphics", "PalladiumDAQIcon.png");
packageOpts.OutputDir = packageDir;
packageOpts.Version = verString;
packageOpts.Verbose = true;

%Create the installer files
GenerateInstallers(packageOpts, buildResult);

end

function buildResult = BuildStandalone(buildOpts)
if ispc
    %Build windows-specific version - which will not open a console window
    %behind it
    buildResult = compiler.build.standaloneWindowsApplication(buildOpts);
else
    %Build multi-platform version
    buildResult = compiler.build.standaloneApplication(buildOpts);
end
end

function BuildDebugStandalone(buildOpts)
buildOpts.ExecutableName = "PalladiumDAQ_Debug";
compiler.build.standaloneApplication(buildOpts);
end

function GenerateInstallers(packageOpts, buildResult)

% Download the MATLAB Runtime to include in the installer.
compiler.runtime.download;

%Make installer with runtime bundled
% packageOpts.RuntimeDelivery = "installer";
% packageOpts.InstallerName = "Palladium DAQ Installer - Runtime Bundled";
% compiler.package.installer(buildResult, "Options", packageOpts);


%Make Web installer
packageOpts.RuntimeDelivery = "web";
packageOpts.InstallerName = "Palladium DAQ Installer - Runtime Web Installer";
compiler.package.installer(buildResult, "Options", packageOpts);


%Make installer without runtime included
packageOpts.RuntimeDelivery = "none";
packageOpts.InstallerName = "Palladium DAQ Installer - No Runtime";
compiler.package.installer(buildResult, "Options", packageOpts);

end