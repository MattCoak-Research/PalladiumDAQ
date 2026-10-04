# Presets and Config.json

Palladium DAQ has two kinds of settings file:

* **Presets** describe a measurement setup - which instruments to add and how to configure them, which Instrument Controls to turn on, and which plots to show. A lab typically keeps one preset per experiment or cryostat, so that everything is set up when Palladium DAQ starts.
* **Config.json** holds Palladium DAQ's own settings: default folders and file names, logging, the window size, and plot appearance.

Both are JSON text files, which can be edited in any text editor or in the MATLAB Editor.

## Presets

### Loading and saving

* **Save Preset** (under **⚙️ Settings**) saves the current setup as a preset - the easiest way to make one. Set up the instruments, controls and plots as you want them, then save.
* **Load Preset** (under **⚙️ Settings**) applies a preset file from anywhere.
* To apply a preset as Palladium DAQ starts, give its name (without `.json`) - it is looked for in the `Presets` folder of your [user files folder](installation.md):

```matlab
pd = Palladium(Preset="Example"); 
```

An `Example.json` is put in your `Presets` folder to start from.

### What a preset contains

```json
{
    "UpdateTime": 1,
    "Instruments": [
        {
            "Type": "Lakeshore350",
            "Properties": {
                "Name": "Cryostat",
                "Connection_Type": "GPIB",
                "GPIB_Address": 12,
                "Ch_A_Name": "1 K Pot Temp (K)",
                "Ch_C_Name": "Sample Stage Temp (K)"
            }
        },
        {
            "Type": "Keithley2410",
            "Properties": {
                "Connection_Type": "Debug",
                "MeasMode": "Current"
            },
            "Controls": [
                { "Name": "Sweep Control", "ControlName": "IV Sweep", "TabName": "IV Sweep" }
            ]
        }
    ],
    "PlottingTabs": [
        {
            "Row": 1,
            "Col": 2,
            "DefaultXAxis": ["Time (mins)", "Time (mins)"],
            "DefaultYAxes": [["1 K Pot Temp (K)", "Sample Stage Temp (K)"], ["Sample Stage Temp (K)"]]
        }
    ],
    "PlottingWindows": [
        {
            "Row": 1,
            "Col": 1,
            "DefaultXAxis": ["Time (mins)"],
            "DefaultYAxes": [["Sample Stage Temp (K)"]]
        }
    ]
}
```

| Key | Meaning |
| --- | --- |
| `UpdateTime` | Optional. The target update time, in seconds |
| `Instruments` | The instruments to add, in order. Each has: |
| &nbsp;&nbsp;`Type` | The instrument's class name, as in the Instruments list, e.g. `Keithley2410` |
| &nbsp;&nbsp;`Properties` | Optional. Settings to apply - any of the instrument's GUI-editable properties (see the [API reference](reference/index.md)). Text values for enumerations, such as `Connection_Type`, and for categorical settings, such as `MeasMode`, are converted. `Name` sets the instrument's name exactly, instead of the usual numbered name |
| &nbsp;&nbsp;`Controls` | Optional. Instrument Controls to turn on: either the control's name as text, or an object with `Name` and optionally `ControlName` and `TabName` |
| `PlottingTabs`, `PlottingWindows` | Optional. Plotting tabs and separate plotting windows to open. Each has: |
| &nbsp;&nbsp;`Row`, `Col` | The grid of plots, e.g. `Row` 2 and `Col` 2 for four plots |
| &nbsp;&nbsp;`DefaultXAxis` | The X axis of each plot, by column header, in reading order (along the first row, then the next) |
| &nbsp;&nbsp;`DefaultYAxes` | The Y axes of each plot - for each plot, a list of up to four column headers. Use `null` or `[]` to leave a plot unset |

The axes in a preset are applied when measurements start, since that is when the column headers are known. Instrument Controls, plotting tabs and plotting windows are only created when Palladium DAQ has a GUI.

## Config.json

Config.json is in the Palladium DAQ installation folder. It is created the first time Palladium DAQ runs, from the settings entered in the **Config Entry** window. By default, data, logs, sequences and user files all go in a `Palladium DAQ` folder in your Documents folder. If settings are missing from it - for example after an update adds new ones - they are added with default values, and a message says so. To use a different file, start Palladium DAQ with `Palladium(ConfigFilePath="OtherConfig.json")`.

### PathSettings

| Setting | Meaning |
| --- | --- |
| `UserFilesDirectory` | The folder where the `Palladium DAQ - User Files` folder is kept (presets, your own instruments) |
| `DefaultDirectory` | The default folder for data files |
| `DefaultFileName` | The default data file name. `<DATE>` is replaced with today's date |
| `DataFileExtension` | The data file extension, normally `.dat` |
| `FileWriteMode` | The default write mode: `Increment File No.`, `Append To File` or `Overwrite File` (see [GUI tour](gui-tour.md)) |
| `SaveFile` | Whether to write data files by default |
| `DefaultDescription` | The default data file description |
| `DefaultSequenceDirectory` | The folder where [sequences](sequences.md) are saved |
| `SequenceFileExtension` | The sequence file extension, normally `.seq` |
| `UserFilesDirectoryIsRelativePath`, `DataDirectoryIsRelativePath`, `SequenceDirectoryIsRelativePath` | If `true`, that folder is relative to the Palladium DAQ installation folder |

Folders that don't exist are created.

### LogSettings

Palladium DAQ's messages go to three places - the MATLAB Command Window, the GUI's status bar, and a log file - each with its own level. A message is shown in a place if it is at least as serious as that place's level: `Debug`, `Info`, `Warning` or `Error`, or `Off` to show nothing.

| Setting | Meaning |
| --- | --- |
| `CommandWindowMessageLevel` | Level for the Command Window |
| `GUIMessageLevel` | Level for the GUI |
| `LogFileMessageLevel` | Level for the log file |
| `LogFileDirectory`, `LogFileDirectoryIsRelativePath` | The folder for log files |
| `LogFileFileName` | The log file name. `<DATE>` is replaced with today's date, giving one log file per day |
| `PrintStackTraceInCommandWindow` | Whether to show the full stack trace of errors in the Command Window |
| `ErrorOnAllInstrumentErrors` | If `false` (the default), an instrument that fails to give a reading logs a warning and its columns are filled with NaN for that measurement, and measuring carries on. If `true`, measuring stops |

### WindowSettings

| Setting | Meaning |
| --- | --- |
| `DefaultSize` | The main window's size, `[width, height]` in pixels |
| `DefaultPosition` | Its position, `[left, bottom]` - leave empty (`[]`) to centre it |
| `Maximised` | Whether to start maximised |

### PlotterSettings

The appearance of the plots. Each plot shows up to four series, styled in order:

| Setting | Meaning |
| --- | --- |
| `Colours` | The series' colours, as RGB triples (values 0 to 1) one after another |
| `Markers` | The series' marker symbols, e.g. `["o","o","+","*"]` |
| `LineStyles` | The series' line styles, e.g. `"-"`, or `"None"` for markers only |
| `MarkerSize`, `LineWidth`, `FontSize` | Sizes |
| `ShowLegends` | Whether to show legends (only on the largest plots) |
