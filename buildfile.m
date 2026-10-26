function plan = buildfile
%BUILDFILE - Build plan for Palladium DAQ: code check, tests, documentation,
%toolbox packaging and standalone deployment. Run with buildtool <task>.
%How each step works is documented in Palladium DAQ/DocsSrc/developers/build-pipeline.md -
%update that page whenever this file (or Tools/, or the CI workflow) changes.
%Every hardcoded name, path and option lives in Settings, below - change
%values there, not in the tasks.

cfg = Settings();

plan = buildplan(localfunctions);
plan("test").Dependencies = "check";

%Documentation: Markdown sources in DocsSrc are built into Docs, which holds
%only generated files (HTML, help index, search database, Getting Started
%guide) and is what ships in the toolbox
docfolder = cfg.DocOutput;
plan("doc").Inputs = cfg.DocSource;
plan("doc").Outputs = [fullfile(docfolder,"**","*.html"), ... % output HTML
    fullfile(docfolder,"resources"), ... % stylesheets and scripts
    fullfile(docfolder,"*.xml"), ... % index files
    fullfile(docfolder,"helpsearch-v*")]; % search database folder
plan("doc").Dependencies = ["apidoc", "gettingStarted"];

%API reference Markdown, generated from the code into DocsSrc/reference
plan("apidoc").Inputs = [cfg.PalladiumFolder, cfg.ApiGeneratorFile];
plan("apidoc").Outputs = cfg.ApiReferenceFolder;

%Getting Started guide: built from its Markdown source, with the version from
%Palladium.m and the images it embeds - so rebuilt when any of those change
plan("gettingStarted").Inputs = [cfg.GettingStartedSource, ...
    cfg.MainFile, ...
    cfg.GettingStartedBuilderFile, ...
    cfg.SplashFile, ...
    cfg.GraphicsFolder];
plan("gettingStarted").Outputs = cfg.GettingStartedOutput;

%Screenshots of the GUI for the docs - run by hand (it needs a display), not
%part of doc or package, so not run on CI. The images are committed to git
plan("screenshots").Inputs = [GuiSourceFolders(cfg), ...
    fullfile(cfg.ScreenshotToolFolder, "TakeDocScreenshots.m"), ...
    fullfile(cfg.ScreenshotToolFolder, "CaptureScreenshot.m")];
plan("screenshots").Outputs = cfg.ScreenshotFolder;

plan("packageToolbox").Dependencies = ["test", "doc"];
plan("deploy").Dependencies = "packageToolbox";
plan("deployDebug").Dependencies = "test";

end

function cfg = Settings()
%SETTINGS - All the hardcoded names, paths and options used by the build, in
%one place. Paths are relative to the repo root, where the build runs.
%Cheap to call, so every task just calls it for itself.
%
%Some values are repeated in the GitHub Actions workflows, which can't read
%this file - keep them in step (marked "Also in" below).

%% Version
verStruct = Palladium.ver();
cfg.VerString = string(verStruct.VersionString);

%% Folders and files
cfg.AppFolder = "Palladium DAQ";
cfg.PalladiumFolder = fullfile(cfg.AppFolder, "+Palladium");
cfg.MainFile = fullfile(cfg.AppFolder, "Palladium.m");
cfg.ProjectFile = "PalladiumDAQ.prj";
cfg.ToolsFolder = "Tools";
cfg.SplashFile = "splash.png";
cfg.GraphicsFolder = fullfile(cfg.PalladiumFolder, "+Components", "Graphics");
cfg.IconFile = fullfile(cfg.GraphicsFolder, "PalladiumDAQIcon.png");
cfg.UnitTestFolder = fullfile(cfg.AppFolder, "Tests", "Unit Tests");
cfg.CheckFolders = [cfg.PalladiumFolder, fullfile(cfg.AppFolder, "Tests")];
cfg.DataViewerFile = fullfile(cfg.AppFolder, "DataViewer.mlapp");

