function TakeDocScreenshots(outputFolder, scenes)
%TAKEDOCSCREENSHOTS - Take the screenshots of Palladium DAQ's GUI used in the documentation.
%
%   TakeDocScreenshots(outputFolder) launches Palladium DAQ's windows with
%   simulated (Debug) instruments, sets each one up as a "scene", and saves
%   screenshots of them - cropped, highlighted and numbered - as PNG files
%   in outputFolder (DocsSrc/images/gui). Files are only rewritten if the
%   image has changed.
%
%   TakeDocScreenshots(outputFolder, scenes) takes only the named scenes,
%   e.g. "setup-tab".
%
%   This needs a display, so it is run by hand (buildtool screenshots) on a
%   developer's computer, not on CI - and the images are committed to git.
%   Everything Palladium DAQ writes while doing so goes in the git-ignored
%   work folder next to this file.
%
%   To add a screenshot: add a scene function below, and its name to
%   AllScenes. Refer to it in the docs as images/gui/<scene>.png.

arguments
    outputFolder (1,1) string
    scenes (1,:) string = AllScenes()
end

here = fileparts(mfilename("fullpath"));
addpath(here);
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

%Reading components inside Palladium's custom GUI components uses struct()
warningState = warning("off", "MATLAB:structOnObject");
restoreWarning = onCleanup(@() warning(warningState));

for scene = scenes
    fprintf(1, "Screenshot: %s\n", scene);
    work = PrepareWorkFolder(here);
    rng(1); %Same simulated data each time
    closeAll = onCleanup(@() CloseAllWindows());
    try
        feval("Scene_" + replace(scene, "-", "_"), fullfile(outputFolder, scene + ".png"), work);
    catch err
        warning("TakeDocScreenshots:SceneFailed", "Screenshot %s failed: %s", scene, err.message);
    end
    clear closeAll
end
end

function names = AllScenes()
names = ["main-window", "setup-tab", "instrument-settings", "plotting-tab", "sweep-control", ...
    "sequence-editor", "data-viewer", "config-entry"];
end

%% Scenes
% Each takes the output file and the work folder struct, sets up the
% windows, and calls Save (CaptureScreenshot).

function Scene_main_window(file, work)
[pd, app] = LaunchPalladium(work);
pd.AddInstrument("Keithley2000", ConnectionType="Debug");
pd.AddInstrument("Lakeshore331", ConnectionType="Debug");
DressMainWindow(app);
Save(app.PalladiumUIFigure, file, Highlights={app.GridLayout_TopMenuStrip, app.FilePathsPanel, ...
    app.StateControlPanel, app.TabGroup, app.StatusPanel});
end

function Scene_setup_tab(file, work)
[pd, app] = LaunchPalladium(work);
pd.AddInstrument("Keithley2000", ConnectionType="Debug");
pd.AddInstrument("Lakeshore331", ConnectionType="Debug");
DressMainWindow(app);
browser = Internals(app.InstrumentBrowserPanel);
options = Internals(app.InstrumentOptionsPanel);
Save(app.PalladiumUIFigure, file, Target=app.GridLayout5, Margin=2, Highlights={browser.InstrumentsListBox, ...
    browser.AddButton, browser.SelectedInstrumentsListBox, options.MainPanel, options.LowerPanel});
end

function Scene_instrument_settings(file, work)
[pd, app] = LaunchPalladium(work);
pd.AddInstrument("Keithley2410", ConnectionType="Debug");
Save(app.PalladiumUIFigure, file, Target=app.InstrumentOptionsPanel);
end

function Scene_plotting_tab(file, work)
%A preset adds the instruments and a plotting tab with its axes chosen,
%then a few seconds of simulated measurements fill the plots
WritePreset(work, "Screenshots", struct( ...
    "UpdateTime", 0.2, ...
    "Instruments", {{struct("Type", "Lakeshore331", "Properties", struct("Connection_Type", "Debug")), ...
                     struct("Type", "Keithley2000", "Properties", struct("Connection_Type", "Debug"))}}, ...
    "PlottingTabs", {{struct("Row", 2, "Col", 1, ...
        "DefaultXAxis", {{"Time (mins)", "Channel A Temperature (K)"}}, ...
        "DefaultYAxes", {{{"Channel A Temperature (K)", "Channel B Temperature (K)"}, {"K2000_1 - Resistance_Ohms"}}})}}));
[pd, app] = LaunchPalladium(work, Preset="Screenshots");
pd.Start();
pause(5);
pd.Stop();
SelectTab(app, "Plotting");
Save(app.PalladiumUIFigure, file, Target=app.TabGroup, Margin=2, Tolerance=0.08);
end

