function plan = buildfile
plan = buildplan(localfunctions);
plan("test").Dependencies = "check";

docfolder = fullfile("Palladium DAQ", "Docs");
plan("doc").Inputs = docfolder; 
plan("doc").Outputs = [fullfile(docfolder,"**","*.html"), ... % output HTML
    fullfile(docfolder,"resources"), ... % stylesheets and scripts
    fullfile(docfolder,"*.xml"), ... % index files
    fullfile(docfolder,"helpsearch-v*")]; % search database folder 
plan("doc").Dependencies = "apidoc";

plan("apidoc").Inputs = [fullfile("Palladium DAQ", "+Palladium"), fullfile("Tools", "GenerateApiReference.m")];
plan("apidoc").Outputs = fullfile(docfolder, "reference");

plan("package").Dependencies = ["test", "doc"];
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

function docTask(c)
doc = c.Task.Inputs.Path; % source folder

EnsureDocMaker();

%DocMaker (pre-0.8) copies its stylesheets/scripts from its read-only
%add-on install folder, and the copies keep the read-only attribute - so
%the next build can't overwrite them. Make any existing ones writable, then
%clear the folder so stale files (e.g. from a different Theme) don't linger
res = fullfile(doc, "resources");
if isfolder(res)
    MakeWritable(res);
    rmdir(res, "s");
end

%Convert one document at a time, so that a GitHub timeout only retries
%that document (see ConvertWithRetry)
mdFiles = dir(fullfile(doc,"**","*.md")); % Markdown documents
html = strings(1, 0);
for i = 1 : numel(mdFiles)
    html(i) = ConvertWithRetry(fullfile(mdFiles(i).folder, mdFiles(i).name), doc);
end
docrun(html(~contains(html, filesep + "reference" + filesep))) % run code and insert output - not in the generated API reference
docindex(doc) % index
end

function html = ConvertWithRetry(md, root)
%Convert one Markdown document to HTML. DocMaker converts via GitHub's
%Markdown API, which sometimes times out (HTTP 502/503/504) - retry a few
%times before failing the build
maxAttempts = 3;
for attempt = 1 : maxAttempts
    %Each docconvert call re-copies DocMaker's read-only stylesheets (see
    %docTask), so make any existing copies writable first
    if isfolder(fullfile(root, "resources"))
        MakeWritable(fullfile(root, "resources"));
    end

    try
        html = docconvert(md, Theme="light", Root=root); % light theme suits the Help browser
        return
    catch err
        isServerError = contains(err.message, "HTTP/1.1 50" + ["2", "3", "4"]);
        if ~isServerError || attempt == maxAttempts
            rethrow(err);
        end
        fprintf(1, "GitHub could not convert %s (%s) - retrying\n", md, extractBefore(err.message + "]", "]") + "]");
        pause(5 * attempt);
    end
end
end

function MakeWritable(folder)
%Clear the read-only attribute on a folder and everything in it
if ispc
    fileattrib(folder, "+w", "", "s");
else
    fileattrib(folder, "+w", "a", "s");
end
end

function apidocTask(c)
% Generate the API reference Markdown pages (Docs/reference) from the help
% comments in the code. The doc task then converts them to HTML.

%Prototype - a few representative classes, plus every class in the
%namespaces listed
classNames = ["Palladium.Core.Instrument", ...
    "Palladium.Instruments.Keithley2000", ...
    "Palladium.Instruments.Lakeshore331", ...
    "Palladium.Utilities.PathUtils", ...
    NamespaceClasses("Palladium.Enums")];

outputFolder = c.Task.Outputs.Path;
if isfolder(outputFolder)
    rmdir(outputFolder, "s"); %Clear out pages for classes no longer documented
end

addpath(fullfile(c.Plan.RootFolder, "Tools"));
GenerateApiReference(classNames, outputFolder);
end

function names = NamespaceClasses(namespace)
%Names of all the classes in a namespace (not including nested namespaces)
ns = matlab.metadata.Namespace.fromName(namespace);
names = string({ns.ClassList.Name});
end

function EnsureDocMaker()
%Check the DocMaker add-on (https://github.com/mathworks/docmaker) is
%available. On GitHub Actions, install the pinned release below; locally,
%ask the user to install it rather than doing so behind their back.
%Update this tag to move CI onto a newer DocMaker release.
docMakerVersion = "v0.7";

if exist("docconvert", "file")
    return
end

assert(getenv("GITHUB_ACTIONS") == "true", "BuildFile:DocMakerMissing", ...
    "DocMaker not found. Install it from the Add-On Explorer, or from https://github.com/mathworks/docmaker/releases");

url = "https://github.com/mathworks/docmaker/releases/download/" + docMakerVersion + "/MATLAB_DocMaker.mltbx";
mltbx = fullfile(tempdir, "MATLAB_DocMaker.mltbx");
websave(mltbx, url);
matlab.addons.install(mltbx);
fprintf(1, "Installed DocMaker %s from %s\n", docMakerVersion, url);
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
opts.MaximumMatlabRelease = "";
opts.MinimumMatlabRelease = "R2026b";
opts.OutputFile = fullfile(projectRoot, "Release", "Toolbox", "PalladiumDAQ.mltbx");
opts.SupportedPlatforms.Win64 = true;
opts.SupportedPlatforms.Mac = true;
opts.SupportedPlatforms.Glnxa64 = true;
opts.SupportedPlatforms.MatlabOnline = true;
%Getting Started guide, shown from the Add-Ons manager. It is a plain-text
%live script (it must be .m or .mlx, not html) that links to the DocMaker
%docs' Docs/index.html
opts.ToolboxGettingStartedGuide = fullfile(opts.ToolboxFolder, "Docs", "GettingStarted.m");
opts.ToolboxVersion = string(verStruct.VersionString);

%Ship the generated documentation, but not its Markdown source
docFiles = startsWith(opts.ToolboxFiles, fullfile(opts.ToolboxFolder, "Docs"));
opts.ToolboxFiles(docFiles & endsWith(opts.ToolboxFiles, ".md")) = [];

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

%Retrieve version
verStruct = Palladium.ver();
verString = string(verStruct.VersionString);

%Set build options
buildOpts = AssembleBuildOptions(verString, projectRoot);
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
buildOpts = AssembleBuildOptions(verString, projectRoot);
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
packageOpts.AddRemoveProgramsIcon = fullfile(projectRoot, "Palladium DAQ", "+Palladium", "+Components", "Graphics", "PalladiumDAQIcon.png");
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

function buildOpts = AssembleBuildOptions(verString, projectRoot)

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
buildOpts.ExecutableSplashScreen = fullfile(projectRoot, "splash.png");
buildOpts.ExecutableVersion = verString;
buildOpts.ObfuscateArchive = false;
buildOpts.TreatInputsAsNumeric = false;
buildOpts.Verbose = true;

end