%% Documentation
cfg.DocSource = fullfile(cfg.AppFolder, "DocsSrc");
cfg.DocOutput = fullfile(cfg.AppFolder, "Docs");
cfg.ApiReferenceFolder = fullfile(cfg.DocSource, "reference");
cfg.ScreenshotFolder = fullfile(cfg.DocSource, "images", "gui");
cfg.ScreenshotToolFolder = fullfile(cfg.ToolsFolder, "DocScreenshots");
cfg.ApiGeneratorFile = fullfile(cfg.ToolsFolder, "GenerateApiReference.m");
cfg.GettingStartedBuilderFile = fullfile(cfg.ToolsFolder, "BuildGettingStarted.m");
cfg.GettingStartedSource = fullfile(cfg.DocSource, "GettingStarted.md");
cfg.GettingStartedOutput = fullfile(cfg.DocOutput, "GettingStarted.m");
cfg.DocTheme = "light"; %Suits the Help browser
cfg.DocConvertAttempts = 3; %GitHub's Markdown API sometimes times out
cfg.DocConvertRetryPause = 5; %Seconds, times the attempt number
%DocMaker add-on (https://github.com/mathworks/docmaker), installed on CI
%from this pinned release. Update the tag to move CI onto a newer release.
cfg.DocMakerVersion = "v0.7";

%Classes in the API reference: some individually, whole namespaces, and every
%driver in the instruments folder except the scratch instrument
cfg.ApiClasses = "Palladium";
cfg.ApiNamespaces = ["Palladium.Core", "Palladium.Enums", "Palladium.Events", "Palladium.Instruments.Events", "Palladium.Utilities", "Palladium.DataWriting", "Palladium.Logging", "Palladium.PythonInstruments"];
cfg.InstrumentsNamespace = "Palladium.Instruments";
cfg.InstrumentsFolder = fullfile(cfg.PalladiumFolder, "+Instruments");
%A scratch driver for prototyping, left out of the docs, the toolbox and the
%standalone application
cfg.ScratchInstrument = "TestInstrument";

%% Toolbox
cfg.ToolboxOutput = fullfile("Release", "Toolbox", "PalladiumDAQ.mltbx"); %Also in release.yml
cfg.MinMatlabRelease = "R2026b";
cfg.MaxMatlabRelease = "";
cfg.SupportedPlatforms = struct(Win64=true, Mac=true, Glnxa64=true, MatlabOnline=true);

%% Authorship, used by the toolbox and the installers
cfg.AuthorName = "Matthew Coak";
cfg.AuthorCompany = "University of Birmingham";
cfg.AuthorEmail = "m.j.coak@bham.ac.uk";
cfg.Description = "Palladium Data Acquisition - an open source platform for laboratory instrument control, data acquisition logging and graphing. See https://github.com/MattCoak-Research/PalladiumDAQ for details.";

%% Standalone application and installers
cfg.ApplicationName = "Palladium DAQ";
cfg.ExecutableName = "PalladiumDAQ";
cfg.DebugExecutableName = "PalladiumDAQ_Debug";
cfg.BuildFolder = fullfile("Release", "Build");
cfg.DebugBuildFolder = fullfile("Release", "Debug Build");
cfg.PackageFolder = fullfile("Release", "Package");
cfg.InstallerSummary = "Laboratory instrument control, data acquisition and live plotting.";
cfg.InstallerNotes = "Updating from an earlier version? Close Palladium DAQ and uninstall the old version first (Settings > Apps > Installed apps), then run this installer. Your data and settings are kept. " ...
    + "The documentation is installed with the application: open it with the Help button in Palladium DAQ, or open Docs\index.html in the installation's application folder.";
%Installer variants: output subfolder (in PackageFolder), installer name and
%how the MATLAB Runtime is delivered. The web installer is the one released
%(Also in release.yml)
cfg.Installers = struct( ...
    Folder = ["Runtime Bundled", "Runtime Web Installer", "No Runtime"], ...
    Name = "Palladium DAQ Installer - " + ["Runtime Bundled", "Runtime Web Installer", "No Runtime"], ...
    RuntimeDelivery = ["installer", "web", "none"]);

%Files the application reads from disk at run time. Each is installed next
%to the executable under the name given here, and copied from its source
%folder (in the app folder) into the build folder first, so only the files
%wanted are installed. See deployTask for what each is for
cfg.InstallPythonCore = "PalladiumPythonCore";
cfg.InstallPresets = fullfile("ExamplesAndTemplates", "Presets");
cfg.InstallPythonTemplates = fullfile("ExamplesAndTemplates", "PythonInstruments");
cfg.InstallExamples = "ExamplesAndTemplates";
cfg.InstallGraphics = "Graphics";
cfg.InstallPython = "Python"; %Windows only
cfg.InstrumentDriversFolder = fullfile(cfg.AppFolder, "Instrument Drivers"); %Installed as it is

%Folders of classes that are only loaded by name at run time, which the
%compiler's dependency analysis can't find, so every file in them is added
%explicitly
cfg.CompilerFolders = [ ...
    fullfile(cfg.PalladiumFolder, "+Components"), ...
    fullfile(cfg.PalladiumFolder, "+Instruments"), ...
    fullfile(cfg.PalladiumFolder, "+Instruments", "+Controls"), ...
    fullfile(cfg.PalladiumFolder, "+Instruments", "+Events"), ...
    fullfile(cfg.PalladiumFolder, "+Enums"), ...
    fullfile(cfg.PalladiumFolder, "+Events"), ...
    fullfile(cfg.PalladiumFolder, "+Sequence", "+Views"), ...
    fullfile(cfg.PalladiumFolder, "+Views")];

%% Python bundled with the Windows standalone application
%Python's official "embeddable package", with the packages Python instruments
%need, and QCoDeS (the instrument drivers in the Instruments list). Versions
%are pinned and the download checked against its published SHA-256, so every
%build bundles exactly the same Python and packages. To update Python: pick a
%Python version supported by the minimum MATLAB release, and take its
%SHA-256 from python.org (the .spdx.json file next to the download)
cfg.Python.Version = "3.14.8";
cfg.Python.Sha256 = "a93abe456ab01bd96d7a085b3cdb6566b3063f4241360d114142fbdb07f0a310";
cfg.Python.Packages = ["pyvisa==1.16.2", "pyvisa-py==0.8.1", "pyserial==3.5", "typing_extensions==4.16.0"]; %With all their dependencies, as installed with --no-deps
cfg.Python.CacheFolder = fullfile(tempdir, "PalladiumDAQ build"); %Downloads are kept here between builds

%% QCoDeS bundled with that Python
%TO UPDATE THE QCoDeS THAT IS BUNDLED, CHANGE THESE TWO VERSIONS (the latest
%are at pypi.org/project/qcodes and pypi.org/project/qcodes-contrib-drivers),
%then run `buildtool bundledPython`: it builds the bundled Python and checks
%that the drivers can still be imported. If the check names a missing package,
%add it to QCoDeSDependencies. Users can always use a different QCoDeS by
%setting PythonSettings.PythonExecutable in the config to their own Python.
cfg.Python.QCoDeSVersion = "0.61.1";
cfg.Python.QCoDeSContribVersion = "0.25.0";

%The packages that QCoDeS and its contrib drivers import, pinned (installed
%with --no-deps). This is deliberately less than QCoDeS says it requires: the
%rest (matplotlib, xarray, h5py, pyarrow, Jupyter, ...) is only imported by
%QCoDeS's data and plotting features, which Palladium DAQ doesn't use, and is
%over 350 MB. The pins are what resolved when QCoDeS was last updated; after
%changing the QCoDeS versions, a newer QCoDeS may need newer versions of these
cfg.Python.QCoDeSDependencies = [ ...
    "numpy==2.5.4", "packaging==26.3", "uncertainties==3.2.3", "websockets==17.3", ... %Used by QCoDeS itself
    "jsonschema==4.26.0", "jsonschema-specifications==2025.9.1", "referencing==0.37.0", "rpds-py==2026.9.1", "attrs==26.1.0", "idna==3.20", ...
    "opentelemetry-api==1.45.1", ...
    "broadbean==0.15.0", "schema==0.7.8", ... %Tektronix AWG drivers
    "tqdm==4.70.1", "colorama==0.4.6", "cffi==2.1.1", "pycparser==3.11", ... %Some contrib drivers (Andor, Lighthouse Photonics, Advantech)
    "pandas==3.0.6", "python-dateutil==2.9.0.post0", "six==1.17.0", "tzdata==2026.5"]; %BlueFors and Triton, which are important to us

%Files deleted from the bundled packages (relative to Lib/site-packages).
%These two contrib drivers are GPL-2.0-or-later, unlike everything else
%bundled (MIT, BSD, Apache, PSF), so they are left out of the installers
cfg.Python.RemoveFiles = [ ...
    fullfile("qcodes_contrib_drivers", "drivers", "Tektronix", "AWG520.py"), ...
    fullfile("qcodes_contrib_drivers", "drivers", "Tektronix", "Keithley_2700.py")];

%Bundled packages whose wheels carry no licence file, which the check of the
%bundled Python warns about otherwise. Add a package here only after checking
%its licence allows bundling it (pyserial is BSD-3-Clause)
cfg.Python.NoLicenceFileOK = "pyserial-3.5";

%What the check of the bundled Python (CheckBundledPython) insists on: these
%drivers must import, and at least this many of the drivers in the
%Instruments list must (about 30 more need vendor packages, such as
%nidaqmx, that nobody bundles - the check lists them)
cfg.Python.RequiredDrivers = [ ...
    "qcodes.instrument_drivers.Keithley.Keithley_2450.Keithley2450", ...
    "qcodes.instrument_drivers.Lakeshore.Lakeshore_model_336.LakeshoreModel336", ...
    "qcodes.instrument_drivers.Lakeshore.Lakeshore_model_372.LakeshoreModel372", ...
    "qcodes.instrument_drivers.Keysight.Keysight_34465A_submodules.Keysight34465A", ...
    "qcodes_contrib_drivers.drivers.BlueFors.BlueFors.BlueFors", ...
    "qcodes_contrib_drivers.drivers.OxfordInstruments.Triton.Triton"];
cfg.Python.MinimumImportableDrivers = 250;
end

%% Tasks
function checkTask(~)
cfg = Settings();
issues = codeIssues(cfg.CheckFolders, IncludeSubfolders=true);
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
cfg = Settings();
results = runtests(cfg.UnitTestFolder, IncludeSubfolders=true);
assertSuccess(results);
end

function apidocTask(c)
% Generate the API reference Markdown pages (DocsSrc/reference) from the help
% comments in the code. The doc task then builds them into Docs/reference.
cfg = Settings();

%Classes listed individually, plus every class in the namespaces listed,
%plus every instrument driver in the +Instruments folder (not the scratch
%instrument, which is for prototyping)
classNames = [cfg.ApiClasses, ...
    NamespaceClasses(cfg.ApiNamespaces), ...
    FolderClasses(fullfile(c.Plan.RootFolder, cfg.InstrumentsFolder), cfg.InstrumentsNamespace, cfg.ScratchInstrument)];

outputFolder = c.Task.Outputs.Path;
if isfolder(outputFolder)
    rmdir(outputFolder, "s"); %Clear out pages for classes no longer documented
end

addpath(fullfile(c.Plan.RootFolder, cfg.ToolsFolder));
GenerateApiReference(classNames, outputFolder);
end

function gettingStartedTask(c)
% Build the toolbox's Getting Started guide, Docs/GettingStarted.m (a
% plain-text live script), from its Markdown source DocsSrc/GettingStarted.md,
% with the current version from Palladium.ver. The .m is generated and not
% under source control, like the HTML docs
cfg = Settings();
addpath(fullfile(c.Plan.RootFolder, cfg.ToolsFolder));
mdFile = c.Task.Inputs(1).Path;
mFile = c.Task.Outputs.Path;
BuildGettingStarted(mdFile, mFile, Palladium.ver().VersionString);
fprintf(1, "[+] %s (version %s)\n", mFile, Palladium.ver().VersionString);
end

