# CheckBundledPython.py
"""Check that the Python bundled with the Windows application can use QCoDeS.

Run by the build (buildfile.m, CheckBundledPython) with the bundled python.exe:

    python.exe CheckBundledPython.py <Palladium DAQ folder> <settings .json> <result .json>

It imports every QCoDeS driver that Palladium DAQ lists in its Instruments
list (QCoDeSCatalog), checks that the drivers in the settings' RequiredDrivers
import, that a driver can run with no instrument (what Debug mode and the
Parameters tab depend on), and that each bundled package has a licence file.
The results are written as JSON to the result file, for the build to judge.
"""
import importlib
import json
import os
import re
import sys

sys.dont_write_bytecode = True      # The bundled Python's folder is for installing, not for running in

app_folder, settings_path, result_path = sys.argv[1:4]
sys.path.insert(0, app_folder)      # For PalladiumPythonCore
settings = json.load(open(settings_path))

from PalladiumPythonCore import QCoDeSCatalog
from PalladiumPythonCore.QCoDeSInstrument import QCoDeSGeneric

catalog = QCoDeSCatalog.build_catalog()


def try_import(class_path):
    """None if the class imports, otherwise why not."""
    module, _, name = class_path.rpartition(".")
    try:
        getattr(importlib.import_module(module), name)
        return None
    except BaseException as e:
        return f"{type(e).__name__}: {e}"


def what_is_missing(message):
    """The package a failed import was missing, or the start of the message if it wasn't a missing package."""
    found = re.search(r"No module named '([^']+)'", message)
    return found.group(1).split(".")[0] if found else message.splitlines()[0][:70]


failures = {}
for entry in catalog:
    message = try_import(entry["class_path"])
    if message:
        failures[entry["entry"]] = message

missing = {}
for message in failures.values():
    package = what_is_missing(message)
    missing[package] = missing.get(package, 0) + 1

required_failed = []
for class_path in settings["RequiredDrivers"]:
    message = try_import(class_path)
    if message:
        required_failed.append(f"{class_path} ({message[:80]})")

# A driver must be able to run with no instrument: Debug mode and the Parameters tab depend on it
offline_works, offline_message = True, ""
try:
    generic = QCoDeSGeneric()
    generic.configure("qcodes.instrument_drivers.Keithley.Keithley_2450.Keithley2450")
    listing = json.loads(generic.available_parameters_json())
    if not generic.SupportsSimulation or len(listing) < 10:
        offline_works, offline_message = False, f"the Keithley 2450 can't be simulated: {generic.SimulationProblem or 'too few parameters'}"
except BaseException as e:
    offline_works, offline_message = False, f"{type(e).__name__}: {e}"

# Every bundled package should carry its licence, which most licences require to be shipped with it
site_packages = next(p for p in sys.path if p.endswith("site-packages"))
no_licence = []
for name in sorted(os.listdir(site_packages)):
    if name.endswith(".dist-info"):
        folder = os.path.join(site_packages, name)
        files = os.listdir(folder)
        has_licence = any(re.match(r"(licen[cs]e|copying|notice)", f, re.I) for f in files) \
            or (os.path.isdir(os.path.join(folder, "licenses")) and os.listdir(os.path.join(folder, "licenses"))) \
            or (os.path.isdir(os.path.join(folder, "license_files")) and os.listdir(os.path.join(folder, "license_files")))
        if not has_licence:
            no_licence.append(name[:-len(".dist-info")])

result = {
    "Entries": len(catalog),
    "Importable": len(catalog) - len(failures),
    "MissingPackages": [{"Name": k, "Count": v} for k, v in sorted(missing.items(), key=lambda kv: -kv[1])],
    "RequiredFailed": required_failed,
    "OfflineWorks": offline_works,
    "OfflineMessage": offline_message,
    "PackagesWithoutLicence": no_licence,
}
json.dump(result, open(result_path, "w"), indent=1)
