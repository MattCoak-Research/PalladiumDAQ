function plan = buildfile
plan = buildplan(localfunctions);
plan("test").Dependencies = "check";
plan("package").Dependencies = "test";
plan("deploy").Dependencies = "package";
plan("deployDebug").Dependencies = "test";
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
projectRoot = "";

%Construct a toolbox options object to set parameters, and retrieve the
%build version
opts = matlab.addons.toolbox.ToolboxOptions("PalladiumDAQ.prj");
verStruct = Palladium.ver();

%Set various settings for the toolbox
opts.AuthorCompany = "University of Birmingham";
opts.AuthorEmail = "m.j.coak@bham.ac.uk";
opts.AuthorName = "Matthew Coak";
opts.Description = "Palladium Data Acquisition - an open source platform for laboratory instrument control, data acquisition logging and graphing. See https://github.com/MattCoak-Research/PalladiumDAQ for details.";
opts.MinimumMatlabRelease = "R2026a";
opts.MaximumMatlabRelease = "";
opts.OutputFile = fullfile(projectRoot, "Release", "Toolbox", "PalladiumDAQ.mltbx");
opts.ToolboxGettingStartedGuide = fullfile(projectRoot, "Docs", "Palladium DAQ Toolbox Getting Started Guide"); 
opts.ToolboxVersion = string(verStruct.VersionString);

%Build the .mltbx toolbox installation file
matlab.addons.toolbox.packageToolbox(opts);
end

function deployDebugTask(~)
projectRoot = ""; %Was full path: "E:\OneDrive\OneDrive - University of Birmingham\Physics\Matlab\Palladium DAQ";

%Define, then clear (ready to write to) output directory
exeDir = fullfile(projectRoot, "Release", "Debug Build");
if exist(exeDir, "dir")
    %Don't delete the exeDir, as we'd quite like to lazily keep the config
    %file in there..
 %   rmdir(exeDir, "s");
end

%Set build options
buildOpts = AssembleBuildOptions(verString);
buildOpts.ExecutableName = "PalladiumDAQ";
buildOpts.OutputDir = exeDir;

BuildDebugStandalone(buildOpts);
end

function deployTask(~)
projectRoot = ""; %Was full path: "E:\OneDrive\OneDrive - University of Birmingham\Physics\Matlab\Palladium DAQ";

%Define, then clear (ready to write to) output directory
exeDir = fullfile(projectRoot, "Release", "Build");
if exist(exeDir, "dir")
    rmdir(exeDir, "s");
end

%Define, then clear (ready to write to) output directory
packageDir = fullfile(projectRoot, "Release", "Package");
if exist(packageDir, "dir")
    rmdir(packageDir, "s");
end

%Retrieve version
verStruct = Palladium.ver();
verString = string(verStruct.VersionString);

%Set build options
buildOpts = AssembleBuildOptions(verString);
buildOpts.ExecutableName = "PalladiumDAQ";
buildOpts.OutputDir = exeDir;

%Build the standalone .exe file (not yet the full installer) to the Build
%folder
buildResult = BuildStandalone(buildOpts);

%Build a debug version of the .exe which has a console window (just using
%the all platform version, on windows). This will not work for mac
%developers
if ispc
    BuildDebugStandalone(buildOpts);
end

% Create package options object, set package properties and package.
packageOpts = compiler.package.InstallerOptions(buildResult);
packageOpts.ApplicationName = "Palladium DAQ";
packageOpts.AuthorName = "Matthew Coak";
packageOpts.AuthorCompany = "University of Birmingham";
packageOpts.InstallerIcon = fullfile(projectRoot, "Palladium DAQ", "+Palladium", "+Components", "Graphics", "PalladiumDAQIcon.png");
packageOpts.InstallerSplash = "splash.png";
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

directory = packageOpts.OutputDir;

% Download the MATLAB Runtime to include in the installer.
compiler.runtime.download;

%Make installer with runtime bundled
packageOpts.RuntimeDelivery = "installer";
packageOpts.OutputDir = fullfile(directory, "Runtime Bundled");
packageOpts.InstallerName = "Palladium DAQ Installer - Runtime Bundled";
compiler.package.installer(buildResult, "Options", packageOpts);


%Make Web installer
packageOpts.RuntimeDelivery = "web";
packageOpts.OutputDir = fullfile(directory, "Runtime Web Installer");
packageOpts.InstallerName = "Palladium DAQ Installer - Runtime Web Installer";
compiler.package.installer(buildResult, "Options", packageOpts);


%Make installer without runtime included
packageOpts.RuntimeDelivery = "none";
packageOpts.OutputDir = fullfile(directory, "No Runtime");
packageOpts.InstallerName = "Palladium DAQ Installer - No Runtime";
compiler.package.installer(buildResult, "Options", packageOpts);

end

function filePathsStrArray = GetAdditionalFilesFromFolders(listOfDirs)
filePathsStrArray = [];

for i = 1 : length(listOfDirs)
    dr = listOfDirs(i);

    assert(exist(dr, "dir"), "Directory " + dr + " not found in buildfile");
   classNames = dir(fullfile(dr, '*.m'));
    filePathsStrArray = [filePathsStrArray, fullfile(dr, string({classNames.name}))]; 
end
end

function filePathsStrArray = RemoveAdditionalFiles(strIn, stringsToRemove)
filePathsStrArray = strIn;
for i = 1 : length(stringsToRemove)    
    idx = strcmp(strIn,stringsToRemove(i));
    filePathsStrArray(idx) = [];
end
end

function buildOpts = AssembleBuildOptions(verString)

%The compiler excludes any code files it doesn't find an explicit mention
%of. Add those in here. Instrument files and dynamically loaded Views are
%good examples.
additionalFiles = GetAdditionalFilesFromFolders([...,...
    fullfile("Palladium DAQ", "+Palladium", "+Components"),...
    fullfile("Palladium DAQ", "+Palladium", "+Instruments"),...
    fullfile("Palladium DAQ", "+Palladium", "+Instruments", "+Controls"),...
    fullfile("Palladium DAQ", "+Palladium", "+Instruments", "+Events"),...
    fullfile("Palladium DAQ", "+Palladium", "+Enums"),...
    fullfile("Palladium DAQ", "+Palladium", "+Events"),...
    fullfile("Palladium DAQ", "+Palladium", "+Sequence", "+Views"),...
    fullfile("Palladium DAQ", "+Palladium", "+Views")]);

additionalFiles = RemoveAdditionalFiles(additionalFiles, [...
    fullfile("Palladium DAQ", "+Palladium", "+Instruments", "TestInstrument.m")...
    ]);

%Set build options
buildOpts = compiler.build.StandaloneApplicationOptions(fullfile(projectRoot, "Palladium DAQ", "Palladium.m"));
buildOpts.AdditionalFiles = additionalFiles;
buildOpts.AutoDetectDataFiles = true;
buildOpts.EmbedArchive = true;
buildOpts.ExecutableIcon = fullfile(projectRoot, "Palladium DAQ", "+Palladium", "+Components", "Graphics", "PalladiumDAQIcon.png");
buildOpts.ExecutableVersion = verString;
buildOpts.ObfuscateArchive = false;
buildOpts.TreatInputsAsNumeric = false;
buildOpts.Verbose = true;

end