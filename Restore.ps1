# One-shot restore taskbar composition
$cs = @'
using System;
using System.Runtime.InteropServices;

public static class TBRestore
{
    public const int WCA_ACCENT_POLICY = 19;
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_LAYERED = 0x80000;

    [StructLayout(LayoutKind.Sequential)]
    public struct AccentPolicy
    {
        public int AccentState;
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

    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string w);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string w);
    [DllImport("user32.dll")] public static extern int SetWindowCompositionAttribute(IntPtr h, ref WindowCompositionAttributeData d);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int n, int v);

    public static void RestoreOne(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;
        AccentPolicy p = new AccentPolicy();
        p.AccentState = 0;
        p.AccentFlags = 0;
        p.GradientColor = 0;
        int size = Marshal.SizeOf(typeof(AccentPolicy));
        IntPtr ptr = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(p, ptr, false);
            WindowCompositionAttributeData d = new WindowCompositionAttributeData();
            d.Attribute = WCA_ACCENT_POLICY;
            d.SizeOfData = size;
            d.Data = ptr;
            SetWindowCompositionAttribute(hwnd, ref d);
        }
        finally { Marshal.FreeHGlobal(ptr); }

        int ex = GetWindowLong(hwnd, GWL_EXSTYLE);
        SetWindowLong(hwnd, GWL_EXSTYLE, ex & ~WS_EX_LAYERED);
    }

    public static void Restore()
    {
        RestoreOne(FindWindow("Shell_TrayWnd", null));
        IntPtr sec = IntPtr.Zero;
        while (true)
        {
            sec = FindWindowEx(IntPtr.Zero, sec, "Shell_SecondaryTrayWnd", null);
            if (sec == IntPtr.Zero) break;
            RestoreOne(sec);
        }
    }
}
'@
Add-Type -TypeDefinition $cs -Language CSharp -ErrorAction SilentlyContinue
[TBRestore]::Restore()
Write-Host "Taskbar restored."
