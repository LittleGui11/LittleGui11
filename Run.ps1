# TaskbarStyleTool - registry opacity + composition (default alpha=0)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$cs = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;

public static class TB
{
    public const int WCA_ACCENT_POLICY = 19;
    public const int HWND_BROADCAST = 0xffff;
    public const int WM_SETTINGCHANGE = 0x001A;
    public const int SMTO_ABORTIFHUNG = 0x0002;

    public enum AccentState
    {
        DISABLED = 0,
        GRADIENT = 1,
        TRANSPARENTGRADIENT = 2,
        BLURBEHIND = 3,
        ACRYLICBLURBEHIND = 4
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
        public int Left, Top, Right, Bottom;
        public int W { get { return Right - Left; } }
        public int H { get { return Bottom - Top; } }
    }

    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string w);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string w);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr i, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern int SetWindowCompositionAttribute(IntPtr h, ref WindowCompositionAttributeData d);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);

    static IntPtr FindChild(IntPtr parent, string className)
    {
        IntPtr child = IntPtr.Zero;
        while (true)
        {
            child = FindWindowEx(parent, child, null, null);
            if (child == IntPtr.Zero) return IntPtr.Zero;
            StringBuilder sb = new StringBuilder(256);
            GetClassName(child, sb, sb.Capacity);
            if (string.Equals(sb.ToString(), className, StringComparison.OrdinalIgnoreCase)) return child;
            IntPtr n = FindChild(child, className);
            if (n != IntPtr.Zero) return n;
        }
    }

    public static string Diagnose()
    {
        IntPtr tray = FindWindow("Shell_TrayWnd", null);
        if (tray == IntPtr.Zero) return "FAIL: Shell_TrayWnd not found";
        IntPtr list = FindChild(tray, "MSTaskListWClass");
        RECT tr, lr;
        GetWindowRect(tray, out tr);
        int acrylic = -1;
        try
        {
            object v = Registry.GetValue(
                @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced",
                "TaskbarAcrylicOpacity", -1);
            if (v != null) acrylic = Convert.ToInt32(v);
        }
        catch { }
        string msg = "Tray OK size=" + tr.W + "x" + tr.H + " | RegOpacity=" + acrylic;
        if (list == IntPtr.Zero) return msg + " | TaskList NOT found";
        GetWindowRect(list, out lr);
        return msg + " | TaskList " + lr.W + "x" + lr.H;
    }

    public static void SetRegistryOpacity(int opacity)
    {
        if (opacity < 0) opacity = 0;
        if (opacity > 255) opacity = 255;

        Registry.SetValue(
            @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
            "EnableTransparency", 1, RegistryValueKind.DWord);

        Registry.SetValue(
            @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced",
            "TaskbarAcrylicOpacity", opacity, RegistryValueKind.DWord);

        IntPtr result;
        SendMessageTimeout((IntPtr)HWND_BROADCAST, (uint)WM_SETTINGCHANGE, IntPtr.Zero,
            "ImmersiveColorSet", SMTO_ABORTIFHUNG, 2000, out result);
        SendMessageTimeout((IntPtr)HWND_BROADCAST, (uint)WM_SETTINGCHANGE, IntPtr.Zero,
            "TraySettings", SMTO_ABORTIFHUNG, 2000, out result);
    }

    public static int ApplyAccent(IntPtr hwnd, AccentState state, byte alpha, int flags)
    {
        if (hwnd == IntPtr.Zero) return -1;
        // Win10 often ignores alpha=0 as "disabled"; use 1 for fully-clear look
        byte a = alpha;
        if (state == AccentState.TRANSPARENTGRADIENT && a == 0) a = 1;

        AccentPolicy p = new AccentPolicy();
        p.AccentState = state;
        p.AccentFlags = flags;
        p.GradientColor = (a << 24); // ABGR, RGB=0
        int size = Marshal.SizeOf(typeof(AccentPolicy));
        IntPtr ptr = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(p, ptr, false);
            WindowCompositionAttributeData d = new WindowCompositionAttributeData();
            d.Attribute = WCA_ACCENT_POLICY;
            d.SizeOfData = size;
            d.Data = ptr;
            return SetWindowCompositionAttribute(hwnd, ref d);
        }
        finally { Marshal.FreeHGlobal(ptr); }
    }

    public static void ApplyComposition(byte alpha, int style)
    {
        AccentState st = AccentState.TRANSPARENTGRADIENT;
        int flags = 2;
        if (style == 1) { st = AccentState.BLURBEHIND; flags = 0x13; }
        if (style == 2) { st = AccentState.ACRYLICBLURBEHIND; flags = 0; }

        ApplyAccent(FindWindow("Shell_TrayWnd", null), st, alpha, flags);
        IntPtr sec = IntPtr.Zero;
        while (true)
        {
            sec = FindWindowEx(IntPtr.Zero, sec, "Shell_SecondaryTrayWnd", null);
            if (sec == IntPtr.Zero) break;
            ApplyAccent(sec, st, alpha, flags);
        }
    }

    public static void Apply(byte alpha, int style)
    {
        SetRegistryOpacity(alpha);
        ApplyComposition(alpha, style);
    }

    public static void CenterIcons()
    {
        IntPtr tray = FindWindow("Shell_TrayWnd", null);
        CenterOne(tray);
    }

    static void CenterOne(IntPtr taskbar)
    {
        if (taskbar == IntPtr.Zero) return;
        IntPtr list = FindChild(taskbar, "MSTaskListWClass");
        if (list == IntPtr.Zero) return;
        IntPtr parent = GetParent(list);
        if (parent == IntPtr.Zero) parent = taskbar;
        RECT br, lr, pr;
        if (!GetWindowRect(taskbar, out br)) return;
        if (!GetWindowRect(list, out lr)) return;
        if (!GetWindowRect(parent, out pr)) return;
        int listW = lr.W, barW = br.W;
        if (listW <= 0 || barW <= 0 || listW >= barW - 40) return;
        int newX = (br.Left + (barW - listW) / 2) - pr.Left;
        int curX = lr.Left - pr.Left;
        int curY = lr.Top - pr.Top;
        if (Math.Abs(curX - newX) < 3) return;
        SetWindowPos(list, IntPtr.Zero, newX, curY, 0, 0, 0x0001 | 0x0004 | 0x0010 | 0x4000);
    }

    public static void Restore()
    {
        try
        {
            Registry.SetValue(
                @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced",
                "TaskbarAcrylicOpacity", 255, RegistryValueKind.DWord);
        }
        catch { }
        ApplyAccent(FindWindow("Shell_TrayWnd", null), AccentState.DISABLED, 255, 0);
        IntPtr result;
        SendMessageTimeout((IntPtr)HWND_BROADCAST, (uint)WM_SETTINGCHANGE, IntPtr.Zero,
            "ImmersiveColorSet", SMTO_ABORTIFHUNG, 2000, out result);
    }

    public static void RefreshExplorerTaskbar()
    {
        // soft refresh without killing explorer: hide/show tray
        IntPtr tray = FindWindow("Shell_TrayWnd", null);
        if (tray == IntPtr.Zero) return;
        ShowWindow(tray, 0); // SW_HIDE
        ShowWindow(tray, 5); // SW_SHOW
    }

    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@

