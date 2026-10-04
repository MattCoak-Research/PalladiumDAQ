function plan = buildfile
%BUILDFILE - Build plan for Palladium DAQ: code check, tests, documentation,
%toolbox packaging and standalone deployment. Run with buildtool <task>.
%How each step works is documented in Palladium DAQ/DocsSrc/developers/build-pipeline.md -
%update that page whenever this file (or Tools/, or the CI workflow) changes.

plan = buildplan(localfunctions);
plan("test").Dependencies = "check";

%Documentation: Markdown sources in DocsSrc are built into Docs, which holds
%only generated files (HTML, help index, search database, Getting Started
%guide) and is what ships in the toolbox
docsrc = fullfile("Palladium DAQ", "DocsSrc");
docfolder = fullfile("Palladium DAQ", "Docs");
plan("doc").Inputs = docsrc;
plan("doc").Outputs = [fullfile(docfolder,"**","*.html"), ... % output HTML
    fullfile(docfolder,"resources"), ... % stylesheets and scripts
    fullfile(docfolder,"*.xml"), ... % index files
    fullfile(docfolder,"helpsearch-v*")]; % search database folder
plan("doc").Dependencies = ["apidoc", "gettingStarted"];

%API reference Markdown, generated from the code into DocsSrc/reference
plan("apidoc").Inputs = [fullfile("Palladium DAQ", "+Palladium"), fullfile("Tools", "GenerateApiReference.m")];
plan("apidoc").Outputs = fullfile(docsrc, "reference");

%Getting Started guide: built from its Markdown source, with the version from
%Palladium.m and the images it embeds - so rebuilt when any of those change
plan("gettingStarted").Inputs = [fullfile(docsrc, "GettingStarted.md"), ...
    fullfile("Palladium DAQ", "Palladium.m"), ...
    fullfile("Tools", "BuildGettingStarted.m"), ...
    "splash.png", ...
    fullfile("Palladium DAQ", "+Palladium", "+Components", "Graphics")];
plan("gettingStarted").Outputs = fullfile(docfolder, "GettingStarted.m");

%Screenshots of the GUI for the docs - run by hand (it needs a display), not
%part of doc or package, so not run on CI. The images are committed to git
plan("screenshots").Inputs = [GuiSourceFolders(), ...
    fullfile("Tools", "DocScreenshots", "TakeDocScreenshots.m"), ...
    fullfile("Tools", "DocScreenshots", "CaptureScreenshot.m")];
plan("screenshots").Outputs = fullfile(docsrc, "images", "gui");

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
% Build the HTML documentation in Docs from the Markdown sources in DocsSrc.
% DocMaker writes its output next to each .md, and the index and search
% database next to helptoc.md - so copy the sources into Docs, build them
% there, then remove the copies, leaving Docs with generated files only
src = c.Task.Inputs.Path;
srcInfo = dir(src);
src = string(srcInfo(1).folder); % absolute path
out = fullfile(fileparts(src), "Docs");

EnsureDocMaker();

%Start from an empty Docs, keeping only the Getting Started guide (built by
%the gettingStarted task) and the .gitkeep that keeps the folder in git
ClearFolder(out, ["GettingStarted.m", ".gitkeep"]);

WarnIfScreenshotsStale(fullfile(src, "images", "gui"));

%Copy in the sources - Markdown pages and the images they use - keeping
%their folder structure. GettingStarted.md is not a DocMaker page (see
%gettingStartedTask), and the screenshots' fingerprint file isn't needed
srcFiles = dir(fullfile(src, "**", "*.*"));
srcFiles([srcFiles.isdir] | strcmp({srcFiles.name}, "GettingStarted.md") | endsWith({srcFiles.name}, ".sha256")) = [];
mdCopies = strings(1, 0);
for i = 1 : numel(srcFiles)
    destFolder = fullfile(out, extractAfter(string(srcFiles(i).folder), strlength(src)));
    if ~isfolder(destFolder)
        mkdir(destFolder);
    end
    dest = fullfile(destFolder, srcFiles(i).name);
    copyfile(fullfile(srcFiles(i).folder, srcFiles(i).name), dest);
    if endsWith(dest, ".md")
        mdCopies(end+1) = dest; %#ok<AGROW>
    end
