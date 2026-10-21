# QCoDeSCatalog.py
"""Find the QCoDeS instrument drivers that can be added to Palladium DAQ, without importing them.

Importing hundreds of driver modules would be slow, and some fail without
optional packages, so the driver files are read as text and parsed. A class is
taken to be an instrument if it inherits (directly, or through other classes in
the files read) from QCoDeS's Instrument or VisaInstrument. That is a guess
from the source, so the odd class that isn't an instrument is listed, and the
odd one that is isn't. Only the driver the user chooses is imported.

The drivers come from the installed qcodes and qcodes_contrib_drivers
packages, and from any .py files in the user's QCoDeS Drivers folder.
"""
import ast
import importlib.util
import json
import os
import re

ENTRY_PREFIX = "QCoDeS: "
_ROOT_BASES = {"Instrument", "VisaInstrument", "IPInstrument"}   # QCoDeS's own base classes, by name
_BUILDING_BLOCK = re.compile(r"(^|[a-z0-9_])(Base|Abstract|Mixin)([A-Z0-9_]|$)")   # e.g. LakeshoreBase, KeysightPNABase - but not Basel


def _package_folder(*parts):
    """The folder of an installed package's sub-package, found without importing it - or None."""
    try:
        spec = importlib.util.find_spec(parts[0])     # Finds a top-level package without importing it
    except (ImportError, ValueError):
        return None
    if spec is None or not spec.submodule_search_locations:
        return None
    folder = os.path.join(list(spec.submodule_search_locations)[0], *parts[1:])
    return folder if os.path.isdir(folder) else None


def _python_files(folder):
    for root, dirs, files in os.walk(folder):
        dirs[:] = sorted(d for d in dirs if not d.startswith((".", "__")) and d != "tests")
        for name in sorted(files):
            if name.endswith(".py") and name != "__init__.py":       # Private modules (_name.py) hold many drivers too
                yield os.path.join(root, name)


def _classes_in_file(path):
    """(class name, [base class names]) for each class defined at the top of a Python file; [] if it can't be parsed."""
    try:
        with open(path, encoding="utf-8") as f:
            tree = ast.parse(f.read(), filename=path)
    except (OSError, SyntaxError, UnicodeDecodeError, ValueError):
        return []
    found = []
    for node in tree.body:
        if isinstance(node, ast.ClassDef):
            bases = []
            for base in node.bases:
                if isinstance(base, ast.Name):
                    bases.append(base.id)
                elif isinstance(base, ast.Attribute):
                    bases.append(base.attr)
                elif isinstance(base, ast.Subscript) and isinstance(base.value, ast.Name):
                    bases.append(base.value.id)       # A generic base, e.g. Foo[Bar]
            found.append((node.name, bases))
    return found


def _scan_source(files, module_name, extra_known=()):
    """The instrument classes in a set of files, and the names of every instrument class found (building blocks too).

    The classes are a list of dicts with name and class_path (module.Class). extra_known are names of
    instrument classes defined elsewhere, which a class in these files may inherit from."""
    per_file = [(f, _classes_in_file(f)) for f in files]
    known = set(_ROOT_BASES) | set(extra_known)
    changed = True
    while changed:                      # A class is an instrument if a base is - repeat until nothing new is found
        changed = False
        for _, classes in per_file:
            for name, bases in classes:
                if name not in known and any(b in known for b in bases):
                    known.add(name)
                    changed = True
    result = []
    for path, classes in per_file:
        for name, bases in classes:
            if name in known and name not in _ROOT_BASES and not name.startswith("_") \
                    and not _BUILDING_BLOCK.search(name):
                result.append(dict(name=name, class_path=f"{module_name(path)}.{name}", file=path))
    return result, known


def scan_installed():
    """The drivers in the installed qcodes and qcodes_contrib_drivers packages."""
    return _scan_installed()[0]


def _scan_installed():
    """scan_installed, and the names of every instrument class in those packages (for classes in other files to inherit from)."""
    entries = []
    known = set()
    for source, parts, label in (("qcodes", ("qcodes", "instrument_drivers"), "QCoDeS"),
                                 ("contrib", ("qcodes_contrib_drivers", "drivers"), "QCoDeS contrib")):
        folder = _package_folder(*parts)
        if folder is None:
            continue
        base = os.path.dirname(os.path.dirname(folder))     # The folder that holds the top-level package

        def module_name(path, base=base):
            return os.path.relpath(path, base)[:-3].replace(os.sep, ".")

        found, found_known = _scan_source(_python_files(folder), module_name)
        known |= found_known
        for e in found:
            e["source"] = source
            e["folder"] = ""
            e["vendor"] = os.path.relpath(e["file"], folder).split(os.sep)[0].replace(".py", "")
            entries.append(e)
    return entries, known


def scan_folder(folder, extra_known=()):
    """The drivers in .py files in a folder (not its subfolders) - such as the user's QCoDeS Drivers folder.

    extra_known are names of instrument classes elsewhere (the installed drivers) that a class here may inherit from."""
    if not folder or not os.path.isdir(folder):
        return []
    files = sorted(os.path.join(folder, n) for n in os.listdir(folder) if n.endswith(".py") and not n.startswith("_"))
    entries, _ = _scan_source(files, lambda path: os.path.splitext(os.path.basename(path))[0], extra_known)
    for e in entries:
        e["source"] = "user"
        e["vendor"] = ""
        e["folder"] = folder
    return entries


def build_catalog(user_folder=None):
    """Every driver that can be added, with a unique entry name for each: a list of dicts.

    Each has entry (the name in Palladium's instrument list, e.g. "QCoDeS: Keithley2450"),
    class_path, name, source ("qcodes", "contrib" or "user"), vendor and file; user drivers
    also have folder, which must be put on Python's path to import them.
    An entry's name is the class name, with " (contrib)" or " (user)" if the same
    class is in more than one place, and the vendor too if that isn't enough.
    """
    installed, known = _scan_installed()
    entries = installed + scan_folder(user_folder, known)
    for e in entries:
        e["entry"] = ENTRY_PREFIX + e["name"]
    counts = {}
    for e in entries:
        counts[e["entry"]] = counts.get(e["entry"], 0) + 1
    for e in entries:
        if counts[e["entry"]] > 1 and e["source"] != "qcodes":
            e["entry"] += f" ({e['source']})"
    counts = {}
    for e in entries:
        counts[e["entry"]] = counts.get(e["entry"], 0) + 1
    for e in entries:
        if counts[e["entry"]] > 1:
            where = e["vendor"] or os.path.splitext(os.path.basename(e["file"]))[0]     # A user driver has no vendor: use its file's name
            e["entry"] = f"{ENTRY_PREFIX}{where}.{e['name']}" + (f" ({e['source']})" if e["source"] != "qcodes" else "")
    counts = {}
    for e in entries:
        counts[e["entry"]] = counts.get(e["entry"], 0) + 1
    for e in entries:      # The same class name defined in several files of one vendor
        if counts[e["entry"]] > 1:
            e["entry"] += f" [{os.path.splitext(os.path.basename(e['file']))[0]}]"
    entries.sort(key=lambda e: e["entry"].lower())
    return entries


def build_catalog_json(user_folder=""):
    """build_catalog, as JSON for MATLAB: a list of dicts with entry, name, class_path, source, vendor, file and folder (all text)."""
    fields = ("entry", "name", "class_path", "source", "vendor", "file", "folder")
    # The same fields in the same order in every entry, so that MATLAB decodes the list as one struct array
    return json.dumps([{f: e.get(f, "") for f in fields} for e in build_catalog(user_folder or None)])