function screenshotsTask(c)
% Take the GUI screenshots used in the docs (DocsSrc/images/gui), with
% Tools/DocScreenshots. Needs a display - run it by hand when the GUI
% changes, then review and commit the changed images
cfg = Settings();
addpath(fullfile(c.Plan.RootFolder, cfg.ScreenshotToolFolder));
outputFolder = c.Task.Outputs.Path;
TakeDocScreenshots(outputFolder);
writelines(GuiSourcesHash(cfg), fullfile(outputFolder, "gui-sources.sha256"));
end

function docTask(c)
% Build the HTML documentation in Docs from the Markdown sources in DocsSrc.
% DocMaker writes its output next to each .md, and the index and search
% database next to helptoc.md - so copy the sources into Docs, build them
% there, then remove the copies, leaving Docs with generated files only
cfg = Settings();
src = c.Task.Inputs.Path;
srcInfo = dir(src);
src = string(srcInfo(1).folder); % absolute path
[~, docFolderName] = fileparts(cfg.DocOutput);
out = fullfile(fileparts(src), docFolderName);

EnsureDocMaker(cfg);

%Start from an empty Docs, keeping only the Getting Started guide (built by
%the gettingStarted task) and the .gitkeep that keeps the folder in git
[~, gettingStartedGuide, gettingStartedExt] = fileparts(cfg.GettingStartedOutput);
ClearFolder(out, [gettingStartedGuide + gettingStartedExt, ".gitkeep"]);

