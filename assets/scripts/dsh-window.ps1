<#
.SYNOPSIS
    Window control for the DeepSeek Harness desktop shell.

.DESCRIPTION
    The DeepSeek Harness Electron shell registers no global shortcut of its own, and its
    single-instance / `dsh://open` path does not restore a window that was already hidden
    (the shell's own close button only hides it to the notification area). This helper
    drives the shell's top-level window directly through Win32 so a launcher can toggle it.

    The Win32 entry points live in the C# program embedded below. The first run compiles it
    to `%LOCALAPPDATA%\RaycastDsh\dsh-window.exe`; later runs execute that cached binary, which
    keeps a global hotkey responsive. When compilation is impossible the same code is loaded
    in-process with Add-Type instead, so the helper degrades rather than fails.

    Output is one JSON object on stdout. Exit codes: 0 success, 1 error, 2 nothing to do.

.PARAMETER Action
    status   report the current state and change nothing
    show     reveal, restore and focus the window (launches the app when needed)
    hide     hide the window to the notification area
    toggle   hide when the window is the one the user is looking at, otherwise reveal and focus it
    focus    alias of show

.PARAMETER ProcessName
    Image name of the shell, without extension.

.PARAMETER ExecutablePath
    Full path to the shell executable, used when it has to be launched. When empty the
    helper falls back to the registered `dsh://` protocol.

.PARAMETER WaitMs
    How long the helper may wait for a window after launching the app.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'show', 'hide', 'toggle', 'focus')]
    [string]$Action = 'status',

    [Parameter(Position = 1)]
    [string]$ProcessName = 'DeepSeek Harness',

    [Parameter(Position = 2)]
    [string]$ExecutablePath = '',

    [Parameter(Position = 3)]
    [int]$WaitMs = 0
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class DshWindowNative
{
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hWnd, uint command);
    [DllImport("user32.dll")]
    private static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);
    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    private static extern bool AttachThreadInput(uint attach, uint attachTo, bool attachFlag);
    [DllImport("user32.dll")]
    private static extern void SwitchToThisWindow(IntPtr hWnd, bool altTab);
    [DllImport("user32.dll")]
    private static extern void keybd_event(byte virtualKey, byte scanCode, uint flags, UIntPtr extraInfo);
    [DllImport("user32.dll")]
    private static extern IntPtr GetTopWindow(IntPtr hWnd);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll")]
    private static extern bool IsZoomed(IntPtr hWnd);
    [DllImport("user32.dll")]
    private static extern bool GetWindowPlacement(IntPtr hWnd, ref WindowPlacement placement);
    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    public const int SwHide = 0;
    public const int SwMaximize = 3;
    public const int SwShow = 5;
    public const int SwRestore = 9;
    private const uint GwOwner = 4;
    private const uint GwHwndNext = 2;
    private const int GwlExStyle = -20;
    private const int WsExToolWindow = 0x00000080;
    private const int WpfRestoreToMaximized = 0x00000002;
    private const byte VkMenu = 0x12;
    private const uint KeyEventKeyUp = 0x0002;

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WindowPlacement
    {
        public int length;
        public int flags;
        public int showCmd;
        public Point minPosition;
        public Point maxPosition;
        public Rect normalPosition;
    }

    /// <summary>Top-level, unowned, titled windows owned by one process.</summary>
    public static List<IntPtr> WindowsOf(uint processId)
    {
        List<IntPtr> found = new List<IntPtr>();
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
        {
            uint owner;
            GetWindowThreadProcessId(hWnd, out owner);
            if (owner != processId) return true;
            if (GetWindow(hWnd, GwOwner) != IntPtr.Zero) return true;
            if (GetWindowTextLength(hWnd) == 0) return true;
            found.Add(hWnd);
            return true;
        }, IntPtr.Zero);
        return found;
    }

    /// <summary>Largest window by area: the shell's main window rather than a transient popup.</summary>
    public static IntPtr Largest(List<IntPtr> windows)
    {
        IntPtr best = IntPtr.Zero;
        long bestArea = -1;
        foreach (IntPtr hWnd in windows)
        {
            Rect rect;
            if (!GetWindowRect(hWnd, out rect)) continue;
            long area = (long)(rect.Right - rect.Left) * (long)(rect.Bottom - rect.Top);
            if (area > bestArea)
            {
                bestArea = area;
                best = hWnd;
            }
        }
        return best;
    }

    public static uint OwningProcess(IntPtr hWnd)
    {
        uint owner;
        GetWindowThreadProcessId(hWnd, out owner);
        return owner;
    }

    public static bool IsVisible(IntPtr hWnd) { return IsWindowVisible(hWnd); }
    public static bool IsMinimized(IntPtr hWnd) { return IsIconic(hWnd); }
    public static bool IsForeground(IntPtr hWnd) { return GetForegroundWindow() == hWnd; }

    /// <summary>
    /// Apply one ShowWindow command so that it always takes effect.
    ///
    /// Windows replaces the very first ShowWindow call a process makes with the wShowWindow value
    /// from its STARTUPINFO, whenever the creator supplied STARTF_USESHOWWINDOW. Node's
    /// `windowsHide: true` sets exactly that, with SW_HIDE, so a single call would be silently
    /// discarded. The command is idempotent, so issuing it twice costs nothing and guarantees the
    /// intended state is the one that survives.
    /// </summary>
    private static void ApplyShowState(IntPtr hWnd, int command)
    {
        ShowWindow(hWnd, command);
        ShowWindow(hWnd, command);
    }

    public static string TitleOf(IntPtr hWnd)
    {
        int length = GetWindowTextLength(hWnd);
        if (length <= 0) return string.Empty;
        StringBuilder buffer = new StringBuilder(length + 1);
        GetWindowText(hWnd, buffer, buffer.Capacity);
        return buffer.ToString();
    }

    public static void Hide(IntPtr hWnd)
    {
        ApplyShowState(hWnd, SwHide);
    }

    /// <summary>
    /// Whether this window is the one the user is actually looking at.
    ///
    /// The foreground window alone cannot answer this: a launcher that invoked this helper owns the
    /// foreground while its heads-up display is on screen. Walking the z-order and skipping windows
    /// that are not real application windows — invisible, minimized, owned, captionless or tool
    /// windows — lands on whatever the user was looking at before the launcher appeared. Raycast's
    /// own window is a captionless tool window, so it drops out of the walk without this helper
    /// having to know which launcher called it.
    /// </summary>
    public static bool IsFrontWindow(IntPtr hWnd)
    {
        if (!IsWindowVisible(hWnd) || IsIconic(hWnd)) return false;

        for (IntPtr candidate = GetTopWindow(IntPtr.Zero); candidate != IntPtr.Zero; candidate = GetWindow(candidate, GwHwndNext))
        {
            if (!IsWindowVisible(candidate)) continue;
            if (IsIconic(candidate)) continue;
            if (GetWindow(candidate, GwOwner) != IntPtr.Zero) continue;
            if ((GetWindowLong(candidate, GwlExStyle) & WsExToolWindow) != 0) continue;
            if (GetWindowTextLength(candidate) == 0) continue;
            return candidate == hWnd;
        }
        return false;
    }

    /// <summary>
    /// Reveal a hidden or minimized window and take the foreground. Windows refuses
    /// SetForegroundWindow unless the calling thread shares its input queue with the current
    /// foreground thread, so both threads are attached for the duration of the attempt; when
    /// even that is refused the classic keyless ALT press makes this thread eligible again.
    ///
    /// A visible window is never passed through ShowWindow here: it is already in whatever shape
    /// the user left it, and re-showing it is what used to drop a maximized window back to normal
    /// size.
    /// </summary>
    public static bool Activate(IntPtr hWnd)
    {
        if (IsIconic(hWnd))
        {
            bool restoreToMaximized = WasMaximized(hWnd);
            ApplyShowState(hWnd, SwRestore);
            // SW_RESTORE returns a maximized window to its normal size, so a window that was
            // maximized before it was minimized has to be maximized again.
            if (restoreToMaximized && !IsZoomed(hWnd)) ApplyShowState(hWnd, SwMaximize);
        }
        else if (!IsWindowVisible(hWnd))
        {
            ApplyShowState(hWnd, SwShow);
        }

        if (TryTakeForeground(hWnd)) return true;

        keybd_event(VkMenu, 0, 0, UIntPtr.Zero);
        keybd_event(VkMenu, 0, KeyEventKeyUp, UIntPtr.Zero);
        return TryTakeForeground(hWnd);
    }

    /// <summary>Whether a minimized window should come back maximized.</summary>
    private static bool WasMaximized(IntPtr hWnd)
    {
        if (IsZoomed(hWnd)) return true;
        WindowPlacement placement = new WindowPlacement();
        placement.length = Marshal.SizeOf(typeof(WindowPlacement));
        if (!GetWindowPlacement(hWnd, ref placement)) return false;
        return (placement.flags & WpfRestoreToMaximized) != 0;
    }

    private static bool TryTakeForeground(IntPtr hWnd)
    {
        uint ignored;
        IntPtr foreground = GetForegroundWindow();
        uint currentThread = GetCurrentThreadId();
        uint foregroundThread = foreground == IntPtr.Zero ? 0 : GetWindowThreadProcessId(foreground, out ignored);
        uint targetThread = GetWindowThreadProcessId(hWnd, out ignored);

        bool attachedForeground = false;
        bool attachedTarget = false;
        if (foregroundThread != 0 && foregroundThread != currentThread)
            attachedForeground = AttachThreadInput(currentThread, foregroundThread, true);
        if (targetThread != 0 && targetThread != currentThread)
            attachedTarget = AttachThreadInput(currentThread, targetThread, true);
        try
        {
            BringWindowToTop(hWnd);
            SetForegroundWindow(hWnd);
            if (GetForegroundWindow() != hWnd) SwitchToThisWindow(hWnd, true);
        }
        finally
        {
            if (attachedTarget) AttachThreadInput(currentThread, targetThread, false);
            if (attachedForeground) AttachThreadInput(currentThread, foregroundThread, false);
        }
        return GetForegroundWindow() == hWnd;
    }
}

