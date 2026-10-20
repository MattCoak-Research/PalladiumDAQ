classdef LoopState
    %LoopState - The state of the measurement loop, held in TimingLoopController.State.
    %Changes Ready -> Running when measurements start, then back to Ready
    %when they stop. `Pause` and `Stop` first set Pausing or Stopping, which
    %take effect on the next tick (Paused, or Ready). Compare it with text,
    %e.g. `State == "Running"`, or use it in a `switch` with text cases.

    %% Enumeration
    enumeration
        Ready       %Not measuring - instruments are not connected
        Running     %Measuring, one tick per update time
        Pausing     %Pause has been asked for, and takes effect on the next tick
        Paused      %Paused - instruments stay connected, and Resume carries on
        Stopping    %Stop has been asked for, and takes effect on the next tick
    end
end
