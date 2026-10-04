# Code and comment conventions

Palladium classes follow a consistent layout, and the [API reference](../reference/index.md) is generated from their help comments. Following these conventions keeps the code easy to navigate and makes the reference pages read well. They apply to all classes, and to instrument drivers in particular.

## Class layout

Every block in a `classdef` gets a `%% ` section header, even when there is only one block of its kind. Blocks appear in this order (leave out any that are not needed):

| Order | Section header | Declaration |
| :-: | --- | --- |
| 1 | `%% Properties (Abstract, Constant, Public)`, `%% Properties (Abstract, Public)` | `properties (Abstract, ...)` - base classes only |
| 2 | `%% Properties (Constant, Public)`, `%% Properties (Constant, Private)` | `properties (Constant, ...)` |
| 3 | `%% Properties (Public)` | `properties (Access = public)` |
| 4 | `%% Properties (Public, Set Observable)` | `properties (Access = public, SetObservable)` |
| 5 | `%% Properties (Public, Protected Set)`, `%% Properties (Public, Private Set)` | `properties (GetAccess = public, SetAccess = protected)` etc. |
| 6 | `%% Properties (Protected)` | `properties (Access = protected)` |
| 7 | `%% Properties (Private)` | `properties (Access = private)` |
| 8 | `%% Events` | `events` |
| 9 | `%% Get and Set Accessors` | `methods` holding `get.Prop`/`set.Prop` |
| 10 | `%% Categoricals` | `methods` holding the one-line categorical converters (instruments) |
| 11 | `%% Methods (Abstract, Public)` | `methods (Abstract, Access = public)` - base classes only |
| 12 | `%% Constructor` | `methods` |
| 13 | `%% Methods (Public)`, then `%% Methods (Public, Sealed)` | `methods (Access = public)` |
| 14 | `%% Methods (Protected)` | `methods (Access = protected)` |
| 15 | `%% Methods (Private)` | `methods (Access = private)` |
| 16 | `%% Methods (Static, Public)`, then `%% Methods (Static, Private)` | `methods (Static, Access = ...)` |

The header lists the block's attributes in the order *modifiers* (`Abstract`, `Constant`, `Static`, `Dependent`), then *access* (`Public`, `Protected`, `Private`), then *extras* (`Set Observable`, `Sealed`). Where get and set access differ, write e.g. `Public, Private Set`. The header must match the attributes of the block beneath it. A short description may follow a dash, e.g. `%% Properties (Public) - Sweep Parameters`.

* **Enumeration classes** (in `+Enums`) have a class help block, then a `%% Enumeration` section with one member per line, each with a trailing comment describing it. Member order is the order shown in GUI drop-downs, so keep it stable.
* **Dependent** property blocks sit next to the block with the same access, e.g. `%% Properties (Dependent, Public)` beside `%% Properties (Public)`.
* **Access lists** that grant extra classes access, such as `Access = {?Palladium, ?matlab.unittest.TestCase}` to let tests in, are labelled `Private`.
* **The order of `SetObservable` properties is the order their fields appear in the GUI.** When reordering blocks, do not change the order of GUI-editable properties unless that is the intention.

A skeleton instrument driver:

```matlab
classdef MyInstrument < Palladium.Core.Instrument
    %MyInstrument - One-line summary of the instrument, as a complete sentence.
    %Further description, which can run over several lines and is
    %rendered as Markdown in the API reference.

    %% Properties (Public)
    properties (Access = public)
        FullName = "My Instrument Model 1234"     %Full name, displayed in the GUI
    end

    %% Properties (Public, Set Observable)
    % These properties will appear in the Instrument Settings GUI and are editable there
    properties (Access = public, SetObservable)
        Name = "MyInst"                                     %Instrument name, used in data column headers
        Connection_Type = Palladium.Enums.ConnectionType.GPIB   %Type of connection used to talk to the instrument
        Range categorical                                   %Measurement range, set in the constructor
    end

    %% Categoricals
    methods
        function catOut = RangeType(this, inputStr); catOut = this.ConvertToCategorical(inputStr, ["Low", "High"]); end
    end

    %% Constructor
    methods
        function this = MyInstrument()
            %Specify communication options and default settings

            this.DefineSupportedConnectionTypes(["Debug", "GPIB"]);
            this.GPIB_Address = 12;
            this.Range = this.RangeType("Low");
        end
    end

    %% Methods (Public)
    methods (Access = public)
        function [headers, units] = GetHeaders(this)
            %Column headers and units of the values returned by Measure

            headers = this.Name + " - Voltage";
            units = "V";
        end

        function dataRow = Measure(this)
            %Read the voltage, or generate synthetic data in SimulationMode

            if this.SimulationMode
                dataRow = rand();
            else
                dataRow = this.QueryDouble("READ?");
            end
        end
    end
end 
```