public static class DshWindowProgram
{
    private sealed class Snapshot
    {
        public Process[] Processes = new Process[0];
        public int ProcessId;
        public IntPtr Handle = IntPtr.Zero;
        public bool Running;
        public bool HasWindow;
        public string State = "not-running";
        public string Title = string.Empty;
        public string Executable = string.Empty;

        public bool Visible
        {
            get { return HasWindow && DshWindowNative.IsVisible(Handle); }
        }

        public bool Minimized
        {
            get { return HasWindow && DshWindowNative.IsMinimized(Handle); }
        }

        public bool Foreground
        {
            get { return HasWindow && DshWindowNative.IsForeground(Handle); }
        }

        /// <summary>Whether this window is the one the user is looking at, launcher windows aside.</summary>
        public bool InFront
        {
            get { return HasWindow && DshWindowNative.IsFrontWindow(Handle); }
        }
    }

    public static int Main(string[] args)
    {
        string json = Run(args);
        Console.Out.Write(json);
        Console.Out.Flush();
        if (json.IndexOf("\"ok\":false", StringComparison.Ordinal) >= 0) return 1;
        if (json.IndexOf("\"result\":\"noop\"", StringComparison.Ordinal) >= 0) return 2;
        return 0;
    }

    /// <summary>Perform one action and return its result as a single JSON object.</summary>
    public static string Run(string[] args)
    {
        string action = args.Length > 0 && args[0].Length > 0 ? args[0].ToLowerInvariant() : "status";
        string processName = args.Length > 1 && args[1].Length > 0 ? args[1] : "DeepSeek Harness";
        string executable = args.Length > 2 ? args[2] : string.Empty;
        int waitMs = 0;
        if (args.Length > 3) int.TryParse(args[3], out waitMs);

        if (action == "focus") action = "show";

        try
        {
            Snapshot snapshot = Capture(processName);

            if (!snapshot.Running)
            {
                if (action == "status" || action == "hide")
                    return Report(action, "noop", snapshot, "the shell is not running");
                Launch(executable);
                Snapshot launched = WaitForWindow(processName, waitMs > 0 ? waitMs : 15000);
                if (!launched.HasWindow)
                    return Report(action, "noop", launched, "the shell started but exposed no window");
                DshWindowNative.Activate(launched.Handle);
                return Report(action, "launched", Capture(processName), "the shell was launched");
            }

            if (!snapshot.HasWindow)
                return Report(action, "noop", snapshot, "the shell is running without a top-level window");

            switch (action)
            {
                case "status":
                    return Report(action, "reported", snapshot, "reported the current window state");
                case "hide":
                {
                    DshWindowNative.Hide(snapshot.Handle);
                    Thread.Sleep(120);
                    Snapshot after = Capture(processName);
                    return after.Visible
                        ? Report(action, "noop", after, "the window could not be hidden")
                        : Report(action, "hidden", after, "the window was hidden to the notification area");
                }
                case "show":
                {
                    DshWindowNative.Activate(snapshot.Handle);
                    Thread.Sleep(120);
                    Snapshot after = Capture(processName);
                    return after.Visible
                        ? Report(action, "shown", after, "the window was revealed")
                        : Report(action, "noop", after, "the window could not be revealed");
                }
                case "toggle":
                {
                    if (DshWindowNative.IsFrontWindow(snapshot.Handle))
                    {
                        DshWindowNative.Hide(snapshot.Handle);
                        Thread.Sleep(120);
                        Snapshot hidden = Capture(processName);
                        return hidden.Visible
                            ? Report(action, "noop", hidden, "the window could not be hidden")
                            : Report(action, "hidden", hidden, "the foreground window was hidden");
                    }
                    DshWindowNative.Activate(snapshot.Handle);
                    Thread.Sleep(120);
                    Snapshot shown = Capture(processName);
                    return shown.Visible
                        ? Report(action, "shown", shown, "the window was revealed and focused")
                        : Report(action, "noop", shown, "the window could not be revealed");
                }
                default:
                    return Error(action, "unknown action: " + action);
            }
        }
        catch (Exception error)
        {
            return Error(action, error.GetType().Name + ": " + error.Message);
        }
    }