function Scene_sweep_control(file, work)
[pd, app] = LaunchPalladium(work);
k = pd.AddInstrument("Keithley2410", ConnectionType="Debug");
pd.AddInstrumentControl(k, "Sweep Control");
SelectTab(app, "Sweep");
Save(app.PalladiumUIFigure, file, Target=app.TabGroup, Margin=2);
end

function Scene_sequence_editor(file, work)
[pd, ~] = LaunchPalladium(work);
pd.AddInstrument("PPMS", ConnectionType="Debug");
pd.AddInstrument("Keithley2410", ConnectionType="Debug");
writelines(["Palladium Sequence File, Version [1.0]", "", "[WAIT] 1 min"], fullfile(work.Sequences, "Cooldown.seq"));
writelines(["Palladium Sequence File, Version [1.0]", "", "[WAIT] 1 min"], fullfile(work.Sequences, "Sample1 IV sweeps.seq"));

controller = Internals(pd).Controller;
controller.OpenSequenceEditor();
seqFig = FindFigure("Palladium Sequence Editor");
seqFig.Position(3:4) = [1300 800];
seqApp = seqFig.RunningAppInstance;
seqApp.SequenceEdit_TextArea.Value = ["% Measure at 10 K, then at 20 K"; "[INSTR] PPMS_1 : SetTemperature(10)"; ...
    "[WAIT] 10 min"; "[DATAFILE] 1 : C:\Data\Sample1_10K.dat"; "[INSTR] K2410_SrcMtr_1.Sweep Control : SweepRun()"; ...
    "[INSTR] PPMS_1 : SetTemperature(20)"; "[WAIT] 10 min"; "[DATAFILE] 1 : C:\Data\Sample1_20K.dat"; ...
    "[INSTR] K2410_SrcMtr_1.Sweep Control : SweepRun()"];
seqApp.TextArea.Value = "C:\Data\Sequences";
dataFileEntry = Internals(seqApp.SequenceEditor_ComEntry_DatafileCommand);
dataFileEntry.DirectoryTextArea.Value = "C:\Data";
nestedEntry = Internals(seqApp.SequenceEditor_ComEntry_RunSequenceCommand);
nestedEntry.FilePathTextArea.Value = "C:\Data\Sequences\Cooldown.seq";
Save(seqFig, file);
end

function Scene_data_viewer(file, work)
%Record a short simulated measurement to view
[pd, ~] = LaunchPalladium(work, View=[]);
pd.AddInstrument("Lakeshore331", ConnectionType="Debug");
pd.SetFileName("Sample1");
pd.SetUpdateTime(0.2);
pd.Start();
pause(4);
pd.Stop();

DataViewer("DefaultDir", work.Data, "FileExtensions", ".dat");
viewerFig = FindFigure("Data Viewer");
viewerFig.Position(3:4) = [1300 800];
viewer = viewerFig.RunningAppInstance;
viewer.TextArea.Value = "C:\Data";

%Tick the data file, and choose the axes to plot
nodes = findall(viewer.Tree, "Type", "uitreenode");
node = nodes(contains(string({nodes.Text}), "Sample1"));
viewer.Tree.CheckedNodes = node(1);
%Fire the tree's callback as a user's tick would
event = struct("CheckedNodes", node(1), "LeafCheckedNodes", node(1), "PreviousCheckedNodes", [], ...
    "PreviousLeafCheckedNodes", [], "Source", viewer.Tree, "EventName", "CheckedNodesChanged");
feval(viewer.Tree.CheckedNodesChangedFcn, viewer.Tree, event);
plotter = Internals(viewer.PlotterPanel);
SelectDropDown(plotter.XAxisDropDown, "Time (mins)");
SelectDropDown(plotter.YAxisDropDown_1, "Channel A Temperature (K)");
Save(viewerFig, file, Tolerance=0.08);
end

function Scene_config_entry(file, ~)
c = Palladium.Components.ConfigInputWindow();
root = fullfile("C:\Users\me\Documents", "Palladium DAQ");
c.SetInitialValues( ...
    "DefaultDataDirectory", fullfile(root, "Data"), "DefaultDataDirectoryIsRelativePath", false, ...
    "DefaultLogFileDirectory", fullfile(root, "Logs"), "DefaultLogFileDirectoryIsRelativePath", false, ...
    "DefaultSequenceDirectory", fullfile(root, "Sequences"), "DefaultSequenceDirectoryIsRelativePath", false, ...
    "DefaultFileName", "<DATE>_Filename", ...
    "UserFilesDirectory", root, "UserFilesDirectoryIsRelativePath", false, ...
    "WindowWidth", 1200, "WindowHeight", 900, "WindowStartsMaximised", true);