## Help comments

MATLAB's `help` and the API reference both read the comment block directly beneath a `classdef` or `function` line.

* **The first line is the summary.** It must be a complete sentence that fits on that one line - summary tables in the reference show only this line. Do not let a sentence wrap onto the second line.
* **Classes** start with the class name and a dash: `%Keithley2000 - Instrument implementation for Keithley 2000 digital multimeters.` MATLAB strips the leading name.
* **Methods** start straight with the summary: `%Get measurement values from the instrument.` Do not start with the method name as the subject of the sentence (`%UpdateAndMeasure is the entry point...`) - MATLAB strips the name and leaves the summary reading "is the entry point...".
* **Further lines** give the detail. They are rendered as Markdown, so use backticks for code (`` `Connect()` ``), `*` for bulleted lists, and a line containing only `%` between paragraphs.
* **Leave a blank line** (with no `%`) between the end of the help block and the first line of code or code comment. Otherwise the code comment becomes part of the help text.
* **Describe inputs and outputs** in the help text where they are not obvious from their names and any `arguments` block. After the summary and a `%` line, list them under `%Inputs:` and `%Outputs:` headings, one per line as `%   name - description`:

```matlab
function unit = QueryUnit(this, command)
    %Query a :UNIT setting and return it as a units string, e.g. "C" or "dBm"
    %
    %Inputs:
    %   command - the :UNIT query to send, e.g. ":UNIT:TEMP?"
    %
    %Outputs:
    %   unit - units string, with dB and dBm in their usual case
end 
```
* **Overriding methods**, such as an instrument's `Measure` or `GetHeaders`, need help text only where their behaviour differs from the base class; otherwise the reference shows the base class's help.

## Properties

* **Declare a type** wherever the property has a fixed type, e.g. `Range categorical`, `GPIB_Address (1,1) {mustBeInteger}`, or `Connection_Type Palladium.Enums.ConnectionType`. The API reference shows declared types on every page; otherwise it can only show the class of the value on instrument pages, and nothing elsewhere. Declared types also catch invalid values set from the GUI or scripts. Note that a declared class converts values assigned to it (for example, `"GPIB"` becomes `ConnectionType.GPIB`), so test the class after adding one.
* **Inherited abstract properties** - `Name`, `FullName` and `Connection_Type` in instrument drivers - cannot have a type declared in the subclass; MATLAB does not allow it. Their type belongs on the abstract declaration in the base class, and subclasses inherit it; the subclass only gives the value.
* **Comment every property** with a single line: either at the end of the declaration line or, if it would be too long, on its own line directly above. The reference shows only the first line, so keep it to one.
* **`SetObservable` means GUI-editable.** Public `SetObservable` properties are shown and editable in the Instrument Options panel, and raise `PropertyChanged` events. Use it only for settings a user should change, and put them in the `Properties (Public, Set Observable)` block.
* **Abstract properties** in a base class should say what subclasses must set them to.

## Code formatting

* **Compact `switch` statements.** When every case of a `switch` does one short thing - typically assigning one or two values - write each case on a single line, `case(...);` followed by its statements, with the statements aligned in a column. This keeps lookup-style switches readable as a table:

```matlab
switch(this.MeasMode)
    case(this.MeasType("DC Voltage"));          quantity = "Voltage_DC";
    case(this.MeasType("Resistance"));          quantity = "Resistance";
    case(this.MeasType("4-Wire Resistance"));   quantity = "Resistance_4W";
    otherwise
        error("Keithley2000:InvalidMeasureMode", "%s", "Unsupported measurement mode: " + string(this.MeasMode));
end 
```

  Keep the multi-line form for cases with more than a line or two of logic, and for `otherwise` branches that raise an error.

## Instrument drivers

* **Constructors must work with no arguments and no hardware attached.** They only set defaults (addresses, categoricals, supported connection types, Instrument Controls); connecting happens later in `Connect()`. The API reference build constructs every instrument to read these defaults.
* **Categorical properties** get a converter in the `Categoricals` block and a default set in the constructor, as in the skeleton above.
* **Start from** `+Palladium/+Instruments/TemplateInstrumentClass.m`, which follows this layout.