    private static Snapshot Capture(string processName)
    {
        Snapshot snapshot = new Snapshot();
        Process[] processes = Process.GetProcessesByName(processName);
        snapshot.Processes = processes;
        snapshot.Running = processes.Length > 0;
        if (!snapshot.Running) return snapshot;

        List<IntPtr> windows = new List<IntPtr>();
        foreach (Process process in processes)
        {
            windows.AddRange(DshWindowNative.WindowsOf((uint)process.Id));
        }
        if (windows.Count == 0) return snapshot;

        IntPtr handle = DshWindowNative.Largest(windows);
        snapshot.Handle = handle;
        snapshot.HasWindow = true;
        snapshot.Title = DshWindowNative.TitleOf(handle);
        snapshot.ProcessId = (int)DshWindowNative.OwningProcess(handle);

        foreach (Process process in processes)
        {
            if (process.Id != snapshot.ProcessId) continue;
            try { snapshot.Executable = process.MainModule.FileName; }
            catch (Exception) { snapshot.Executable = string.Empty; }
            break;
        }

        if (DshWindowNative.IsMinimized(handle)) snapshot.State = "minimized";
        else if (DshWindowNative.IsVisible(handle) && DshWindowNative.IsForeground(handle)) snapshot.State = "active";
        else if (DshWindowNative.IsVisible(handle)) snapshot.State = "visible";
        else snapshot.State = "hidden";
        return snapshot;
    }

