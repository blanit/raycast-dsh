# Decide-test for toggle: put a specific window in front, then run toggle and see which way it goes.
#
#   scenario A  a real application window is in front  -> toggle must REVEAL DSH
#   scenario B  Raycast's captionless tool window is in front -> toggle must HIDE DSH
#
# Scenario B is the hotkey moment: Raycast owns the foreground while its heads-up display is up.
$ErrorActionPreference = 'Continue'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class FProbe {
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int index);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder t, int m);

    public static bool ForceForeground(IntPtr hWnd) {
        if (IsIconic(hWnd)) return false;
        uint ignored;
        IntPtr fg = GetForegroundWindow();
        uint current = GetCurrentThreadId();
        uint fgThread = fg == IntPtr.Zero ? 0 : GetWindowThreadProcessId(fg, out ignored);
        uint target = GetWindowThreadProcessId(hWnd, out ignored);
        bool a = false, b = false;
        if (fgThread != 0 && fgThread != current) a = AttachThreadInput(current, fgThread, true);
        if (target != 0 && target != current) b = AttachThreadInput(current, target, true);
        try {
            BringWindowToTop(hWnd);
            SetForegroundWindow(hWnd);
            if (GetForegroundWindow() != hWnd) {
                keybd_event(0x12, 0, 0, UIntPtr.Zero);
                keybd_event(0x12, 0, 2, UIntPtr.Zero);
                SetForegroundWindow(hWnd);
            }
        } finally {
            if (b) AttachThreadInput(current, target, false);
            if (a) AttachThreadInput(current, fgThread, false);
        }
        return GetForegroundWindow() == hWnd;
    }

    /// <summary>First visible, unowned, titled, non-tool top-level window of a process.</summary>
    public static IntPtr RealWindowOf(uint processId) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            uint owner; GetWindowThreadProcessId(h, out owner);
            if (owner != processId) return true;
            if (!IsWindowVisible(h) || IsIconic(h)) return true;
            if (GetWindow(h, 4) != IntPtr.Zero) return true;
            if ((GetWindowLongPtr(h, -20).ToInt64() & 0x80) != 0) return true;
            if (GetWindowTextLength(h) == 0) return true;
            found = h; return false;
        }, IntPtr.Zero);
        return found;
    }

    /// <summary>Raycast's heads-up window: visible, unowned, captionless tool window.</summary>
    public static IntPtr ToolWindowOf(uint processId) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            uint owner; GetWindowThreadProcessId(h, out owner);
            if (owner != processId) return true;
            if (!IsWindowVisible(h)) return true;
            if (GetWindow(h, 4) != IntPtr.Zero) return true;
            if ((GetWindowLongPtr(h, -20).ToInt64() & 0x80) == 0) return true;
            found = h; return false;
        }, IntPtr.Zero);
        return found;
    }
}
'@

$exe = Join-Path $env:LOCALAPPDATA 'RaycastDsh\dsh-window.exe'

function Get-Name([IntPtr]$handle) {
    if ($handle -eq [IntPtr]::Zero) { return '(none)' }
    $ownerPid = 0
    [void][FProbe]::GetWindowThreadProcessId($handle, [ref]$ownerPid)
    $proc = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
    $length = [FProbe]::GetWindowTextLength($handle)
    $sb = [System.Text.StringBuilder]::new($length + 2)
    [void][FProbe]::GetWindowText($handle, $sb, $sb.Capacity)
    "$($proc.ProcessName) [$($sb.ToString())]"
}

function Invoke-Toggle([string]$label) {
    "### $label"
    "  foreground before : $(Get-Name ([FProbe]::GetForegroundWindow()))"
    $report = & $exe toggle 'DeepSeek Harness' '' 0 | ConvertFrom-Json
    "  toggle            : result=$($report.result) state=$($report.state)"
    Start-Sleep -Milliseconds 400
    return $report.result
}

# --- scenario A: a real application window in front ---
& $exe show 'DeepSeek Harness' '' 0 | Out-Null
Start-Sleep -Milliseconds 400
Start-Process notepad.exe
Start-Sleep -Seconds 2
$notepad = $null
foreach ($p in @(Get-Process -Name notepad -ErrorAction SilentlyContinue)) {
    $h = [FProbe]::RealWindowOf([uint32]$p.Id)
    if ($h -ne [IntPtr]::Zero) { $notepad = $h; break }
}
$placed = [FProbe]::ForceForeground($notepad)
"setup: notepad in front = $placed"
Start-Sleep -Milliseconds 400
$resultA = Invoke-Toggle 'scenario A - real app in front (expect shown)'
Stop-Process -Name notepad -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# --- scenario B: Raycast's tool window in front, DSH behind ---
& $exe show 'DeepSeek Harness' '' 0 | Out-Null
Start-Sleep -Milliseconds 400
$raycastTool = [IntPtr]::Zero
foreach ($p in @(Get-Process -Name 'Raycast' -ErrorAction SilentlyContinue)) {
    $h = [FProbe]::ToolWindowOf([uint32]$p.Id)
    if ($h -ne [IntPtr]::Zero) { $raycastTool = $h; break }
}
$placed = [FProbe]::ForceForeground($raycastTool)
"setup: raycast tool window in front = $placed ($(Get-Name $raycastTool))"
Start-Sleep -Milliseconds 400
$resultB = Invoke-Toggle 'scenario B - Raycast tool window in front (expect hidden)'

''
"A: $resultA   (want shown)"
"B: $resultB   (want hidden)"
