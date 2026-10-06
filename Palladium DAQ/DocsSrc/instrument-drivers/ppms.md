# Setting up the PPMS

The `PPMS` instrument controls a Quantum Design PPMS over the network, through the Quantum Design instrument server running on the PPMS's own control PC. It needs two .NET files on the computer running Palladium DAQ:

| File | Where it comes from |
| --- | --- |
| `QDInterface.dll` | Included with Palladium DAQ, and copied into your user files folder automatically |
| `QDInstrument.dll` | Quantum Design's driver. Its licence doesn't allow it to be distributed with Palladium DAQ, so you have to download it yourself |

The PPMS instrument only works on Windows.

## Installing the driver

1. Download `QDInstrument.dll` from Quantum Design's Pharos file management site. You need a Pharos account.
2. Put it in the `Instrument Drivers/Quantum Design/PPMS Communication` folder of your [user files folder](../installation.md), next to `QDInterface.dll`. Palladium DAQ creates this folder, and copies `QDInterface.dll` into it, when it starts.
3. Restart Palladium DAQ if it was already running.

Both files need to be in the same folder: Palladium DAQ loads `QDInterface.dll` from there, and that finds `QDInstrument.dll` next to it.

## Connecting

1. On the PPMS control PC, start the Quantum Design instrument server (see Quantum Design's documentation that comes with the driver).
2. In Palladium DAQ, add a `PPMS` instrument, and set its IP address to the PPMS control PC's address. The default port is 11000.

`Debug` (simulation) mode also needs both files, because the simulation runs inside Quantum Design's driver. No instrument server is needed for it.

## Troubleshooting

* **"The driver file QDInstrument.dll is missing"** - `QDInstrument.dll` isn't in the folder. The error message shows the exact folder to put it in.
* **"The built-in QDInterface.dll file is missing"** or **"Cannot find the PPMS Communication driver folder"** - restart Palladium DAQ, which creates the folder and copies `QDInterface.dll` back in.