    private static Snapshot WaitForWindow(string processName, int waitMs)
    {
        Stopwatch clock = Stopwatch.StartNew();
        Snapshot snapshot = Capture(processName);
        while (!snapshot.HasWindow && clock.ElapsedMilliseconds < waitMs)
        {
            Thread.Sleep(150);
            snapshot = Capture(processName);
        }
        return snapshot;
    }

    private static void Launch(string executable)
    {
        if (executable.Length > 0 && System.IO.File.Exists(executable))
        {
            ProcessStartInfo info = new ProcessStartInfo(executable);
            info.UseShellExecute = true;
            info.WorkingDirectory = System.IO.Path.GetDirectoryName(executable);
            Process.Start(info);
            return;
        }
        ProcessStartInfo protocol = new ProcessStartInfo("dsh://open");
        protocol.UseShellExecute = true;
        Process.Start(protocol);
    }

    private static string Report(string action, string result, Snapshot snapshot, string message)
    {
        StringBuilder json = new StringBuilder();
        json.Append("{\"ok\":true");
        json.Append(",\"action\":").Append(Encode(action));
        json.Append(",\"result\":").Append(Encode(result));
        json.Append(",\"state\":").Append(Encode(snapshot.State));
        json.Append(",\"running\":").Append(snapshot.Running ? "true" : "false");
        json.Append(",\"processCount\":").Append(snapshot.Processes.Length);
        json.Append(",\"processId\":").Append(snapshot.ProcessId);
        json.Append(",\"hasWindow\":").Append(snapshot.HasWindow ? "true" : "false");
        json.Append(",\"hwnd\":").Append(snapshot.HasWindow ? snapshot.Handle.ToInt64().ToString() : "0");
        json.Append(",\"visible\":").Append(snapshot.Visible ? "true" : "false");
        json.Append(",\"minimized\":").Append(snapshot.Minimized ? "true" : "false");
        json.Append(",\"foreground\":").Append(snapshot.Foreground ? "true" : "false");
        json.Append(",\"inFront\":").Append(snapshot.InFront ? "true" : "false");
        json.Append(",\"title\":").Append(Encode(snapshot.Title));
        json.Append(",\"executable\":").Append(Encode(snapshot.Executable));
        json.Append(",\"message\":").Append(Encode(message));
        json.Append("}");
        return json.ToString();
    }