end

%Convert one document at a time, so that a GitHub timeout only retries
%that document (see ConvertWithRetry)
html = strings(1, numel(mdCopies));
for i = 1 : numel(mdCopies)
    html(i) = ConvertWithRetry(mdCopies(i), out);
end
docrun(html(~contains(html, filesep + "reference" + filesep))) % run code and insert output - not in the generated API reference
docindex(out) % index - info.xml, helptoc.xml and search database
AddContentsLinks(html, out); % after indexing, to keep the links out of the search database

%Remove the Markdown copies
for i = 1 : numel(mdCopies)
    delete(mdCopies(i));
end
end

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

function screenshotsTask(c)
% Take the GUI screenshots used in the docs (DocsSrc/images/gui), with
% Tools/DocScreenshots. Needs a display - run it by hand when the GUI
% changes, then review and commit the changed images
addpath(fullfile(c.Plan.RootFolder, "Tools", "DocScreenshots"));
outputFolder = c.Task.Outputs.Path;
TakeDocScreenshots(outputFolder);
writelines(GuiSourcesHash(), fullfile(outputFolder, "gui-sources.sha256"));
end

function folders = GuiSourceFolders()
%Folders holding the GUI's code and layout (App Designer files)
folders = [fullfile("Palladium DAQ", "+Palladium", "+Views"), ...
    fullfile("Palladium DAQ", "+Palladium", "+Components"), ...
    fullfile("Palladium DAQ", "+Palladium", "+Sequence", "+Views"), ...
    fullfile("Palladium DAQ", "+Palladium", "+Instruments", "+Controls"), ...
    fullfile("Palladium DAQ", "DataViewer.mlapp")];
end

function hash = GuiSourcesHash()
%SHA-256 fingerprint of the GUI source files, ignoring line endings (which
%git may change on checkout)
files = strings(0);
for folder = GuiSourceFolders()
    if isfile(folder)
        files(end+1) = folder; %#ok<AGROW>
    else
        listing = [dir(fullfile(folder, "*.m")); dir(fullfile(folder, "*.mlapp"))];
        files = [files, string(fullfile({listing.folder}, {listing.name}))]; %#ok<AGROW>
    end
end
digest = java.security.MessageDigest.getInstance("SHA-256");
for file = sort(files)
    fid = fopen(file, "r");
    bytes = fread(fid, Inf, "*uint8");
    fclose(fid);
    if endsWith(file, ".m")
        bytes(bytes == 13) = []; %Drop CRs
    end
    digest.update(typecast(bytes, "int8"));
end
hash = string(sprintf("%02x", typecast(digest.digest(), "uint8")));
end

function WarnIfScreenshotsStale(imagesFolder)
%Warn (but don't fail) if the GUI has changed since the screenshots were
%taken - they can only be retaken on a computer with a display
hashFile = fullfile(imagesFolder, "gui-sources.sha256");
if ~isfile(hashFile)
    return
end
try
    if strtrim(string(fileread(hashFile))) ~= GuiSourcesHash()
        warning("BuildFile:ScreenshotsStale", "%s", "The GUI has changed since the documentation's screenshots were taken. " + ...
            "Run ""buildtool screenshots"" on a computer with a display, then review and commit the changed images.");
    end
catch err
    fprintf(1, "Could not check whether the screenshots are up to date: %s\n", err.message);
end
end

function gettingStartedTask(c)
% Build the toolbox's Getting Started guide, Docs/GettingStarted.m (a
% plain-text live script), from its Markdown source DocsSrc/GettingStarted.md,
% with the current version from Palladium.ver. The .m is generated and not
% under source control, like the HTML docs
addpath(fullfile(c.Plan.RootFolder, "Tools"));
mdFile = c.Task.Inputs(1).Path;
mFile = c.Task.Outputs.Path;
BuildGettingStarted(mdFile, mFile, Palladium.ver().VersionString);
fprintf(1, "[+] %s (version %s)\n", mFile, Palladium.ver().VersionString);
end

function apidocTask(c)
% Generate the API reference Markdown pages (DocsSrc/reference) from the help
% comments in the code. The doc task then builds them into Docs/reference.

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

