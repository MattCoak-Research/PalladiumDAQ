function files = GenerateApiReference(classNames, outputFolder)
%GENERATEAPIREFERENCE - Write Markdown API reference pages for classes,
%built from their help comments via MATLAB's class metadata.
%
%   files = GenerateApiReference(classNames, outputFolder) writes one page
%   per class (named e.g. Palladium.Core.Instrument.md) plus an index.md to
%   outputFolder, ready for DocMaker to convert to HTML. Public and
%   protected members are documented; private, restricted-access and hidden
%   members are left out. Members inherited from other documented classes
%   are listed by name with a link to the class that defines them.
%
%   The class/member summary is the first (H1) comment line, minus the
%   leading name; the rest of the help block is the description and is
%   treated as Markdown. Property descriptions come from the comment at
%   the end of the property line (or the line above it).
%
%   Instruments (non-abstract subclasses of Palladium.Core.Instrument) are
%   also constructed once, so that property values set in the constructor
%   - commonly addresses, categoricals and connection types - appear as
%   the defaults, and properties with no declared type show the class of
%   their value. If construction fails, the page falls back to the class
%   definition alone.

arguments
    classNames (1,:) string
    outputFolder (1,1) string
end

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

metaClasses = matlab.metadata.Class.empty(1, 0);
for name = classNames
    mc = matlab.metadata.Class.fromName(name);
    assert(~isempty(mc), "GenerateApiReference:ClassNotFound", ...
        "Class %s could not be found on the MATLAB path.", name);
    metaClasses(end+1) = mc; %#ok<AGROW>
end

files = strings(0);
for i = 1 : numel(metaClasses)
    lines = ClassPage(metaClasses(i), classNames);
    files(end+1) = fullfile(outputFolder, PageName(metaClasses(i).Name)); %#ok<AGROW>
    writelines(lines, files(end));
end

files(end+1) = fullfile(outputFolder, "index.md");
writelines(IndexPage(metaClasses), files(end));
end

%% Pages

function lines = IndexPage(metaClasses)
lines = ["# API reference", "", ...
    "Reference pages for the Palladium DAQ classes, generated from the help comments in the code.", ""];

classNamespaces = MapToString(@(mc) NamespaceOf(mc.Name), metaClasses);
for ns = unique(classNamespaces)
    lines(end+1:end+2) = ["## " + ns, ""];
    for mc = metaClasses(classNamespaces == ns)
        lines(end+1) = "* [" + ShortName(mc.Name) + "](" + PageName(mc.Name) + ") - " + TableText(mc.Description); %#ok<AGROW>
    end
    lines(end+1) = ""; %#ok<AGROW>
end
end

function lines = ClassPage(mc, documented)
name = string(mc.Name);
lines = ["# " + ShortName(name), ""];

%Header line: full name, superclasses, class attributes
header = "`" + name + "`";
supers = string({mc.SuperclassList.Name});
if ~isempty(supers)
    header = header + " | Superclasses: " + join(MapToString(@(s) ClassLink(s, documented), supers), ", ");
end
if mc.Abstract
    header = header + " | *Abstract*";
end
if mc.Sealed
    header = header + " | *Sealed*";
end
lines = [lines, header, "", FullDescription(mc), ""];

instanceValues = InstanceValues(mc);
if ~isempty(instanceValues)
    lines = [lines, "*Property types and defaults on this page include values set by the constructor, " + ...
        "read from a newly constructed " + ShortName(name) + ".*", ""];
end
lines = [lines, "[Back to API reference](index.md)", ""];

isMember = @(m) ~m.Hidden && IsVisible(m.DefiningClass, mc);

%% Enumeration members
if ~isempty(mc.EnumerationMemberList)
    lines = [lines, "## Enumeration members", "", "| Member | Description |", "| --- | --- |"];
    for e = mc.EnumerationMemberList'
        lines(end+1) = "| `" + e.Name + "` | " + TableText(e.Description) + " |"; %#ok<AGROW>
    end
    lines(end+1) = "";
