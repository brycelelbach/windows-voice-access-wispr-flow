using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

internal sealed class VoiceModeMemory : NativeWindow, IDisposable
{
    // Voice Access shows a mode name immediately before its Settings and Help buttons.
    // A positive default reading requires both an empty label and visible toolbar controls.
    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out Rect bounds);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out int pid);
    [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr window, uint flag);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll", SetLastError=true)] private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr window, int id);

    private static readonly string Folder = AppDomain.CurrentDomain.BaseDirectory;
    private static readonly string Marker = Path.Combine(Folder, "Return to default.lnk");
    private static readonly string Template = Path.Combine(Folder, "Default action.lnk");
    private readonly bool trace;
    private readonly System.Windows.Forms.Timer expiry = new System.Windows.Forms.Timer();
    private IntPtr savedWindow;
    private int savedPid;

    private VoiceModeMemory(bool testing)
    {
        trace = testing;
        CreateHandle(new CreateParams { Caption = "Wispr Voice Access mode memory", Parent = new IntPtr(-3) });
        // Register only these two chords. Windows forwards their messages to this window.
        const uint modifiers = 1 | 2 | 4 | 0x4000; // Alt, Ctrl, Shift, no key repeat
        if (!RegisterHotKey(Handle, 1, modifiers, (uint)Keys.F9) ||
            !RegisterHotKey(Handle, 2, modifiers, (uint)Keys.F10))
        {
            var error = new Win32Exception(Marshal.GetLastWin32Error());
            Dispose();
            throw error;
        }
        File.Delete(Marker);
        expiry.Interval = 5000;
        expiry.Tick += delegate { expiry.Stop(); File.Delete(Marker); };
        Note("ready");
    }

    private void Note(string message)
    {
        if (trace) File.AppendAllText(Path.Combine(Folder, "test-results.txt"),
            DateTime.Now.ToString("O") + " " + message + Environment.NewLine);
    }

    private static bool HasInk(Bitmap area, int left, int right)
    {
        int step = Math.Max(1, area.Height / 24);
        int count = 0;
        for (int y=area.Height/4; y<area.Height*3/4; y+=2)
        {
            for (int x=left+step; x<right; x+=2)
            {
                Color a=area.GetPixel(x,y), b=area.GetPixel(x-step,y);
                if (Math.Max(Math.Abs(a.R-b.R), Math.Max(Math.Abs(a.G-b.G), Math.Abs(a.B-b.B))) > 32 && ++count >= 5)
                    return true;
            }
        }
        return false;
    }

    private static IntPtr Toolbar(out int pid)
    {
        pid=0;
        IntPtr window=FindWindow("Voice access","Voice access");
        if (window==IntPtr.Zero || !IsWindowVisible(window) || GetWindowThreadProcessId(window,out pid)==0)
            return IntPtr.Zero;
        using (var process = Process.GetProcessById(pid))
            return process.ProcessName.Equals("VoiceAccess",StringComparison.OrdinalIgnoreCase) ? window : IntPtr.Zero;
    }

    private static string ReadMode(IntPtr window)
    {
        Rect r;
        if (window==IntPtr.Zero || !GetWindowRect(window,out r)) return "unavailable";
        int h=r.Bottom-r.Top;
        if (h<20 || h>180 || r.Right-r.Left<h*15) return "unavailable";
        // Only inspect the end of the mode name and the adjacent control icons.
        int left=r.Right-4*h;
        for(int x=left+h/4;x<r.Right;x+=h/2)
            if(GetAncestor(WindowFromPoint(new Point(x,r.Top+h/2)),2)!=window) return "covered";
        using(var strip=new Bitmap(4*h,h,PixelFormat.Format32bppArgb))
        {
            using(var graphics=Graphics.FromImage(strip))
                graphics.CopyFromScreen(left,r.Top,0,0,strip.Size);
            if (!HasInk(strip,2*h,4*h)) return "unavailable";
            return HasInk(strip,0,2*h) ? "named mode" : "default";
        }
    }

    private void HandleSignal(int id)
    {
        int pid;
        IntPtr window=Toolbar(out pid);
        expiry.Stop();
        File.Delete(Marker);
        if (id==1)
        {
            savedWindow=IntPtr.Zero;
            string reading=ReadMode(window);
            if (reading=="default") { savedWindow=window; savedPid=pid; }
            Note("begin " + reading);
            return;
        }
        bool restore=window!=IntPtr.Zero && savedWindow==window && savedPid==pid;
        savedWindow=IntPtr.Zero;
        if (restore)
        {
            File.Copy(Template,Marker);
            expiry.Start();
        }
        Note(restore ? "end default" : "end command");
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg==0x0312)
        {
            try { HandleSignal(message.WParam.ToInt32()); }
            catch (Exception ex) { savedWindow=IntPtr.Zero; Note("signal failure " + ex.GetType().Name); }
            return;
        }
        base.WndProc(ref message);
    }

    public void Dispose()
    {
        expiry.Dispose();
        UnregisterHotKey(Handle,1);
        UnregisterHotKey(Handle,2);
        DestroyHandle();
    }

    [STAThread]
    private static int Main(string[] args)
    {
        SetProcessDpiAwarenessContext(new IntPtr(-4));
        if (args.Length==1 && args[0]=="action") return 0;
        if (args.Length==1 && args[0]=="test-action")
        {
            File.AppendAllText(Path.Combine(Folder,"test-results.txt"),DateTime.Now.ToString("O")+" native default action opened"+Environment.NewLine);
            return 0;
        }
        bool owner;
        using (var mutex = new Mutex(true,@"Local\WisprFlowVoiceAccessModeMemory",out owner))
        {
            if (!owner) return 0;
            try
            {
                using(var listener=new VoiceModeMemory(args.Length==1 && args[0]=="test"))
                    Application.Run();
            }
            catch (Exception) { return 1; }
            finally { mutex.ReleaseMutex(); }
        }
        return 0;
    }
}