    private static string Error(string action, string message)
    {
        return "{\"ok\":false,\"action\":" + Encode(action) + ",\"message\":" + Encode(message) + "}";
    }

    private static string Encode(string value)
    {
        if (value == null) return "null";
        StringBuilder builder = new StringBuilder("\"");
        foreach (char character in value)
        {
            switch (character)
            {
                case '"': builder.Append("\\\""); break;
                case '\\': builder.Append("\\\\"); break;
                case '\n': builder.Append("\\n"); break;
                case '\r': builder.Append("\\r"); break;
                case '\t': builder.Append("\\t"); break;
                default:
                    if (character < ' ') builder.Append("\\u").Append(((int)character).ToString("x4"));
                    else builder.Append(character);
                    break;
            }
        }
        builder.Append("\"");
        return builder.ToString();
    }
}
'@

$cacheDir = Join-Path $env:LOCALAPPDATA 'RaycastDsh'
$cachedExe = Join-Path $cacheDir 'dsh-window.exe'
$cachedHash = Join-Path $cacheDir 'dsh-window.sha256'

$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $fingerprint = [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($source))).Replace('-', '')
} finally {
    $sha.Dispose()
}

function Get-CachedFingerprint {
    if (-not (Test-Path -LiteralPath $cachedHash)) { return '' }
    try { return (Get-Content -LiteralPath $cachedHash -Raw).Trim() } catch { return '' }
}

function Build-CachedExecutable {
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    $temporary = Join-Path $cacheDir ('dsh-window.' + [System.Guid]::NewGuid().ToString('N') + '.exe')
    try {
        Add-Type -TypeDefinition $source -OutputAssembly $temporary -OutputType ConsoleApplication -Language CSharp
        Move-Item -LiteralPath $temporary -Destination $cachedExe -Force
        Set-Content -LiteralPath $cachedHash -Value $fingerprint -Encoding Ascii -NoNewline
        return $true
    } catch {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

# Fast path: the fingerprint matches, so the cached binary is current. A missing binary
# or a changed source compiles once; only when that fails is the code loaded in-process.
$ready = $false
if ((Test-Path -LiteralPath $cachedExe) -and ((Get-CachedFingerprint) -eq $fingerprint)) {
    $ready = $true
} elseif (Build-CachedExecutable) {
    $ready = $true
}

if ($ready) {
    & $cachedExe $Action $ProcessName $ExecutablePath $WaitMs
    exit $LASTEXITCODE
}

Add-Type -TypeDefinition $source -Language CSharp
$json = [DshWindowProgram]::Run([string[]]@($Action, $ProcessName, $ExecutablePath, [string]$WaitMs))
[Console]::Out.Write($json)
if ($json -like '*"ok":false*') { exit 1 }
if ($json -like '*"result":"noop"*') { exit 2 }
exit 0