end

%% Properties
props = mc.PropertyList;
props = props(arrayfun(@(p) isMember(p) && IsDocumentedAccess(p.GetAccess), props));
lines = [lines, PropertiesSection(props, mc, documented, instanceValues)];

%% Methods
methodList = mc.MethodList;
methodList = methodList(arrayfun(@(m) isMember(m) && IsDocumentedAccess(m.Access), methodList));
methodList = SortByName(methodList);
definedHere = arrayfun(@(m) DefinedHere(m, mc), methodList);
%Leave out methods MATLAB generates rather than the class's source defines
%(e.g. char, eq and union on every enumeration)
methodList = methodList(~definedHere | arrayfun(@(m) IsInSource(m, mc), methodList));
isConstructor = arrayfun(@(m) string(m.Name) == ShortName(name), methodList);
definedHere = arrayfun(@(m) DefinedHere(m, mc), methodList);
%Leave out implicit/empty constructors (e.g. on all-static utility classes)
isTrivial = arrayfun(@(m) isempty(m.InputNames) && FullDescription(m) == "*No help text.*", methodList);
lines = [lines, MethodsSection("Constructor", methodList(isConstructor & definedHere & ~isTrivial), mc, documented)];
lines = [lines, MethodsSection("Methods", methodList(~isConstructor & definedHere), mc, documented)];

%% Events
eventList = mc.EventList;
eventList = eventList(arrayfun(@(e) isMember(e) && IsDocumentedAccess(e.ListenAccess) && DefinedHere(e, mc), eventList));
if ~isempty(eventList)
    lines = [lines, "## Events", "", "| Event | Description |", "| --- | --- |"];
    for e = SortByName(eventList)'
        lines(end+1) = "| `" + e.Name + "` | " + TableText(e.Description) + " |"; %#ok<AGROW>
    end
    lines(end+1) = "";
end

%% Inherited members, grouped by the class that defines them
inheritedPropList = props(arrayfun(@(p) ~DefinedHere(p, mc) && ~IsGuiEditable(p), props)); %GUI-editable ones are listed in their own table
inherited = [MapToString(@(p) p.DefiningClass.Name, inheritedPropList), ...
    MapToString(@(m) m.DefiningClass.Name, methodList(~definedHere & ~isConstructor))];
if ~isempty(inherited)
    lines = [lines, "## Inherited members", ""];
    for definer = unique(inherited)
        inheritedProps = inheritedPropList(arrayfun(@(p) string(p.DefiningClass.Name) == definer, inheritedPropList));
        inheritedMethods = methodList(~definedHere & ~isConstructor);
        inheritedMethods = inheritedMethods(arrayfun(@(m) string(m.DefiningClass.Name) == definer, inheritedMethods));
        lines(end+1) = "From " + ClassLink(definer, documented) + ":"; %#ok<AGROW>
        if ~isempty(inheritedProps)
            inheritedProps = SortByName(inheritedProps);
            lines(end+1) = "* Properties: " + join("`" + string({inheritedProps.Name}) + "`", ", "); %#ok<AGROW>
        end
        if ~isempty(inheritedMethods)
            lines(end+1) = "* Methods: " + join("`" + string({inheritedMethods.Name}) + "`", ", "); %#ok<AGROW>
        end
        lines(end+1) = ""; %#ok<AGROW>
    end
end
end

function lines = PropertiesSection(props, mc, documented, instanceValues)
%Properties, split into tables by how they can be used. GUI-editable
%properties come first, and include inherited ones, since together they
%are what the Instrument Options panel shows. Everything else lists only
%the properties defined in this class.
lines = strings(0);
isGui = arrayfun(@IsGuiEditable, props);
definedHere = arrayfun(@(p) DefinedHere(p, mc), props);
getAccess = MapToString(@(p) AccessName(p.GetAccess), props)';
setAccess = MapToString(@(p) AccessName(p.SetAccess), props)';
isConstant = arrayfun(@(p) p.Constant, props);
isPublic = getAccess == "public";

