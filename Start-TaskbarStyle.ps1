# TaskbarStyleTool - Win10 任务栏透明 + 图标居中
param(
    [ValidateSet('Transparent', 'Blur', 'Acrylic', 'Opaque')]
    [string]$Mode = 'Acrylic',
    [byte]$Opacity = 160,
    [switch]$NoCenter
)

$ErrorActionPreference = 'Stop'

# 使用单引号 here-string，避免 PowerShell 解析 C# 代码
$src = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class TaskbarStyle
{
    public const int WCA_ACCENT_POLICY = 19;

    public enum AccentState
    {
        ACCENT_DISABLED = 0,
        ACCENT_ENABLE_GRADIENT = 1,
        ACCENT_ENABLE_TRANSPARENTGRADIENT = 2,
        ACCENT_ENABLE_BLURBEHIND = 3,
        ACCENT_ENABLE_ACRYLICBLURBEHIND = 4
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct AccentPolicy
    {
        public AccentState AccentState;
        public int AccentFlags;
        public int GradientColor;
        public int AnimationId;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WindowCompositionAttributeData
    {
        public int Attribute;
        public IntPtr Data;
        public int SizeOfData;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
    }

    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string className, string windowName);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WindowCompositionAttributeData data);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    const uint SWP_NOSIZE = 0x0001;
    const uint SWP_NOZORDER = 0x0004;
    const uint SWP_NOACTIVATE = 0x0010;
    const uint SWP_ASYNCWINDOWPOS = 0x4000;

    public static void ApplyAccent(IntPtr hwnd, AccentState state, byte opacity)
    {
        if (hwnd == IntPtr.Zero) return;
        int color = (opacity << 24);
        AccentPolicy policy = new AccentPolicy();
        policy.AccentState = state;
        policy.AccentFlags = 2;
        policy.GradientColor = color;
        policy.AnimationId = 0;

        int size = Marshal.SizeOf(typeof(AccentPolicy));
        IntPtr policyPtr = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(policy, policyPtr, false);
            WindowCompositionAttributeData data = new WindowCompositionAttributeData();
            data.Attribute = WCA_ACCENT_POLICY;
            data.SizeOfData = size;
            data.Data = policyPtr;
            SetWindowCompositionAttribute(hwnd, ref data);
        }
        finally
        {
            Marshal.FreeHGlobal(policyPtr);
        }
    }

    static IntPtr FindChildByClass(IntPtr parent, string className)
    {
        IntPtr child = IntPtr.Zero;
        while (true)
        {
            child = FindWindowEx(parent, child, null, null);
            if (child == IntPtr.Zero) break;
            StringBuilder sb = new StringBuilder(256);
            GetClassName(child, sb, sb.Capacity);
            if (string.Equals(sb.ToString(), className, StringComparison.OrdinalIgnoreCase))
                return child;
            IntPtr nested = FindChildByClass(child, className);
            if (nested != IntPtr.Zero) return nested;
        }
        return IntPtr.Zero;
    }

    public static void StyleTaskbar(string mode, byte opacity, bool center)
    {
        AccentState state = AccentState.ACCENT_ENABLE_ACRYLICBLURBEHIND;
        string m = (mode == null ? "acrylic" : mode).ToLowerInvariant();
        if (m == "transparent") state = AccentState.ACCENT_ENABLE_TRANSPARENTGRADIENT;
        else if (m == "blur") state = AccentState.ACCENT_ENABLE_BLURBEHIND;
        else if (m == "opaque") state = AccentState.ACCENT_DISABLED;

        StyleOne(FindWindow("Shell_TrayWnd", null), state, opacity, center);
        IntPtr secondary = IntPtr.Zero;
        while (true)
        {
            secondary = FindWindowEx(IntPtr.Zero, secondary, "Shell_SecondaryTrayWnd", null);
            if (secondary == IntPtr.Zero) break;
            StyleOne(secondary, state, opacity, center);
        }
    }

    static void StyleOne(IntPtr taskbar, AccentState state, byte opacity, bool center)
    {
        if (taskbar == IntPtr.Zero) return;
        ApplyAccent(taskbar, state, opacity);
        if (!center) return;

        IntPtr taskList = FindChildByClass(taskbar, "MSTaskListWClass");
        if (taskList == IntPtr.Zero) return;

        RECT barRect;
        RECT listRect;
        if (!GetWindowRect(taskbar, out barRect)) return;
        if (!GetWindowRect(taskList, out listRect)) return;

        int barW = barRect.Width;
        int listW = listRect.Width;
        if (barW <= 0 || listW <= 0 || listW >= barW) return;

        IntPtr parent = FindWindowEx(taskbar, IntPtr.Zero, "ReBarWindow32", null);
        if (parent == IntPtr.Zero) parent = taskbar;

        RECT parentRect;
        if (!GetWindowRect(parent, out parentRect)) return;

        int targetScreenX = barRect.Left + (barW - listW) / 2;
        int newX = targetScreenX - parentRect.Left;
        int curX = listRect.Left - parentRect.Left;
        int curY = listRect.Top - parentRect.Top;

        if (Math.Abs(curX - newX) > 2)
        {
            SetWindowPos(taskList, IntPtr.Zero, newX, curY, 0, 0,
                SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS);
        }
    }
}
'@

try {
    Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop
} catch {
    if ($_.Exception.Message -notmatch 'already exists') { throw }
}

Write-Host "TaskbarStyleTool started: D:\TaskbarStyleTool"
Write-Host ("Mode={0} Opacity={1} Center={2}" -f $Mode, $Opacity, (-not $NoCenter))
Write-Host "Press Ctrl+C to stop."

$center = -not $NoCenter
try {
    while ($true) {
        [TaskbarStyle]::StyleTaskbar($Mode, $Opacity, $center)
        Start-Sleep -Milliseconds 400
    }
} finally {
    [TaskbarStyle]::StyleTaskbar('Opaque', 255, $false)
    Write-Host "Stopped."
}
