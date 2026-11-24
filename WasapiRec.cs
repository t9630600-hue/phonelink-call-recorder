// Запись звука через WASAPI: микрофон или "то, что звучит" в устройстве вывода (loopback) в WAV.
using System;
using System.IO;
using System.Threading;
using System.Runtime.InteropServices;

namespace CRW {
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int EnumAudioEndpoints(int f, int m, out IntPtr c); int GetDefaultAudioEndpoint(int f, int r, out IMMDevice d); int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice d); }
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
[Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioClient {
  int Initialize(int share, int flags, long dur, long per, IntPtr fmt, IntPtr guid);
  int GetBufferSize(out uint n); int GetStreamLatency(out long l); int GetCurrentPadding(out uint p);
  int IsFormatSupported(int s, IntPtr f, out IntPtr c); int GetMixFormat(out IntPtr f); int GetDevicePeriod(out long a, out long b);
  int Start(); int Stop(); int Reset(); int SetEventHandle(IntPtr h); int GetService(ref Guid g, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
[Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioCaptureClient { int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong devPos, out ulong qpc); int ReleaseBuffer(uint frames); int GetNextPacketSize(out uint frames); }

public class Recorder {
  string devId, path; bool loopback; Thread th; volatile bool stop; public string Error;
  public Recorder(string deviceId, bool isLoopback, string wavPath) { devId = deviceId; loopback = isLoopback; path = wavPath; }
  public void Start() { th = new Thread(Run); th.IsBackground = true; th.SetApartmentState(ApartmentState.MTA); th.Start(); }
  public void Stop() { stop = true; if (th != null) th.Join(5000); }

  void Run() {
    FileStream fs = null; BinaryWriter w = null; long dataBytes = 0; int hdrLen = 0;
    try {
      // Не через "new MMDeviceEnumerator()": в этом процессе уже есть такой же COM-класс из CallRecorder.ps1 -> ошибка приведения
      var en = (IMMDeviceEnumerator)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")));
      IMMDevice d; int hg = en.GetDevice(devId, out d);
      if (hg != 0 || d == null) { Error = "GetDevice 0x" + hg.ToString("X8"); return; }
      Guid ga = typeof(IAudioClient).GUID; object o; d.Activate(ref ga, 23, IntPtr.Zero, out o); var ac = (IAudioClient)o;
      IntPtr fmt; ac.GetMixFormat(out fmt);
      int cbSize = Marshal.ReadInt16(fmt, 16); int fmtLen = 18 + cbSize;
      int channels = Marshal.ReadInt16(fmt, 2); int rate = Marshal.ReadInt32(fmt, 4); int blockAlign = Marshal.ReadInt16(fmt, 12);
      int hr = ac.Initialize(0, loopback ? 0x00020000 : 0, 2000000, 0, fmt, IntPtr.Zero);
      if (hr != 0) { Error = "Initialize 0x" + hr.ToString("X8"); return; }
      Guid gc = typeof(IAudioCaptureClient).GUID; object oc; ac.GetService(ref gc, out oc); var cc = (IAudioCaptureClient)oc;

      fs = new FileStream(path, FileMode.Create, FileAccess.Write); w = new BinaryWriter(fs);
      byte[] fmtBytes = new byte[fmtLen]; Marshal.Copy(fmt, fmtBytes, 0, fmtLen);
      w.Write(new char[] { 'R','I','F','F' }); w.Write(0); w.Write(new char[] { 'W','A','V','E' });
      w.Write(new char[] { 'f','m','t',' ' }); w.Write(fmtLen); w.Write(fmtBytes);
      w.Write(new char[] { 'd','a','t','a' }); w.Write(0); hdrLen = (int)fs.Position;

      var sw = System.Diagnostics.Stopwatch.StartNew(); long framesWritten = 0;
      ac.Start();
      while (!stop) {
        Thread.Sleep(10);
        uint pkt; cc.GetNextPacketSize(out pkt);
        while (pkt > 0) {
          IntPtr data; uint frames, flags; ulong dp, qpc; cc.GetBuffer(out data, out frames, out flags, out dp, out qpc);
          int bytes = (int)frames * blockAlign; byte[] buf = new byte[bytes];
          if ((flags & 2) == 0) Marshal.Copy(data, buf, 0, bytes);   // 2 = SILENT -> нули
          w.Write(buf); dataBytes += bytes; framesWritten += frames;
          cc.ReleaseBuffer(frames); cc.GetNextPacketSize(out pkt);
        }
        // loopback не присылает данных, когда ничего не играет — дописываем тишину, чтобы не было рассинхрона
        if (loopback) {
          long expected = (long)(sw.Elapsed.TotalSeconds * rate) - rate / 10;
          if (expected > framesWritten) { int miss = (int)(expected - framesWritten); byte[] z = new byte[miss * blockAlign]; w.Write(z); dataBytes += z.Length; framesWritten += miss; }
        }
      }
      ac.Stop();
      Marshal.FreeCoTaskMem(fmt);
    } catch (Exception ex) { Error = ex.Message; }
    finally {
      if (w != null) {
        try { w.Flush(); fs.Seek(4, SeekOrigin.Begin); w.Write((int)(hdrLen - 8 + dataBytes)); fs.Seek(hdrLen - 4, SeekOrigin.Begin); w.Write((int)dataBytes); w.Close(); } catch {}
      }
    }
  }
}
}
