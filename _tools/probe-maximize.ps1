# Reproduce the reported bug end to end:
#   maximize the DSH window -> minimize it -> run the helper's `show` -> is it maximized again?
$ErrorActionPreference = 'Continue'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class MProbe {
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT placement);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);

    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct WINDOWPLACEMENT {
        public int length; public int flags; public int showCmd;
        public POINT minPosition; public POINT maxPosition; public RECT normalPosition;
    }

    public static IntPtr FindLargest(uint processId) {
        List<IntPtr> found = new List<IntPtr>();
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            uint owner; GetWindowThreadProcessId(h, out owner);
            if (owner != processId) return true;
            if (GetWindow(h, 4) != IntPtr.Zero) return true;
            if (GetWindowTextLength(h) == 0) return true;
            found.Add(h); return true;
        }, IntPtr.Zero);
        IntPtr best = IntPtr.Zero; long bestArea = -1;
        foreach (IntPtr h in found) {
            RECT r; if (!GetWindowRect(h, out r)) continue;
            long area = (long)(r.Right - r.Left) * (r.Bottom - r.Top);
            if (area > bestArea) { bestArea = area; best = h; }
        }
        return best;
    }
}
'@

function Get-Report([string]$label, [IntPtr]$handle) {
    $placement = New-Object 'MProbe+WINDOWPLACEMENT'
    $placement.length = [System.Runtime.InteropServices.Marshal]::SizeOf([type]'MProbe+WINDOWPLACEMENT')
    [void][MProbe]::GetWindowPlacement($handle, [ref]$placement)
    $restoreToMax = [bool]($placement.flags -band 0x00000002)
    "$label visible=$([MProbe]::IsWindowVisible($handle)) iconic=$([MProbe]::IsIconic($handle)) zoomed=$([MProbe]::IsZoomed($handle)) showCmd=$($placement.showCmd) restoreToMaximized=$restoreToMax"
}

$exe = Join-Path $env:LOCALAPPDATA 'RaycastDsh\dsh-window.exe'
# The window belongs to whichever of the shell's processes owns it, not necessarily the first one
# the process list returns, so every process is searched.
$handle = [IntPtr]::Zero
foreach ($candidate in @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue)) {
    $found = [MProbe]::FindLargest([uint32]$candidate.Id)
    if ($found -ne [IntPtr]::Zero) { $handle = $found; break }
}
"hwnd=$($handle.ToInt64())"
if ($handle -eq [IntPtr]::Zero) { throw 'no DSH window found' }

'--- step 1: maximize ---'
[void][MProbe]::ShowWindow($handle, 3)   # SW_MAXIMIZE
Start-Sleep -Milliseconds 600
Get-Report '  ' $handle

'--- step 2: minimize ---'
[void][MProbe]::ShowWindow($handle, 6)   # SW_MINIMIZE
Start-Sleep -Milliseconds 600
Get-Report '  ' $handle

'--- step 3: helper show ---'
& $exe show 'DeepSeek Harness' '' 0 | ConvertFrom-Json | ForEach-Object { "  result=$($_.result) state=$($_.state)" }
Start-Sleep -Milliseconds 500
Get-Report '  ' $handle

'--- step 4: helper toggle (window is now in front, so it must hide) ---'
& $exe toggle 'DeepSeek Harness' '' 0 | ConvertFrom-Json | ForEach-Object { "  result=$($_.result) state=$($_.state) inFront=$($_.inFront)" }
Start-Sleep -Milliseconds 400
Get-Report '  ' $handle