WarnIfScreenshotsStale(fullfile(src, "images", "gui"), cfg);

%Copy in the sources - Markdown pages and the images they use - keeping
%their folder structure. GettingStarted.md is not a DocMaker page (see
%gettingStartedTask), and the screenshots' fingerprint file isn't needed
[~, gettingStartedSource, gettingStartedSourceExt] = fileparts(cfg.GettingStartedSource);
srcFiles = dir(fullfile(src, "**", "*.*"));
srcFiles([srcFiles.isdir] | strcmp({srcFiles.name}, gettingStartedSource + gettingStartedSourceExt) | endsWith({srcFiles.name}, ".sha256")) = [];
mdCopies = strings(1, 0);
for i = 1 : numel(srcFiles)
    destFolder = fullfile(out, extractAfter(string(srcFiles(i).folder), strlength(src)));
    if ~isfolder(destFolder)
        mkdir(destFolder);
    end
    dest = fullfile(destFolder, srcFiles(i).name);
    copyfile(fullfile(srcFiles(i).folder, srcFiles(i).name), dest);
    if endsWith(dest, ".md")
        if srcFiles(i).name == "index.md"
            %Fill in the version, so the page needn't show code to print it
            text = replace(fileread(dest, Encoding="UTF-8"), "{{version}}", ...
                Palladium.ver().VersionString);
            writelines(text, dest, Encoding="UTF-8");
        end
        mdCopies(end+1) = dest; %#ok<AGROW>
    end
end

%Convert one document at a time, so that a GitHub timeout only retries
%that document (see ConvertWithRetry)
html = strings(1, numel(mdCopies));
for i = 1 : numel(mdCopies)
    html(i) = ConvertWithRetry(mdCopies(i), out, cfg);
end
docrun(html(~contains(html, filesep + "reference" + filesep))) % run code and insert output - not in the generated API reference
docindex(out) % index - info.xml, helptoc.xml and search database
AddContentsLinks(html, out); % after indexing, to keep the links out of the search database

%Remove the Markdown copies
for i = 1 : numel(mdCopies)
    delete(mdCopies(i));
end
end

function packageToolboxTask(~)
cfg = Settings();

%Construct a toolbox options object to set parameters, and retrieve the
%build version
opts = matlab.addons.toolbox.ToolboxOptions(cfg.ProjectFile);

%Set various settings for the toolbox
opts.AuthorCompany = cfg.AuthorCompany;
opts.AuthorEmail = cfg.AuthorEmail;
opts.AuthorName = cfg.AuthorName;
opts.Description = cfg.Description;
opts.MaximumMatlabRelease = cfg.MaxMatlabRelease;
opts.MinimumMatlabRelease = cfg.MinMatlabRelease;
opts.OutputFile = cfg.ToolboxOutput;
opts.SupportedPlatforms.Win64 = cfg.SupportedPlatforms.Win64;
opts.SupportedPlatforms.Mac = cfg.SupportedPlatforms.Mac;
opts.SupportedPlatforms.Glnxa64 = cfg.SupportedPlatforms.Glnxa64;
opts.SupportedPlatforms.MatlabOnline = cfg.SupportedPlatforms.MatlabOnline;
%Getting Started guide, shown from the Add-Ons manager. It is a plain-text
%live script (it must be .m or .mlx, not html) that links to the DocMaker
%docs' Docs/index.html
opts.ToolboxGettingStartedGuide = fullfile(opts.ToolboxFolder, "Docs", "GettingStarted.m");
opts.ToolboxVersion = cfg.VerString;

%Ship the generated documentation, but not its Markdown source
opts.ToolboxFiles(startsWith(opts.ToolboxFiles, fullfile(opts.ToolboxFolder, "DocsSrc"))) = [];
docFiles = startsWith(opts.ToolboxFiles, fullfile(opts.ToolboxFolder, "Docs"));
opts.ToolboxFiles(docFiles & endsWith(opts.ToolboxFiles, ".md")) = []; %Any left by a failed doc build

%The scratch instrument is for prototyping, not shipped (it is left out of
%the standalone application too - see AssembleBuildOptions)
opts.ToolboxFiles(endsWith(opts.ToolboxFiles, fullfile("+Palladium", "+Instruments", cfg.ScratchInstrument + ".m"))) = [];

%Build the .mltbx toolbox installation file
matlab.addons.toolbox.packageToolbox(opts);
end

function deployDebugTask(~)
cfg = Settings();

%Define, then clear (ready to write to) output directory
exeDir = cfg.DebugBuildFolder;
if exist(exeDir, "dir")
    %Don't delete the exeDir, as we'd quite like to lazily keep the config
    %file in there..
    %   rmdir(exeDir, "s");