groups = { ...
    "GUI-editable properties", isGui, ...
    "These properties are declared `SetObservable` with public set access. For instruments, they are shown " + ...
    "and can be edited in the Instrument Options panel of the GUI (unless the class hides them with " + ...
    "`GetPropertiesToIgnore`), and changes to them raise `PropertyChanged` events. Inherited ones are included.";
    "Public properties", definedHere & ~isGui & isPublic & ~isConstant & setAccess == "public", ...
    "";
    "Read-only properties", definedHere & ~isGui & isPublic & ~isConstant & setAccess ~= "public", ...
    "Public to read, but only set by the class itself (or its subclasses, for protected set access).";
    "Constant properties", definedHere & isConstant & isPublic, ...
    "";
    "Protected properties", definedHere & ~isGui & getAccess == "protected", ...
    "Only accessible from within the class and its subclasses - relevant when writing a subclass."};

for i = 1 : size(groups, 1)
    [heading, selected, intro] = groups{i, :};
    if ~any(selected)
        continue
    end
    lines = [lines, "## " + heading, ""]; %#ok<AGROW>
    if intro ~= ""
        lines = [lines, intro, ""]; %#ok<AGROW>
    end
    lines = [lines, "| Property | Type | Default | Description |", "| --- | --- | --- | --- |"]; %#ok<AGROW>
    for p = SortByName(props(selected))'
        lines(end+1) = "| `" + p.Name + "` | " + TypeCell(TypeString(p, instanceValues), documented) + " | " + ...
            DefaultCell(p, instanceValues) + " | " + PropertyDescription(p, mc, documented) + " |"; %#ok<AGROW>
    end
    lines(end+1) = ""; %#ok<AGROW>
end
end

function tf = IsGuiEditable(p)
%Same rule as Palladium.Utilities.GUIUtils uses to pick the properties it shows
tf = p.SetObservable && AccessName(p.SetAccess) == "public" && ~p.Constant && ~p.Hidden;
end

function lines = MethodsSection(heading, methodList, mc, documented)
lines = strings(0);
if isempty(methodList)
    return
end
lines = ["## " + heading, ""];

%Summary table for longer lists, then the full entry for each method
if numel(methodList) > 1
    lines = [lines, "| Method | Summary |", "| --- | --- |"];
    for m = methodList'
        lines(end+1) = "| `" + m.Name + "` | " + TableText(DescriptionSource(m, mc).Description) + " |"; %#ok<AGROW>
    end
    lines(end+1) = "";
end

for m = methodList'
    lines(end+1:end+2) = ["### " + m.Name, ""];
    lines(end+1) = "`" + Signature(m, mc) + "`" + MethodAttributes(m); %#ok<AGROW>
    base = OverriddenMethod(m, mc);
    if ~isempty(base)
        verb = "Overrides";
        if base.Abstract
            verb = "Implements";
        end
        lines(end+1:end+2) = ["", "*" + verb + " `" + m.Name + "` from " + ClassLink(base.DefiningClass.Name, documented) + "*"];
    end
    lines(end+1:end+3) = ["", FullDescription(DescriptionSource(m, mc)), ""];
end
end

%% Text helpers

function text = FullDescription(item)
%Summary (H1 line) followed by the rest of the help block. They are written
%as consecutive lines so that a sentence wrapping onto the second comment
%line still renders as one paragraph.
summary = strtrim(string(item.Description));
detail = Dedent(string(item.DetailedDescription));
if summary == "" && detail == ""
    text = "*No help text.*";
elseif detail == ""
    text = summary;
else
    text = summary + newline + detail;
end
end

function text = Dedent(text)
%Remove the indentation common to all non-blank lines
if strtrim(text) == ""
    text = "";
    return
