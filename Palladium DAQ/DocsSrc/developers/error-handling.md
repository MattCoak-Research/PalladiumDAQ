# Error handling in the GUI

Errors thrown from a GUI callback or an event listener need special handling in Palladium DAQ, or they never reach the error dialogue and the log. This page explains why, how the error handling is put together, and how to hook up new GUI code so its errors are caught. The classes involved have help comments in the code - see `help Palladium.Core.ErrorGuard`.

> **Keep this page up to date.** If you change `ErrorGuard`, `Controller.HandleCallbackError`, `Controller.HandleError` or the dialogue in `Logger.HandleError`, update this page in the same change.

## The problem

MATLAB deliberately converts any error that escapes an **event listener** (`addlistener` / `notify`) or a **UI component callback** (a button push, a value change) into an orange warning. The error is never passed back to the code that fired the event, so a `try` / `catch` around `notify(...)` cannot see it.

This matters most while the measurement loop is running. The loop's timer calls `drawnow()` at the top of every tick, which runs any queued GUI callbacks inside the tick. An error in, say, a settings field's change handler then appears as orange warning text with a stack trace pointing at `timer.m`. It is never logged, never shows the error dialogue, and the loop carries on regardless.

The only way to catch these errors is a `try` / `catch` inside the callback itself. The error handling described here adds that systematically, and sends everything it catches to one place.

## How it works

There is one funnel, `Controller.HandleCallbackError`, with four ways in:

```text
 Measurement loop      Event listeners           GUI callbacks             Timer ErrorFcn
 (Measure, Update)     ErrorGuard.AddListener    try / catch +             (errors that escape
 try / catch           ErrorGuard.Wrap           ErrorGuard.HandleError    the loop entirely)
        |                      |                        |                          |
        +----------------------+------------------------+                          |
                               |                                                   |
                 Controller.HandleCallbackError                             log, return to Ready,
                               |                                            show a warning
                 Controller.HandleError
                               |
              +----------------+-----------------+
              |                                  |
      Logger.Log (command window,        Logger.HandleError
      GUI message area, log file)        (the error dialogue)
```

1. **The measurement loop.** `Controller.Measure` and `TimingLoopController.Update` already had `try` / `catch` blocks, which now call `HandleCallbackError`.
2. **Event listeners.** `Palladium.Core.ErrorGuard.AddListener` is a drop-in replacement for `addlistener` that wraps the callback in a `try` / `catch`. `ErrorGuard.Wrap` does the same for any function handle.
3. **GUI callbacks.** An App Designer callback has its body wrapped in `try` / `catch`, and the `catch` calls `Palladium.Core.ErrorGuard.HandleError`.
4. **The timer's `ErrorFcn`.** This is the last resort for an error that escapes `Update` entirely, which MATLAB would otherwise turn into a warning and silently stop the timer. The handler logs the error, returns the programme to Ready, and shows a warning alert. It deliberately does **not** restart the timer: the programme is in an unknown state, and restarting risks an error-restart-error loop against real hardware.

All of the guards report to the Controller. Inside most `.mlapp` components there is no `Controller` handle, so the Controller registers itself with `ErrorGuard` when it is created, and `ErrorGuard` falls back to that registered default. If there is no Controller at all (for example in a unit test), the error is just logged with the `Logger`. A guard never throws.

## What the user sees

`Controller.HandleError` logs the error once (command window, GUI message area and log file), turns the status light red, and shows the error dialogue. There are two kinds of dialogue:

| | Normal error | Standalone error |
| --- | --- | --- |
| For | The measurement loop, and anything that can affect it | Windows that do not interact with the loop: the Data Viewer, the Sequence Editor, the config window |
| Options | Stop Measurements, Stop & Go to Code, Suppress Error, Ignore | OK, Go to Code, Suppress Error, Ignore |
| Stops the loop | If the user chooses Stop Measurements (only when the loop is running) | Never |
| Status light | Turns red | Left alone |
| Shown in | The main window | The window the error came from (see `Figure` below) |

Things worth knowing:

* **One error, one log entry.** Logging happens in `Controller.HandleError` only, so an error is not logged a second time by the dialogue code.
* **No dialogue pile-ups.** The timer keeps ticking underneath a modal dialogue, so more errors can arrive while one is being handled. While an error is being handled, further errors are logged but do not open more dialogues. The flag is cleared by an `onCleanup`, so it is cleared even if handling itself fails.
* **Suppress Error** adds the error's message to a list on the Controller, and later errors with the same message are skipped silently. The list is shared by every window and is cleared when Palladium is restarted.
* **Closing.** While the main window is closing, normal errors are ignored (they are usually noise about listeners to windows that are going away). Standalone errors are still shown, as a free-floating dialogue if their window is gone too.
* **Go to Code** opens the code at the error. For an ordinary `.m` file this uses the MATLAB editor. An App Designer `.mlapp` file cannot be opened at a line, so the file is opened in App Designer and the function name and line number are printed to the command window. The line number is the one shown in Code View.

## Hooking up new GUI code

Use the first row that matches. For a window that does not interact with the measurement loop, also add the standalone options described below the table.