end

%Set build options
buildOpts = AssembleBuildOptions(cfg);
buildOpts.ExecutableName = cfg.ExecutableName;
buildOpts.OutputDir = exeDir;

BuildDebugStandalone(buildOpts, cfg);
end

function bundledPythonTask(~)
%Build the Python bundled with the Windows standalone application, with
%QCoDeS, in Release/Build/Python, and check that it can use QCoDeS. Run this
%after changing the bundled Python or QCoDeS versions in Settings - deploy
%does the same as part of building the installers, but takes far longer
cfg = Settings();
assert(ispc, "BuildFile:WindowsOnly", "The bundled Python is only part of the Windows standalone application.");
pythonDir = PrepareBundledPython(fullfile(cfg.BuildFolder, cfg.InstallPython), cfg);
CheckBundledPython(pythonDir, cfg);
end

function deployTask(~)
cfg = Settings();

%Define, then clear (ready to write to) output directory
exeDir = cfg.BuildFolder;
if exist(exeDir, "dir")
    rmdir(exeDir, "s");
end

%Define, then clear (ready to write to) output directory
packageDir = cfg.PackageFolder;
if exist(packageDir, "dir")
    rmdir(packageDir, "s");
end

%Set build options
buildOpts = AssembleBuildOptions(cfg);
buildOpts.ExecutableName = cfg.ExecutableName;
buildOpts.OutputDir = exeDir;

%Build the standalone .exe file (not yet the full installer) to the Build
%folder
buildResult = BuildStandalone(buildOpts);

%Build a debug version of the .exe which has a console window (just using
%the all platform version, on windows). This will not work for mac
%developers
if ispc
    BuildDebugStandalone(buildOpts, cfg);
end

% Create package options object, set package properties and package.
packageOpts = compiler.package.InstallerOptions(buildResult);
packageOpts.AddRemoveProgramsIcon = cfg.IconFile;
packageOpts.ApplicationName = cfg.ApplicationName;
packageOpts.AuthorName = cfg.AuthorName;
packageOpts.AuthorCompany = cfg.AuthorCompany;
packageOpts.InstallerIcon = cfg.IconFile;
packageOpts.InstallerSplash = cfg.SplashFile;
packageOpts.OutputDir = packageDir;
packageOpts.Version = cfg.VerString;
packageOpts.Verbose = true;
packageOpts.Summary = cfg.InstallerSummary;
packageOpts.Description = cfg.Description;
packageOpts.InstallationNotes = cfg.InstallerNotes;

%Files the application reads from disk at run time, rather than from its
%compiled archive, installed next to the executable in application/:
% - Docs: the HTML documentation (built by the doc task, which package
%   depends on), opened by Controller.OpenHelp
% - PalladiumPythonCore: the Python base class for Python instruments,
%   which Python imports from that folder. Only the .py files are
%   copied, leaving out __pycache__ and any MATLAB autosaves
% - Python (Windows only): a private copy of Python, with the packages
%   Python instruments need, which the application uses unless the user's
%   config names another (see Controller.SetUpPython)
% - ExamplesAndTemplates/Presets: Example.json, ExamplesAndTemplates/
%   PythonInstruments: the template Python instrument, and Instrument
%   Drivers: the PPMS interface DLL - all copied into the user files folder
%   on first run (see Controller.Initialise). The MATLAB template driver is
%   left out: the standalone application can't load MATLAB drivers written
%   after it is built
% - Graphics: the Palladium icon, for the windows (Controller's
%   WindowSettings.PalladiumIconPath)
pythonCoreDir = fullfile(exeDir, cfg.InstallPythonCore);
mkdir(pythonCoreDir);
copyfile(fullfile(cfg.AppFolder, cfg.InstallPythonCore, "*.py"), pythonCoreDir);
presetsDir = fullfile(exeDir, cfg.InstallPresets);
mkdir(presetsDir);
copyfile(fullfile(cfg.AppFolder, cfg.InstallPresets, "*.json"), presetsDir);
pythonTemplatesDir = fullfile(exeDir, cfg.InstallPythonTemplates);
mkdir(pythonTemplatesDir);
copyfile(fullfile(cfg.AppFolder, cfg.InstallPythonTemplates, "*.py"), pythonTemplatesDir);
graphicsDir = fullfile(exeDir, cfg.InstallGraphics);
mkdir(graphicsDir);
copyfile(cfg.IconFile, graphicsDir);
installFiles = [cfg.DocOutput, pythonCoreDir, fullfile(exeDir, cfg.InstallExamples), ...
    cfg.InstrumentDriversFolder, graphicsDir];
if ispc
    pythonDir = PrepareBundledPython(fullfile(exeDir, cfg.InstallPython), cfg);
    CheckBundledPython(pythonDir, cfg);
    installFiles(end+1) = pythonDir;
end
packageOpts.AdditionalFiles = cellstr(installFiles);

%Create the installer files
GenerateInstallers(packageOpts, buildResult, cfg);

end

%% Helper functions

function AddContentsLinks(html, out)
%Add a link back to the contents page (index.html) at the top of every other
%page. MATLAB's Help browser shows a contents sidebar, but a web browser -
%used for the docs installed with the standalone application - does not
indexPage = fullfile(out, "index.html");
for i = 1 : numel(html)
    if html(i) == indexPage
        continue
    end
    depth = count(extractAfter(html(i), strlength(out) + 1), filesep);
    href = join([repmat("..", 1, depth), "index.html"], "/");
    text = fileread(html(i), Encoding="UTF-8");
    text = replace(text, '<main class="markdown-body">', ...
        '<main class="markdown-body"><p><a href="' + href + '">&#8592; Palladium DAQ documentation contents</a></p>');
    writelines(text, html(i), Encoding="UTF-8");
