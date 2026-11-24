# Диагностика: все аудиоустройства и их сеансы (кто открывал)
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace DG {
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int EnumAudioEndpoints(int flow, int mask, out IMMDeviceCollection c); }
[Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceCollection { int GetCount(out int n); int Item(int i, out IMMDevice d); }
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); int OpenPropertyStore(int access, out IPropertyStore ps); int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id); int GetState(out int s); }
[Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPropertyStore { int GetCount(out int c); int GetAt(int i, out PKEY k); int GetValue(ref PKEY k, out PROPVARIANT v); }
[StructLayout(LayoutKind.Sequential)] struct PKEY { public Guid fmtid; public int pid; }
[StructLayout(LayoutKind.Explicit, Size = 24)] struct PROPVARIANT { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; }
[Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionManager2 { int GetAudioSessionControl(IntPtr g, int f, out IntPtr c); int GetSimpleAudioVolume(IntPtr g, int f, out IntPtr v); int GetSessionEnumerator(out IAudioSessionEnumerator e); }
[Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionEnumerator { int GetCount(out int n); int GetSession(int i, out IAudioSessionControl2 s); }
[Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionControl2 {
  int GetState(out int s); int GetDisplayName(out IntPtr n); int SetDisplayName(string n, ref Guid g); int GetIconPath(out IntPtr p); int SetIconPath(string p, ref Guid g);
  int GetGroupingParam(out Guid g); int SetGroupingParam(ref Guid g, ref Guid c); int RegisterAudioSessionNotification(IntPtr n); int UnregisterAudioSessionNotification(IntPtr n);
  int GetSessionIdentifier(out IntPtr s); int GetSessionInstanceIdentifier(out IntPtr s); int GetProcessId(out uint pid); int IsSystemSoundsSession(); int SetDuckingPreference(bool b); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator {}
public static class D {
  public static List<string> Dump(){
    var r = new List<string>();
    for (int flow = 0; flow < 2; flow++) {
      IMMDeviceCollection c; ((IMMDeviceEnumerator)new MMDeviceEnumerator()).EnumAudioEndpoints(flow, 15, out c); int n; c.GetCount(out n);
      for (int i = 0; i < n; i++) {
        IMMDevice d; c.Item(i, out d); string id; d.GetId(out id); int st; d.GetState(out st);
        IPropertyStore ps; d.OpenPropertyStore(0, out ps);
        var k = new PKEY { fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid = 14 }; PROPVARIANT v; ps.GetValue(ref k, out v);
        string name = v.vt == 31 ? Marshal.PtrToStringUni(v.p) : "?";
        if (st != 1 && !name.Contains("Hands-Free")) continue;
        r.Add((flow == 0 ? "OUT " : "IN  ") + "state=" + st + " " + name + " " + id);
        if (st != 1) continue;
        try {
          Guid g = typeof(IAudioSessionManager2).GUID; object o; d.Activate(ref g, 23, IntPtr.Zero, out o);
          IAudioSessionEnumerator e; ((IAudioSessionManager2)o).GetSessionEnumerator(out e); int m; e.GetCount(out m);
          for (int j = 0; j < m; j++) { IAudioSessionControl2 s; e.GetSession(j, out s); int ss; s.GetState(out ss); uint pid; s.GetProcessId(out pid); IntPtr sid; s.GetSessionIdentifier(out sid);
            string pn = ""; try { pn = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch {}
            r.Add("      session state=" + ss + " pid=" + pid + " " + pn + " " + Marshal.PtrToStringUni(sid)); }
        } catch (Exception ex) { r.Add("      err " + ex.Message); }
      }
    }
    return r;
  }
}
}
'@
[DG.D]::Dump()
