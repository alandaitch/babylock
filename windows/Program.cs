using System.ComponentModel;
using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace BabyLock;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (!Options.TryParse(args, out Options? options, out string? error))
        {
            MessageBox.Show(error, "BabyLock", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new LockForm(options!));
    }
}

internal sealed record Options(TimeSpan? Duration, bool KeyboardOnly)
{
    internal static bool TryParse(string[] args, out Options? options, out string? error)
    {
        options = null;
        error = null;
        bool keyboardOnly = false;
        TimeSpan? duration = null;

        for (int index = 0; index < args.Length; index++)
        {
            switch (args[index])
            {
                case "--solo-teclado":
                    keyboardOnly = true;
                    break;
                case "--minutos" when index + 1 < args.Length:
                    if (!double.TryParse(args[++index], System.Globalization.NumberStyles.Float,
                            System.Globalization.CultureInfo.InvariantCulture, out double minutes)
                        || !double.IsFinite(minutes) || minutes <= 0 || minutes > 1440)
                    {
                        error = "--minutos requiere un número entre 0 y 1440.";
                        return false;
                    }
                    duration = TimeSpan.FromMinutes(minutes);
                    break;
                default:
                    error = "Uso: BabyLock.exe [--minutos N] [--solo-teclado]";
                    return false;
            }
        }

        options = new Options(duration, keyboardOnly);
        return true;
    }
}

internal sealed class LockForm : Form
{
    private readonly Options options;
    private readonly HashSet<Keys> pressedKeys = [];
    private readonly Native.HookProc keyboardProc;
    private readonly Native.HookProc mouseProc;
    private readonly System.Windows.Forms.Timer? unlockTimer;
    private IntPtr keyboardHook;
    private IntPtr mouseHook;

    internal LockForm(Options options)
    {
        this.options = options;
        keyboardProc = KeyboardCallback;
        mouseProc = MouseCallback;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        Size = new Size(224, 56);
        BackColor = Color.FromArgb(31, 41, 55);
        DoubleBuffered = true;

        var screen = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1280, 720);
        Location = new Point(screen.Right - Width - 20, screen.Top + 20);
        Region = new Region(RoundedRectangle(ClientRectangle, 28));
        DoubleClick += (_, _) => Close();