end
end

function buildOpts = AssembleBuildOptions(cfg)

%The compiler excludes any code files it doesn't find an explicit mention
%of. Add those in here. Instrument files and dynamically loaded Views are
%good examples.
additionalFiles = GetAdditionalFilesFromFolders(cfg.CompilerFolders);

%Leave out the scratch instrument, for prototyping, not shipped
additionalFiles = RemoveAdditionalFiles(additionalFiles, ...
    fullfile(cfg.InstrumentsFolder, cfg.ScratchInstrument + ".m"));

%Set build options
buildOpts = compiler.build.StandaloneApplicationOptions(cfg.MainFile);
buildOpts.AdditionalFiles = additionalFiles;
buildOpts.AutoDetectDataFiles = true;
buildOpts.EmbedArchive = true;
buildOpts.ExecutableIcon = cfg.IconFile;
buildOpts.ExecutableSplashScreen = cfg.SplashFile;
buildOpts.ExecutableVersion = cfg.VerString;
buildOpts.ObfuscateArchive = false;
buildOpts.TreatInputsAsNumeric = false;
buildOpts.Verbose = true;

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

function BuildDebugStandalone(buildOpts, cfg)
buildOpts.ExecutableName = cfg.DebugExecutableName;
compiler.build.standaloneApplication(buildOpts);
end

function ClearFolder(folder, keep)
%Delete everything in a folder except the named files (at its top level).
%Clears the read-only attribute first - DocMaker (pre-0.8) copies its
%stylesheets and scripts from its read-only add-on install folder, and the
%copies keep that attribute
if ~isfolder(folder)
    mkdir(folder);
    return
end
MakeWritable(folder);
items = dir(folder);
items = items(~ismember({items.name}, [".", "..", keep]));
for i = 1 : numel(items)
    path = fullfile(items(i).folder, items(i).name);
    if items(i).isdir
        rmdir(path, "s");
    else
        delete(path);
    end
end
end

function html = ConvertWithRetry(md, root, cfg)
%Convert one Markdown document to HTML. DocMaker converts via GitHub's
%Markdown API, which sometimes times out (HTTP 502/503/504) - retry a few
%times before failing the build
maxAttempts = cfg.DocConvertAttempts;
for attempt = 1 : maxAttempts
    %Each docconvert call re-copies DocMaker's read-only stylesheets (see
    %docTask), so make any existing copies writable first
    if isfolder(fullfile(root, "resources"))
        MakeWritable(fullfile(root, "resources"));
    end

    try
        html = docconvert(md, Theme=cfg.DocTheme, Root=root);
        return
    catch err
        isServerError = contains(err.message, "HTTP/1.1 50" + ["2", "3", "4"]);
        if ~isServerError || attempt == maxAttempts
            rethrow(err);
        end
        fprintf(1, "GitHub could not convert %s (%s) - retrying\n", md, extractBefore(err.message + "]", "]") + "]");
        pause(cfg.DocConvertRetryPause * attempt);
    end
end
end

