# Describe every top-level window owned by Raycast, so the toggle's z-order walk can be designed
# against facts: does the launcher's window look like a "real" window to that walk?
$ErrorActionPreference = 'Continue'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class WProbe {
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
    [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int index);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int max);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hWnd);

    public static IntPtr[] All()
    {
        List<IntPtr> found = new List<IntPtr>();
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) { found.Add(hWnd); return true; }, IntPtr.Zero);
        return found.ToArray();
    }
}
'@

function Get-Describe([IntPtr]$handle, [string]$label) {
    $ownerPid = 0
    [void][WProbe]::GetWindowThreadProcessId($handle, [ref]$ownerPid)
    $title = ''
    $length = [WProbe]::GetWindowTextLength($handle)
    if ($length -gt 0) {
        $sb = [System.Text.StringBuilder]::new($length + 2)
        [void][WProbe]::GetWindowText($handle, $sb, $sb.Capacity)
        $title = $sb.ToString()
    }
    $ex = [WProbe]::GetWindowLongPtr($handle, -20).ToInt64()
    $style = [WProbe]::GetWindowLongPtr($handle, -16).ToInt64()
    $owner = [WProbe]::GetWindow($handle, 4)
    "$label hwnd=$($handle.ToInt64()) pid=$ownerPid visible=$([WProbe]::IsWindowVisible($handle)) iconic=$([WProbe]::IsIconic($handle)) owner=$($owner.ToInt64()) tool=$([bool]($ex -band 0x80)) appwindow=$([bool]($ex -band 0x40000)) titled=$([bool]($style -band 0xC00000)) titleLen=$length title='$title'"
}

'=== processes named Raycast* ==='
$rayPids = @(Get-Process -Name 'Raycast*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
"pids: $($rayPids -join ', ')"

'=== their top-level windows ==='
foreach ($h in [WProbe]::All()) {
    $ownerPid = 0
    [void][WProbe]::GetWindowThreadProcessId($h, [ref]$ownerPid)
    if ($rayPids -contains $ownerPid) { Get-Describe $h '  RAYCAST' }
}

'=== foreground now ==='
Get-Describe ([WProbe]::GetForegroundWindow()) '  FG'

'=== first 6 visible, unowned, titled top-level windows in z-order ==='
$h = [WProbe]::GetTopWindow([IntPtr]::Zero)
$i = 0
$shown = 0
while ($h -ne [IntPtr]::Zero -and $shown -lt 6 -and $i -lt 400) {
    if ([WProbe]::IsWindowVisible($h) -and [WProbe]::GetWindow($h, 4) -eq [IntPtr]::Zero -and [WProbe]::GetWindowTextLength($h) -gt 0) {
        Get-Describe $h '  REAL'
        $shown++
    }
    $h = [WProbe]::GetWindow($h, 2)
    $i++
}