try { Add-Type -TypeDefinition $cs -Language CSharp } catch {
  if ($_.Exception.Message -notmatch 'already exists') { throw }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'TaskbarStyleTool'
$form.Size = New-Object System.Drawing.Size(460, 310)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.TopMost = $true

$lbl = New-Object System.Windows.Forms.Label
$lbl.AutoSize = $false
$lbl.Size = New-Object System.Drawing.Size(420, 45)
$lbl.Location = New-Object System.Drawing.Point(16, 12)
$lbl.Text = [TB]::Diagnose()

$lbl2 = New-Object System.Windows.Forms.Label
$lbl2.Text = 'Alpha default 0 = fully transparent (registry TaskbarAcrylicOpacity)'
$lbl2.Location = New-Object System.Drawing.Point(16, 65)
$lbl2.AutoSize = $true

$track = New-Object System.Windows.Forms.TrackBar
$track.Minimum = 0
$track.Maximum = 255
$track.Value = 0
$track.TickFrequency = 15
$track.Width = 400
$track.Location = New-Object System.Drawing.Point(16, 90)

$valLbl = New-Object System.Windows.Forms.Label
$valLbl.Text = 'Alpha = 0'
$valLbl.Location = New-Object System.Drawing.Point(16, 135)
$valLbl.AutoSize = $true
$track.Add_ValueChanged({ $valLbl.Text = ('Alpha = ' + $track.Value) })

$cmb = New-Object System.Windows.Forms.ComboBox
$cmb.DropDownStyle = 'DropDownList'
$cmb.Items.AddRange(@('Transparent', 'Blur', 'Acrylic'))
$cmb.SelectedIndex = 0
$cmb.Width = 180
$cmb.Location = New-Object System.Drawing.Point(16, 160)

$chk = New-Object System.Windows.Forms.CheckBox
$chk.Text = 'Center icons'
$chk.Checked = $false
$chk.Location = New-Object System.Drawing.Point(220, 162)
$chk.AutoSize = $true

$status = New-Object System.Windows.Forms.Label
$status.Text = 'Status: ready'
$status.Location = New-Object System.Drawing.Point(16, 195)
$status.AutoSize = $true

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = 'Apply'
$btnApply.Location = New-Object System.Drawing.Point(16, 225)
$btnApply.Width = 100

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = 'Restore'
$btnRestore.Location = New-Object System.Drawing.Point(130, 225)
$btnRestore.Width = 100

$keepTimer = New-Object System.Windows.Forms.Timer
$keepTimer.Interval = 3000
$script:keepAlive = $false
$script:lastAlpha = 0
$script:lastStyle = 0

$doApply = {
  $alpha = [byte]$track.Value
  $style = $cmb.SelectedIndex
  $script:lastAlpha = $alpha
  $script:lastStyle = $style
  [TB]::Apply($alpha, $style)
  [TB]::RefreshExplorerTaskbar()
  Start-Sleep -Milliseconds 200
  [TB]::ApplyComposition($alpha, $style)
  if ($chk.Checked) { [TB]::CenterIcons() }
  $script:keepAlive = $true
  $keepTimer.Start()
  $status.Text = ('Status: Applied alpha=' + $alpha + ' (reg+composition)')
  $lbl.Text = [TB]::Diagnose()
}

$btnApply.Add_Click({ & $doApply })

$btnRestore.Add_Click({
  $script:keepAlive = $false
  $keepTimer.Stop()
  [TB]::Restore()
  [TB]::RefreshExplorerTaskbar()
  $status.Text = 'Status: Restored'
  $lbl.Text = [TB]::Diagnose()
})

# soft keep-alive: only re-apply composition every 3s (avoids deep flicker)
$keepTimer.Add_Tick({
  if (-not $script:keepAlive) { return }
  [TB]::ApplyComposition([byte]$script:lastAlpha, [int]$script:lastStyle)
  if ($chk.Checked) { [TB]::CenterIcons() }
})

$form.Add_FormClosing({
  $keepTimer.Stop()
})

$form.Controls.AddRange(@($lbl, $lbl2, $track, $valLbl, $cmb, $chk, $status, $btnApply, $btnRestore))

$form.Add_Shown({
  & $doApply
})

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