function EnsureDocMaker(cfg)
%Check the DocMaker add-on (https://github.com/mathworks/docmaker) is
%available. On GitHub Actions, install the pinned release (see Settings);
%locally, ask the user to install it rather than doing so behind their back.
docMakerVersion = cfg.DocMakerVersion;

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

function hash = FileSha256(file)
%SHA-256 of a file, as a lower-case hex string
%Uses the OS's own tool rather than Java, which newer MATLAB doesn't bundle
if ispc
    command = "certutil -hashfile """ + file + """ SHA256";
elseif ismac
    command = "shasum -a 256 """ + file + """";
else
    command = "sha256sum """ + file + """";
end
[status, output] = system(command);
hash = lower(string(regexp(output, "\<[0-9a-fA-F]{64}\>", "match", "once")));
assert(status == 0 && strlength(hash) == 64, "BuildFile:Sha256Failed", "%s", ...
    "Could not compute the SHA-256 of " + file + ":" + newline + string(output));
end

function names = FolderClasses(folder, namespace, exclude)
%Names of the classes defined by the .m files in one namespace folder (not
%its subfolders), leaving out the class names in exclude. Reads the folder
%rather than the namespace, which would also include any classes of the same
%namespace in a user files folder on the path
[~, classNames] = fileparts(string({dir(fullfile(folder, "*.m")).name}));
classNames = setdiff(classNames, exclude, "stable");
names = namespace + "." + classNames;
end

function GenerateInstallers(packageOpts, buildResult, cfg)
%Make an installer of each kind listed in Settings: with the MATLAB Runtime
%bundled, a web installer that downloads it, and one without it

directory = packageOpts.OutputDir;

% Download the MATLAB Runtime to include in the installer.
compiler.runtime.download;

for i = 1 : numel(cfg.Installers.Folder)
    packageOpts.RuntimeDelivery = cfg.Installers.RuntimeDelivery(i);
    packageOpts.OutputDir = fullfile(directory, cfg.Installers.Folder(i));
    packageOpts.InstallerName = cfg.Installers.Name(i);
    compiler.package.installer(buildResult, "Options", packageOpts);
end

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

function folders = GuiSourceFolders(cfg)
%Folders holding the GUI's code and layout (App Designer files)
folders = [fullfile(cfg.PalladiumFolder, "+Views"), ...
    fullfile(cfg.PalladiumFolder, "+Components"), ...
    fullfile(cfg.PalladiumFolder, "+Sequence", "+Views"), ...
    fullfile(cfg.PalladiumFolder, "+Instruments", "+Controls"), ...
    cfg.DataViewerFile];
end

function hash = GuiSourcesHash(cfg)
%SHA-256 fingerprint of the GUI source files, ignoring line endings (which
%git may change on checkout)
files = strings(0);
for folder = GuiSourceFolders(cfg)
    if isfile(folder)
        files(end+1) = folder; %#ok<AGROW>
    else
        listing = [dir(fullfile(folder, "*.m")); dir(fullfile(folder, "*.mlapp"))];
        files = [files, string(fullfile({listing.folder}, {listing.name}))]; %#ok<AGROW>
    end
end
allBytes = uint8([]);
for file = sort(files)
    fid = fopen(file, "r");
    bytes = fread(fid, Inf, "*uint8");
    fclose(fid);
    if endsWith(file, ".m")
        bytes(bytes == 13) = []; %Drop CRs
    end
    allBytes = [allBytes; bytes]; %#ok<AGROW>
end
combined = string(tempname);
cleanup = onCleanup(@() delete(combined));
fid = fopen(combined, "w");
fwrite(fid, allBytes, "uint8");
fclose(fid);
hash = FileSha256(combined);
end

function MakeWritable(folder)
%Clear the read-only attribute on a folder and everything in it
if ispc
    fileattrib(folder, "+w", "", "s");
else
    fileattrib(folder, "+w", "a", "s");
end
end


function names = NamespaceClasses(namespaces)
%Names of all the classes in each namespace (not including nested namespaces)
names = strings(1, 0);
for namespace = namespaces
    ns = matlab.metadata.Namespace.fromName(namespace);
    names = [names, string({ns.ClassList.Name})]; %#ok<AGROW>
end
end

function pythonDir = PrepareBundledPython(pythonDir, cfg)
%Build the Python bundled with the Windows standalone application in
%pythonDir: Python's official "embeddable package" (a self-contained Python
%that needs no installing), plus the packages Python instruments need.
%Versions are pinned, and the download checked against its published
%SHA-256, so every build bundles exactly the same Python (see Settings for
%how to update them)
pythonVersion = cfg.Python.Version;
pythonSha256 = cfg.Python.Sha256;
packages = [cfg.Python.Packages, ...
    "qcodes==" + cfg.Python.QCoDeSVersion, "qcodes-contrib-drivers==" + cfg.Python.QCoDeSContribVersion, cfg.Python.QCoDeSDependencies];

%Download, or reuse an earlier download, and check it
zipName = "python-" + pythonVersion + "-embed-amd64.zip";
cacheDir = cfg.Python.CacheFolder;
zipPath = fullfile(cacheDir, zipName);
if ~isfile(zipPath) || FileSha256(zipPath) ~= pythonSha256
    if ~isfolder(cacheDir)
        mkdir(cacheDir);
    end
    url = "https://www.python.org/ftp/python/" + pythonVersion + "/" + zipName;
    fprintf(1, "Downloading %s\n", url);
    websave(zipPath, url);
end
assert(FileSha256(zipPath) == pythonSha256, "BuildFile:PythonChecksumMismatch", "%s", ...
    "The SHA-256 of " + zipPath + " does not match the one expected for Python " + pythonVersion + ". Delete the file and try again.");

%Unpack it, and let Python find the packages in Lib\site-packages - the
%embeddable package's ._pth file fixes its search path, and doesn't
%include site-packages by default
if isfolder(pythonDir)
    rmdir(pythonDir, "s");
end
unzip(zipPath, pythonDir);
versionParts = split(pythonVersion, ".");
shortVersion = versionParts(1) + versionParts(2);   %e.g. 314
writelines(["python" + shortVersion + ".zip", ".", "Lib\site-packages"], fullfile(pythonDir, "python" + shortVersion + "._pth"));

%Install the packages with the build computer's Python (the one MATLAB
%uses, else python on the PATH): asking pip for packages (all binary wheels,
%no compiling) for the bundled Python's version and platform, so this works
%from any Python version. --no-compile because pip would compile them for
%the build computer's Python, which is no use to the bundled one (see below)
buildPython = string(pyenv().Executable);
if buildPython == ""
    buildPython = "python";
end
sitePackages = fullfile(pythonDir, "Lib", "site-packages");
command = """" + buildPython + """ -m pip install --disable-pip-version-check --no-deps --only-binary=:all: --no-compile" ...
    + " --platform win_amd64 --implementation cp --python-version " + versionParts(1) + "." + versionParts(2) ...
    + " --target """ + sitePackages + """ " + join(packages, " ");
[status, output] = system(command);
assert(status == 0, "BuildFile:PipInstallFailed", "%s", "Installing the bundled Python's packages failed:" + newline + string(output));

%Delete the files that mustn't be bundled (see Settings), and the scripts
%folder that pip puts the packages' command line tools in
for file = cfg.Python.RemoveFiles
    assert(isfile(fullfile(sitePackages, file)), "BuildFile:RemoveFileNotFound", "%s", ...
        "Expected to find " + file + " in the bundled Python's packages, to remove it - has a QCoDeS update moved it? Update cfg.Python.RemoveFiles.");
    delete(fullfile(sitePackages, file));
end
if isfolder(fullfile(sitePackages, "bin"))
    rmdir(fullfile(sitePackages, "bin"), "s");
end

%Delete the packages' own test suites (the folders called tests or test
%inside each package: pandas's and numpy's are about 50 MB), which nothing
%imports when running
allEntries = dir(fullfile(sitePackages, "**", "*"));
isTestFolder = [allEntries.isdir] & ismember(string({allEntries.name}), ["tests", "test"]) & string({allEntries.folder}) ~= string(sitePackages);
for entry = reshape(allEntries(isTestFolder), 1, [])
    testFolder = fullfile(entry.folder, entry.name);
    if isfolder(testFolder)     %Not already deleted with a parent
        rmdir(testFolder, "s");
    end
end
assert(~isempty(allEntries(isTestFolder)), "BuildFile:NoTestFolders", "Expected to find test folders to delete in the bundled Python's packages - has the way they are found stopped working?");

%Compile the packages to bytecode, with the bundled Python itself, so that
%importing them (QCoDeS is slow to import without) doesn't compile them every
%time Palladium DAQ starts: the installation folder may not be writable, so
%Python couldn't save what it compiled. Unchecked hashes, because the
%installer may change the files' dates, which would make Python think the
%bytecode was out of date
bundledPython = fullfile(pythonDir, "python.exe");
[status, output] = system("""" + bundledPython + """ -m compileall -q --invalidation-mode unchecked-hash """ + sitePackages + """");
assert(status == 0, "BuildFile:CompileFailed", "%s", "Compiling the bundled Python's packages failed:" + newline + string(output));
fprintf(1, "Bundled Python %s, with %s\n", pythonVersion, join(packages, ", "));
end

function CheckBundledPython(pythonDir, cfg)
%Check that the bundled Python can use QCoDeS, by running Tools/CheckBundledPython.py
%with it: the QCoDeS drivers in cfg.Python.RequiredDrivers must import, at
%least cfg.Python.MinimumImportableDrivers of all the drivers in the
%Instruments list must, and a driver must be able to run with no instrument
%(which Debug mode and the Parameters tab depend on). Errors if not. Lists the
%drivers that don't import, grouped by the package they are missing, so
%that after a QCoDeS update the maintainer can decide whether to bundle it
resultFile = tempname + ".json";
settingsFile = tempname + ".json";
cleanup = onCleanup(@() delete([resultFile, settingsFile]));
writelines(jsonencode(struct("RequiredDrivers", cfg.Python.RequiredDrivers)), settingsFile);

command = """" + fullfile(pythonDir, "python.exe") + """ """ + fullfile(cfg.ToolsFolder, "CheckBundledPython.py") + """" ...
    + " """ + fullfile(pwd, cfg.AppFolder) + """ """ + settingsFile + """ """ + resultFile + """";
[status, output] = system(command);
assert(status == 0 && isfile(resultFile), "BuildFile:BundledPythonCheckFailed", "%s", "The check of the bundled Python did not run:" + newline + string(output));
result = jsondecode(fileread(resultFile));

fprintf(1, "Bundled Python check: %d QCoDeS drivers in the Instruments list, %d import.\n", result.Entries, result.Importable);
for missing = reshape(result.MissingPackages, 1, [])
    fprintf(1, "  %d need %s\n", missing.Count, string(missing.Name));
end
noLicenceFile = strings(0, 1);
if ~isempty(result.PackagesWithoutLicence)
    noLicenceFile = setdiff(string(result.PackagesWithoutLicence), cfg.Python.NoLicenceFileOK);
end
if ~isempty(noLicenceFile)
    warning("BuildFile:BundledLicenceMissing", "%s", "These bundled packages have no licence file, so check their licences allow bundling, then add them to cfg.Python.NoLicenceFileOK: " + join(noLicenceFile, ", "));
end

assert(isempty(result.RequiredFailed), "BuildFile:RequiredDriverFailed", "%s", ...
    "These QCoDeS drivers must import in the bundled Python, but don't: " + join(string(result.RequiredFailed), "; ") + ". Add the package they need to cfg.Python.QCoDeSDependencies.");
assert(result.Importable >= cfg.Python.MinimumImportableDrivers, "BuildFile:TooFewDrivers", "%s", ...
    "Only " + result.Importable + " QCoDeS drivers import in the bundled Python, fewer than the " + cfg.Python.MinimumImportableDrivers + " expected. See the list above for the packages they need, and add them to cfg.Python.QCoDeSDependencies.");
assert(result.OfflineWorks, "BuildFile:OfflineDriverFailed", "%s", "A QCoDeS driver can't run with no instrument in the bundled Python: " + string(result.OfflineMessage));
end

function filePathsStrArray = RemoveAdditionalFiles(strIn, stringsToRemove)
filePathsStrArray = strIn;
for i = 1 : length(stringsToRemove)
    idx = strcmp(strIn,stringsToRemove(i));
    filePathsStrArray(idx) = [];
end
end


function WarnIfScreenshotsStale(imagesFolder, cfg)
%Warn (but don't fail) if the GUI has changed since the screenshots were
%taken - they can only be retaken on a computer with a display
hashFile = fullfile(imagesFolder, "gui-sources.sha256");
if ~isfile(hashFile)
    return
end
try
    if strtrim(string(fileread(hashFile))) ~= GuiSourcesHash(cfg)
        warning("BuildFile:ScreenshotsStale", "%s", "The GUI has changed since the documentation's screenshots were taken. " + ...
            "Run ""buildtool screenshots"" on a computer with a display, then review and commit the changed images.");
    end
catch err
    fprintf(1, "Could not check whether the screenshots are up to date: %s\n", err.message);
end
end