end
lines = splitlines(text);
indents = strlength(lines) - strlength(strip(lines, "left"));
indent = min(indents(strip(lines) ~= ""));
lines(strlength(lines) >= indent) = extractAfter(lines(strlength(lines) >= indent), indent);
text = strip(join(lines, newline), "right");
end

function text = TableText(text)
%Single-line text that is safe inside a Markdown table cell
text = strtrim(string(text));
if text == ""
    text = "-";
end
text = replace(join(strtrim(splitlines(text)), " "), "|", "\|");
end

function text = Code(text)
if text == ""
    text = "-";
else
    text = "`" + replace(text, "|", "\|") + "`";
end
end

function link = ClassLink(className, documented)
className = string(className);
if any(documented == className)
    link = "[" + className + "](" + PageName(className) + ")";
else
    link = "`" + className + "`";
end
end

function text = Signature(m, mc)
inputs = string(m.InputNames);
outputs = string(m.OutputNames);
name = string(m.Name);
if m.Static
    name = ShortName(mc.Name) + "." + name;
end
text = name + "(" + join(inputs, ", ") + ")";
if isempty(inputs)
    text = name + "()";
end
if isscalar(outputs)
    text = outputs + " = " + text;
elseif numel(outputs) > 1
    text = "[" + join(outputs, ", ") + "] = " + text;
end
end

function text = MethodAttributes(m)
attributes = strings(0);
if AccessName(m.Access) ~= "public"
    attributes(end+1) = AccessName(m.Access);
end
if m.Static
    attributes(end+1) = "Static";
end
if m.Abstract
    attributes(end+1) = "Abstract - subclasses must implement";
end
if m.Sealed
    attributes(end+1) = "Sealed";
end
text = "";
if ~isempty(attributes)
    text = " - *" + join(attributes, ", ") + "*";
end
end

function text = PropertyDescription(p, mc, documented)
%Description table cell: notable attributes (in italics) then the
%property's own comment
text = TableText(p.Description);
notes = PropertyNotes(p, mc, documented);
if notes ~= "" && text == "-"
    text = notes + ".";
elseif notes ~= ""
    text = notes + ". " + text;
end
end

function text = PropertyNotes(p, mc, documented)
%Attributes worth flagging, shown in italics before the description
notes = strings(0);
if ~DefinedHere(p, mc)
    notes(end+1) = "From " + ClassLink(p.DefiningClass.Name, documented);
end
if p.Abstract
    notes(end+1) = "*Abstract - subclasses must define*";
end
if p.Dependent
    notes(end+1) = "*Dependent*";
end
setAccess = AccessName(p.SetAccess);
if ~p.Constant && AccessName(p.GetAccess) == "public" && setAccess ~= "public"
    notes(end+1) = "*" + setAccess + " set*";
end
text = "";
if ~isempty(notes)
    text = join(notes, ", ");
end
end

function text = ValidationString(v)
%Size, class and validation functions, as written in the properties block
text = "";
if isempty(v)
    return
end
parts = strings(0);
if ~isempty(v.Size)
    dims = MapToString(@DimensionString, v.Size);
    parts(end+1) = "(" + join(dims, ",") + ")";
end
if ~isempty(v.Class)
    parts(end+1) = string(v.Class.Name);
end
if ~isempty(v.ValidatorFunctions)
    validators = string(cellfun(@func2str, v.ValidatorFunctions, UniformOutput=false));
    validators = regexprep(validators, "^@\(\w*\)", ""); %Drop anonymous-function wrappers
    parts(end+1) = "{" + join(validators, ", ") + "}";
end
if ~isempty(parts)
    text = join(parts, " ");
end
end

function text = DimensionString(d)
if isprop(d, "Length")
    text = string(d.Length);
else
    text = ":";
end
end

function text = TypeString(p, instanceValues)
%The declared size/class/validators; failing that, for instruments, the
%class of the property's value once constructed
text = ValidationString(p.Validation);
if ~isfield(instanceValues, p.Name)
    return