        if (options.Duration is TimeSpan duration)
        {
            unlockTimer = new System.Windows.Forms.Timer
            {
                Interval = (int)Math.Min(duration.TotalMilliseconds, int.MaxValue)
            };
            unlockTimer.Tick += (_, _) => Close();
        }
    }

    protected override void OnShown(EventArgs eventArgs)
    {
        base.OnShown(eventArgs);

        try
        {
            IntPtr module = Native.GetModuleHandle(Process.GetCurrentProcess().MainModule?.ModuleName);
            keyboardHook = Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, keyboardProc, module, 0);
            if (keyboardHook == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "No se pudo bloquear el teclado.");

            if (!options.KeyboardOnly)
            {
                mouseHook = Native.SetWindowsHookEx(Native.WH_MOUSE_LL, mouseProc, module, 0);
                if (mouseHook == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "No se pudo bloquear el mouse.");
            }

            unlockTimer?.Start();
        }
        catch (Win32Exception error)
        {
            MessageBox.Show(error.Message, "BabyLock", MessageBoxButtons.OK, MessageBoxIcon.Error);
            Close();
        }
    }

    protected override void OnPaint(PaintEventArgs eventArgs)
    {
        base.OnPaint(eventArgs);
        eventArgs.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        TextRenderer.DrawText(eventArgs.Graphics, "🔒 BabyLock", Font, new Rectangle(10, 5, Width - 20, 23),
            Color.White, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        TextRenderer.DrawText(eventArgs.Graphics, "Doble clic para desbloquear", Font,
            new Rectangle(10, 28, Width - 20, 22), Color.FromArgb(209, 213, 219),
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
    }

    private IntPtr KeyboardCallback(int code, IntPtr message, IntPtr data)
    {
        if (code < 0)
            return Native.CallNextHookEx(keyboardHook, code, message, data);

        int eventType = message.ToInt32();
        if (eventType is Native.WM_KEYDOWN or Native.WM_SYSKEYDOWN
            or Native.WM_KEYUP or Native.WM_SYSKEYUP)
        {
            var key = (Keys)Marshal.ReadInt32(data);
            if (eventType is Native.WM_KEYDOWN or Native.WM_SYSKEYDOWN)
                pressedKeys.Add(key);
            else
                pressedKeys.Remove(key);

            if (key == Keys.B && pressedKeys.Contains(Keys.B)
                && (pressedKeys.Contains(Keys.LControlKey) || pressedKeys.Contains(Keys.RControlKey))
                && (pressedKeys.Contains(Keys.LMenu) || pressedKeys.Contains(Keys.RMenu))
                && (pressedKeys.Contains(Keys.LShiftKey) || pressedKeys.Contains(Keys.RShiftKey)))
            {
                BeginInvoke((Action)Close);
            }

            return (IntPtr)1;
        }

        return Native.CallNextHookEx(keyboardHook, code, message, data);
    }

    private IntPtr MouseCallback(int code, IntPtr message, IntPtr data)
    {
        if (code < 0)
            return Native.CallNextHookEx(mouseHook, code, message, data);

        if (message.ToInt32() == Native.WM_MOUSEMOVE)
            return Native.CallNextHookEx(mouseHook, code, message, data);

        var hookData = Marshal.PtrToStructure<Native.MouseHookData>(data);
        if (Bounds.Contains(hookData.Point.X, hookData.Point.Y)
            && message.ToInt32() is Native.WM_LBUTTONDOWN or Native.WM_LBUTTONUP
                or Native.WM_LBUTTONDBLCLK)
        {
            return Native.CallNextHookEx(mouseHook, code, message, data);
        }

        return (IntPtr)1;
    }

    protected override void OnFormClosed(FormClosedEventArgs eventArgs)
    {
        unlockTimer?.Stop();
        unlockTimer?.Dispose();
        if (mouseHook != IntPtr.Zero)
            Native.UnhookWindowsHookEx(mouseHook);
        if (keyboardHook != IntPtr.Zero)
            Native.UnhookWindowsHookEx(keyboardHook);
        base.OnFormClosed(eventArgs);
    }

    private static GraphicsPath RoundedRectangle(Rectangle rectangle, int radius)
    {
        var path = new GraphicsPath();
        int diameter = radius * 2;
        path.AddArc(rectangle.Left, rectangle.Top, diameter, diameter, 180, 90);
        path.AddArc(rectangle.Right - diameter, rectangle.Top, diameter, diameter, 270, 90);
        path.AddArc(rectangle.Right - diameter, rectangle.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(rectangle.Left, rectangle.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }
}

internal static class Native
{
    internal const int WH_KEYBOARD_LL = 13;
    internal const int WH_MOUSE_LL = 14;
    internal const int WM_KEYDOWN = 0x100;
    internal const int WM_KEYUP = 0x101;
    internal const int WM_SYSKEYDOWN = 0x104;
    internal const int WM_SYSKEYUP = 0x105;
    internal const int WM_MOUSEMOVE = 0x200;
    internal const int WM_LBUTTONDOWN = 0x201;
    internal const int WM_LBUTTONUP = 0x202;
    internal const int WM_LBUTTONDBLCLK = 0x203;

    internal delegate IntPtr HookProc(int code, IntPtr message, IntPtr data);

    [StructLayout(LayoutKind.Sequential)]
    internal struct PointData
    {
        internal int X;
        internal int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct MouseHookData
    {
        internal PointData Point;
        internal uint MouseData;
        internal uint Flags;
        internal uint Time;
        internal IntPtr ExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern IntPtr SetWindowsHookEx(int hookType, HookProc callback, IntPtr module, uint threadId);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    internal static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    internal static extern IntPtr GetModuleHandle(string? moduleName);
}