Save(FindFigure("Config Entry"), file);
delete(c);
end

%% Helpers

function work = PrepareWorkFolder(here)
%A clean work folder for Palladium DAQ's output, and a config file using it
%(the config path must be relative to the Palladium DAQ folder)
work.Root = fullfile(here, "work");
if isfolder(work.Root)
    %Palladium puts the user files folder on the path - take it off first
    workPaths = strsplit(genpath(work.Root), pathsep);
    onPath = ismember(workPaths, strsplit(path, pathsep));
    if any(onPath)
        rmpath(workPaths{onPath});
    end
    rmdir(work.Root, "s");
end
work.Data = fullfile(work.Root, "Data");
work.Sequences = fullfile(work.Root, "Sequences");
work.Presets = fullfile(work.Root, "Palladium DAQ - User Files", "Presets");
mkdir(work.Data);
mkdir(work.Sequences);
mkdir(work.Presets);

appDir = fileparts(which("Palladium"));
config = readstruct(fullfile(appDir, "Tests", "TestingConfig.json"));
relativeWork = "../Tools/DocScreenshots/work/";
config.LogSettings.LogFileDirectory = relativeWork + "Logs";
config.LogSettings.CommandWindowMessageLevel = "Warning";
config.LogSettings.GUIMessageLevel = "Warning";
config.LogSettings.ErrorOnAllInstrumentErrors = false;
config.PathSettings.DefaultDirectory = relativeWork + "Data";
config.PathSettings.DefaultSequenceDirectory = relativeWork + "Sequences";
config.PathSettings.UserFilesDirectory = relativeWork;
config.PathSettings.DefaultFileName = "Sample1";
config.WindowSettings.DefaultSize = [1260 860];
config.WindowSettings.Maximised = false;
writestruct(config, fullfile(work.Root, "ScreenshotConfig.json"), FileType="json");
work.ConfigFilePath = relativeWork + "ScreenshotConfig.json";
end

function [pd, app] = LaunchPalladium(work, options)
arguments
    work
    options.Preset = []
    options.View = "PalladiumDAQ_DefaultGUI"
end
pd = Palladium(ConfigFilePath=work.ConfigFilePath, Preset=options.Preset, View=options.View);
app = Internals(pd).View;
if ~isempty(app)
    app.PalladiumUIFigure.Position(3:4) = [1260 860];
    HideTestInstrument(app);
end
end

function HideTestInstrument(app)
%TestInstrument is for testing Palladium itself - leave it out of the
%documentation
list = Internals(app.InstrumentBrowserPanel).InstrumentsListBox;
keep = ~strcmp(list.Items, "TestInstrument");
if ~isempty(list.ItemsData)
    list.ItemsData = list.ItemsData(keep);
end
list.Items = list.Items(keep);
end

function DressMainWindow(app)
%Neutral data file settings, so the screenshots don't show a developer's
%own folders or today's date
paths = Internals(app.FilePathsPanel);
paths.DirectoryEditField.Value = "C:\Data";
paths.FileNameEditField.Value = "Sample1";
end

function SelectTab(app, titleContains)
tabs = app.TabGroup.Children;
tab = tabs(contains(string({tabs.Title}), titleContains));
app.TabGroup.SelectedTab = tab(1);
end

function SelectDropDown(dropDown, value)
if isempty(dropDown.ItemsData)
    dropDown.Value = value;
else
    dropDown.Value = dropDown.ItemsData(strcmp(dropDown.Items, value));
end
feval(dropDown.ValueChangedFcn, dropDown, struct("Value", dropDown.Value, "Source", dropDown));
end

function Save(fig, file, varargin)
if CaptureScreenshot(fig, file, varargin{:})
    fprintf(1, "[+] %s\n", file);
else
    fprintf(1, "[=] %s (unchanged)\n", file);
end
end

function s = Internals(obj)
%Properties of an object, including private ones (e.g. the controls inside
%Palladium's custom GUI components)
s = struct(obj);
end

function fig = FindFigure(name)
fig = findall(groot, "Type", "figure", "Name", name);
assert(~isempty(fig), "TakeDocScreenshots:WindowNotFound", "Window %s not found", name);
fig = fig(1);
end

function WritePreset(work, name, preset)
writelines(jsonencode(preset, PrettyPrint=true), fullfile(work.Presets, name + ".json"));
end

function CloseAllWindows()
%Stop Palladium's measurement timers, then close all its windows
delete(timerfindall);
figs = findall(groot, "Type", "figure");
for i = 1 : numel(figs)
    try
        delete(figs(i));
    catch
    end
end
end