end
value = instanceValues.(p.Name);
if iscategorical(value)
    %Categories only exist on an instance - add them to the declared type
    categoriesText = "categorical {" + join(string(categories(value)), ", ") + "}";
    if contains(text, "categorical")
        text = replace(text, "categorical", categoriesText);
    elseif text == ""
        text = categoriesText;
    end
elseif text == "" && ~isempty(value) && ~isstruct(value)
    text = string(class(value));
end
end

function cell = TypeCell(text, documented)
%Type column cell, as code - with any documented class names in it (e.g. an
%enumeration) linked to their reference pages
if text == ""
    cell = "-";
    return
end

%Whole class names only (not part of a longer name), longest first
names = documented(arrayfun(@(d) contains(text, d), documented));
if isempty(names)
    cell = Code(text);
    return
end
[~, order] = sort(strlength(names), "descend");
pattern = "(?<![\w.])(" + join(regexptranslate("escape", names(order)), "|") + ")(?![\w.])";
[links, others] = regexp(text, pattern, "match", "split");

parts = strings(0);
for i = 1 : numel(others)
    if strtrim(others(i)) ~= ""
        parts(end+1) = Code(strtrim(others(i))); %#ok<AGROW>
    end
    if i <= numel(links)
        parts(end+1) = "[`" + links(i) + "`](" + PageName(links(i)) + ")"; %#ok<AGROW>
    end
end
cell = join(parts, " ");
end

function cell = DefaultCell(p, instanceValues)
%Declared default, or for instruments the value after construction -
%flagged when the constructor changed it
hasDeclared = false;
if p.HasDefault
    try
        declared = p.DefaultValue;
        hasDeclared = true;
    catch
    end
end

if isfield(instanceValues, p.Name)
    value = instanceValues.(p.Name);
    cell = Code(ValueString(value));
    if cell ~= "-" && (~hasDeclared || ~isequal(value, declared))
        cell = cell + " *(set in constructor)*";
    end
elseif hasDeclared
    cell = Code(ValueString(declared));
else
    cell = "-";
end
end

function text = ValueString(value)
%Short scalar/text values only - large structs and arrays would swamp the
%table
text = "";
if (isenum(value) || iscategorical(value)) && isscalar(value)
    text = string(value);
elseif (isnumeric(value) || islogical(value)) && isscalar(value)
    text = string(value);
elseif isstring(value) && isscalar(value)
    text = """" + value + """";
elseif ischar(value) && (isrow(value) || isempty(value))
    text = "'" + string(value) + "'";
elseif isnumeric(value) && isempty(value)
    text = "[]";
end
if strlength(text) > 40
    text = "";
end
end

function values = InstanceValues(mc)
%For instruments, construct one and return its property values (including
%protected ones) as a struct. Returns [] for other classes, or if
%construction fails.
values = [];
if mc.Abstract || ~any(strcmp(superclasses(mc.Name), "Palladium.Core.Instrument"))
    return
end
try
    instance = feval(mc.Name);
catch err
    warning("GenerateApiReference:ConstructionFailed", ...
        "Could not construct %s, so its page shows declared defaults only: %s", mc.Name, err.message);
    return
end
cleanup = onCleanup(@() delete(instance));
warningState = warning("off", "MATLAB:structOnObject");
restoreWarning = onCleanup(@() warning(warningState));
values = struct(instance); %Includes protected properties
end

%% Source checks

function tf = IsInSource(m, mc)
%Whether method m is written in the source of class mc: a function in its
%classdef file, or a file of its own in an @-folder. Abstract methods have
%no function line, and non-.m classes (e.g. .mlapp) can't be checked, so
%those count as in source.
tf = true;
file = which(mc.Name);
[folder, ~, ext] = fileparts(file);
if m.Abstract || ext ~= ".m" || string(m.Name) == ShortName(mc.Name)
    return
