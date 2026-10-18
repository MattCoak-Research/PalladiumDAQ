classdef Keithley6430 < Palladium.Instruments.Keithley2410
    %Keithley6430 - Instrument driver for the Keithley Model 6430 sub-femtoamp SourceMeter.
    %The 6430 is a 2400-series SourceMeter with a Remote PreAmp, programmed
    %with the same commands as the 2410 - so this is the Keithley2410
    %driver, with the 6430's name and source limits. Everything in the
    %Keithley2410 help applies: each measurement tick takes one `:READ?`
    %reading and records, depending on `MeasMode`, the measured values, the
    %programmed source level and whether the instrument is at its compliance
    %limit; a Sweep Control can step the source level; the source function,
    %compliance, ranges and integration time are set on the front panel
    %(`SourceMode` must match, which is checked when connecting); and
    %`OffsetComp` turns on the instrument's offset-compensated ohms.
    %
    %The 6430 sources up to 210 V or 105 mA (the Sweep Control's limits,
    %or the voltage protection limit set on the instrument when sourcing
    %voltage). It has GPIB and RS-232 interfaces.

    %% Constructor
    methods
        function this = Keithley6430()
            %Set the 6430's name and source limits - the rest is the 2410's (see Keithley2410).

            this@Palladium.Instruments.Keithley2410();

            this.FullName = "Keithley 6430 Src Meter";
            this.Name = "SrcMtr";

            %Source voltage 5 uV to 210 V, source current 0.5 fA to 105 mA
            %(6430 Reference Manual, Section 1)
            this.MaxSourceVoltage_V = 210;
            this.MaxSourceCurrent_A = 0.105;
        end
    end
end
