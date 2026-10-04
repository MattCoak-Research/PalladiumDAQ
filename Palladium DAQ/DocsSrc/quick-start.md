# Getting started

This page takes you through a first measurement with a simulated instrument, so no hardware is needed. It assumes Palladium DAQ is [installed](installation.md) as a MATLAB toolbox.

## 1. Launch Palladium DAQ

Type this in the MATLAB Command Window:

```matlab
Palladium 
```

The first time it runs, Palladium DAQ asks where to keep your data, logs, sequences and user files (see [Installation](installation.md)). Then the main window opens on the **⚙️ Setup** tab.

## 2. Add an instrument

The **Instruments** list on the left shows every instrument driver available. Select **Keithley2000** and press **Add >** (or double-click it). It appears in the **Selected Instruments** list.

![The Setup tab, with instruments added](images/gui/setup-tab.png)

Select it there to see its settings in the **Instrument Settings** panel. Its **Name** is `K2000_1` - the name used in its data columns and in [sequences](sequences.md). Set **Connection_Type** to **Debug**: the instrument then runs in simulation mode and produces made-up readings, instead of talking to real hardware. With real hardware you would choose the connection (GPIB, Serial, ...) and fill in its address here instead.

## 3. Choose where to save the data

The panel at the top of the window sets the data file: its **Directory**, **File Name** and a **Description** that is written into the file's header. `<DATE>` in the file name is replaced with today's date. Leave **Write to File** ticked, and leave the mode on **Increment File No.**, so that each run gets a new numbered file instead of overwriting the last one.

## 4. Start measuring

Press **Start**. Palladium DAQ connects to the instrument, writes the file's header, and then takes a reading every **Target update time** seconds, adding each one as a new line in the data file.

Because there is no plot yet, a **📈 Plotting** tab with two plots is added. In a plot, choose **Time (mins)** as the **X Axis** and `K2000_1 - Resistance_Ohms` as the first **Y Axes** entry to watch the readings arrive. The **New 📈 Tab** and **New 📈 Window** buttons at the top add more plots in tabs or separate windows.

![A plotting tab during a measurement](images/gui/plotting-tab.png)

Press **Pause** to stop taking readings for a while (it becomes **Resume**), and **Stop** to finish. The data file is complete as soon as each line is written, so nothing is lost if MATLAB closes unexpectedly.

## 5. Look at the data

Press **🔍 Data Viewer** to browse and plot saved data files, or load one into MATLAB as described in [Data files](data-files.md).

## The same thing from a script

Everything in the GUI can also be done from code. `Palladium` returns an object to control it with:

```matlab
pd = Palladium();
pd.AddInstrument("Keithley2000", ConnectionType="Debug");
pd.SetDirectory("C:\Data");
pd.SetFileName("<DATE>_FirstTest");
pd.Start();
% ... later
pd.Stop(); 
```

Passing `View=[]` runs Palladium DAQ with no GUI at all. See the [API reference](reference/index.md) for the instrument classes, and `help Palladium` for all the methods of the Palladium object.

## Next steps

* Save your setup as a [Preset](presets-and-config.md), so it is ready next time
* Automate a measurement run with a [Sequence](sequences.md)
* Add your own hardware: [Writing an instrument driver](writing-instruments.md)