function pythonDir = PrepareBundledPython(pythonDir)
%Build the Python bundled with the Windows standalone application in
%pythonDir: Python's official "embeddable package" (a self-contained Python
%that needs no installing), plus the packages Python instruments need.
%Versions are pinned, and the download checked against its published
%SHA-256, so every build bundles exactly the same Python. To update: pick a
%Python version supported by the minimum MATLAB release, and take its
%SHA-256 from python.org (the .spdx.json file next to the download)
pythonVersion = "3.14.8";
pythonSha256 = "a93abe456ab01bd96d7a085b3cdb6566b3063f4241360d114142fbdb07f0a310";
packages = ["pyvisa==1.16.2", "pyvisa-py==0.8.1", "pyserial==3.5", "typing_extensions==4.16.0"]; %With all their dependencies, as installed with --no-deps

%Download, or reuse an earlier download, and check it
zipName = "python-" + pythonVersion + "-embed-amd64.zip";
cacheDir = fullfile(tempdir, "PalladiumDAQ build");
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
%uses, else python on the PATH). They are pure Python, so this works from
%any Python version - asking pip for packages for the bundled Python's
%version and platform
buildPython = string(pyenv().Executable);
if buildPython == ""
    buildPython = "python";
end
sitePackages = fullfile(pythonDir, "Lib", "site-packages");
command = """" + buildPython + """ -m pip install --disable-pip-version-check --no-deps --only-binary=:all:" ...
    + " --platform win_amd64 --implementation cp --python-version " + versionParts(1) + "." + versionParts(2) ...
    + " --target """ + sitePackages + """ " + join(packages, " ");
[status, output] = system(command);
assert(status == 0, "BuildFile:PipInstallFailed", "%s", "Installing the bundled Python's packages failed:" + newline + string(output));
fprintf(1, "Bundled Python %s, with %s\n", pythonVersion, join(packages, ", "));
end

function hash = FileSha256(file)
%SHA-256 of a file, as a lower-case hex string
fid = fopen(file, "r");
bytes = fread(fid, Inf, "*uint8");
fclose(fid);
digest = java.security.MessageDigest.getInstance("SHA-256");
digest.update(typecast(bytes, "int8"));
hash = string(sprintf("%02x", typecast(digest.digest(), "uint8")));
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
opts.ToolboxFiles(startsWith(opts.ToolboxFiles, fullfile(opts.ToolboxFolder, "DocsSrc"))) = [];
docFiles = startsWith(opts.ToolboxFiles, fullfile(opts.ToolboxFolder, "Docs"));
opts.ToolboxFiles(docFiles & endsWith(opts.ToolboxFiles, ".md")) = []; %Any left by a failed doc build

%TestInstrument is for testing Palladium itself, not for users (it is left
%out of the standalone application too - see AssembleBuildOptions)
opts.ToolboxFiles(endsWith(opts.ToolboxFiles, fullfile("+Palladium", "+Instruments", "TestInstrument.m"))) = [];

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
packageOpts.Summary = "Laboratory instrument control, data acquisition and live plotting.";
packageOpts.Description = "Palladium Data Acquisition - an open source platform for laboratory instrument control, data acquisition logging and graphing. See https://github.com/MattCoak-Research/PalladiumDAQ for details.";
packageOpts.InstallationNotes = "Updating from an earlier version? Close Palladium DAQ and uninstall the old version first (Settings > Apps > Installed apps), then run this installer. Your data and settings are kept. " ...
    + "The documentation is installed with the application: open it with the Help button in Palladium DAQ, or open Docs\index.html in the installation's application folder.";

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
pythonCoreDir = fullfile(exeDir, "PalladiumPythonCore");
mkdir(pythonCoreDir);
copyfile(fullfile(projectRoot, "Palladium DAQ", "PalladiumPythonCore", "*.py"), pythonCoreDir);
installFiles = [fullfile(projectRoot, "Palladium DAQ", "Docs"), pythonCoreDir];
if ispc
    installFiles(end+1) = PrepareBundledPython(fullfile(exeDir, "Python"));
end
packageOpts.AdditionalFiles = cellstr(installFiles);

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