end
pattern = "^\s*function\s+([^=\r\n]*=\s*)?" + m.Name + "\>";
tf = ~isempty(regexp(fileread(file), pattern, "once", "lineanchors")) || ...
    (startsWith(ShortName(folder), "@") && isfile(fullfile(folder, m.Name + ".m")));
end

%% Overrides

function base = OverriddenMethod(m, mc)
%The superclass method (from this code base) that m overrides or
%implements, or [] if there isn't one
base = [];
for s = mc.SuperclassList'
    candidate = findobj(s.MethodList, "Name", m.Name);
    if ~isempty(candidate) && IsVisible(candidate(1).DefiningClass, mc)
        base = candidate(1);
        return
    end
end
end

function source = DescriptionSource(m, mc)
%Where a method has no help text of its own: an override borrows the help
%of the method it overrides, and a Categoricals converter gets a generated
%description. Returns the method, or an object/struct with Description and
%DetailedDescription to use in its place.
source = m;
if FullDescription(m) ~= "*No help text.*"
    return
end
base = OverriddenMethod(m, mc);
converterHelp = CategoricalConverterHelp(m, mc);
if ~isempty(base)
    source = base;
elseif converterHelp ~= ""
    source = struct("Description", converterHelp, "DetailedDescription", "");
end
end

function help = CategoricalConverterHelp(m, mc)
%For a one-line Categoricals converter, e.g.
%   function catOut = MeasType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["A", "B"]); end
%a summary naming its categories and the properties set from it (found as
%this.Prop = this.MeasType(...) in the class source). "" for other methods.
help = "";
file = which(mc.Name);
[~, ~, ext] = fileparts(file);
if ext ~= ".m"
    return
end
source = fileread(file);
pattern = "function\s+\w+\s*=\s*" + m.Name + "\s*\([^)]*\)\s*;[^\r\n]*?ConvertToCategorical\(\s*\w+\s*,\s*\[([^\]]*)\]";
tokens = regexp(source, pattern, "tokens", "once");
if isempty(tokens)
    return
end
values = strip(erase(split(string(tokens{1}), ","), ["""", "'"]));
help = "Converts text to a categorical with the values " + join(values', ", ");

assignments = regexp(source, "this\.(\w+)\s*=\s*this\." + m.Name + "\(", "tokens");
if ~isempty(assignments)
    properties = unique(cellfun(@(t) string(t{1}), assignments));
    help = help + " - the values of " + join("`" + properties + "`", ", ");
end
help = help + ".";
end

%% Member filtering

function tf = IsDocumentedAccess(access)
tf = any(AccessName(access) == ["public", "protected", "immutable"]);
end

function name = AccessName(access)
%Access is a char vector, or a list of classes allowed access
if ischar(access) || isstring(access)
    name = string(access);
else
    name = "restricted";
end
end

function tf = IsVisible(definingClass, mc)
%Members from MATLAB base classes such as handle are left out
tf = string(definingClass.Name) == string(mc.Name) || startsWith(definingClass.Name, NamespaceRoot(mc.Name));
end

function tf = DefinedHere(member, mc)
tf = string(member.DefiningClass.Name) == string(mc.Name);
end

function out = MapToString(fcn, items)
%arrayfun for functions that return a string
out = strings(1, numel(items));
for i = 1 : numel(items)
    out(i) = string(fcn(items(i)));
end
end

function items = SortByName(items)
[~, order] = sort(lower(string({items.Name})));
items = items(order);
end

%% Names

function name = PageName(className)
name = string(className) + ".md";
end

function name = ShortName(className)
parts = split(string(className), ".");
name = parts(end);
end

function ns = NamespaceOf(className)
parts = split(string(className), ".");
if isscalar(parts)
    ns = "(no namespace)";
else
    ns = join(parts(1:end-1), ".");
end
end

function root = NamespaceRoot(className)
parts = split(string(className), ".");
root = parts(1);
end