| You are writing | Use |
| --- | --- |
| A listener on an event, in any class | `Palladium.Core.ErrorGuard.AddListener(src, "EventName", @(s,e) ...)` instead of `addlistener` |
| A listener in an Instrument Control class | `this.AddGuardedListener(src, "EventName", @(s,e) ...)` |
| An App Designer callback (`ButtonPushed`, `ValueChanged`, ...) | A `try` / `catch` around the body, calling `ErrorGuard.HandleError` |
| A callback assigned as a function handle, e.g. `button.ButtonPushedFcn = @obj.Method` | `ErrorGuard.Wrap` around the handle |
| `startupFcn` | Nothing - see below |
| The window's close request callback | Nothing - see below |

### Listeners

Replace `addlistener` with `ErrorGuard.AddListener`. It takes the same arguments and returns the same listener handle, so it can still be passed to `RegisterEventListener`:

```matlab
Palladium.Core.ErrorGuard.AddListener(app.StateControlPanel, 'Started', @(src,evnt)app.StartPressed(src,evnt)); 
```

In an Instrument Control class (a subclass of `InstrumentControlBase`) use the helper, which fills in the control's name for the error message:

```matlab
this.AddGuardedListener(comp, 'Run', @(src,evnt)this.RunSweep(src, evnt)); 
```

Both take an optional `Context = "..."` to set the text shown in the log and dialogue. The default names the event.

### App Designer callbacks

Wrap the body of each callback in a `try` / `catch`, and report from the `catch`. Keep the signature App Designer generated, and keep the existing code untouched inside the `try`:

```matlab
function SomethingButtonPushed(comp, event)
    try
        % ...the existing body...
    catch err
        Palladium.Core.ErrorGuard.HandleError("Error in SomethingButtonPushed", err);
    end
end 
```

The string is shown in the log and the dialogue, so make it say where the error came from. Catch into a variable (`catch err`, not a bare `catch`), and pass that same variable to `HandleError`.

### Callbacks assigned as function handles

Where a callback is assigned as a handle there is no function body to wrap, so wrap the handle:

```matlab
comp.StartButton.ButtonPushedFcn = Palladium.Core.ErrorGuard.Wrap(@comp.StartButtonPushed, Context = "Error in StartButtonPushed"); 
```

### Leave these alone

* **`startupFcn`** runs inside the app's constructor, so an error in it is thrown to whoever created the window as an ordinary error. It is not turned into a warning, so it does not need guarding, and swallowing it would leave a half-built window. (Listeners that it creates still need `AddListener`.)
* **The close request callback** of the main window. The window is being torn down, and the error dialogue needs a live window to appear in.

### Windows outside the measurement loop

A window that does not interact with the measurement loop should not offer to stop it. Add `Standalone = true` to every guard call in that window, and `Figure = ...` so the dialogue opens in that window and not behind it on the main one:

```matlab
Palladium.Core.ErrorGuard.HandleError("Error in BrowseButtonPushed", err, Standalone = true, Figure = app.DataViewerUIFigure); 
```

`Figure` takes a figure, or any component inside one, and is resolved at the moment the error happens. A deleted or invalid window falls back to the main window, so it is safe to pass one that may have closed.

| Where the code is | `Figure` |
| --- | --- |
| An app (`matlab.apps.AppBase`) | The app's figure, e.g. `app.DataViewerUIFigure` |
| A component container panel inside the window | `comp` |
| A controller class that owns a view | The view's `GetUIFigureHandle()` if it has one - see `SequenceEditorController.CreateView` |

### Passing a Controller

By default the guards report to the Controller that registered itself, which is almost always what you want. Code that has its own reference can pass it with `Controller = this.Controller`. Inside a window's `startupFcn`, do **not** pass `app.Controller`: the Controller is attached to the window after it has been created, so it is still empty at that point. Leave the option out and the default is looked up when an error actually happens.

## If a callback is missed

Nothing gets worse. An unguarded callback behaves as it did before this was added: MATLAB prints the orange warning with a stack trace, and the programme carries on. If a callback only calls a method that is itself guarded, or fires an event whose listeners are guarded, the error is caught further down anyway. A guard only adds coverage for code in the callback's own body.

## Testing

* The guards are covered by unit tests: `test_ErrorGuard` uses a mock Controller to check the arguments pass through, errors are routed with the right options, and the fallbacks when there is no Controller never throw.
* `test_ErrorHandling` in the systems tests checks that a standalone error is logged without turning the status light red.
* The error dialogues are modal, so no test covers them. To try a new callback by hand, put a deliberate `error("TEST:ERROR", "TEST ERROR")` in it, start the measurement loop, and trigger it. You should get the Palladium error dialogue and one log entry, not an orange warning. Take the test error out again afterwards.

## Checklist for a new GUI file

1. Every `addlistener` is `ErrorGuard.AddListener` (or `AddGuardedListener` in an Instrument Control).
2. Every App Designer callback has its body in `try` / `catch err`, with `ErrorGuard.HandleError(..., err)` in the `catch`.
3. Every callback assigned as a function handle is wrapped in `ErrorGuard.Wrap`.
4. `startupFcn` and the close request callback are left unwrapped.
5. If the window is outside the measurement loop, every call has `Standalone = true` and a `Figure`.
6. The context strings read "Error in ..." and name the right callback.
7. A deliberate error in one callback produces the dialogue, and the test error has been removed again.
