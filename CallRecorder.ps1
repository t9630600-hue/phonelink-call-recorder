# PhoneLink Call Recorder — автозапись звонков приложения «Связь с телефоном» (Phone Link) в Windows.
# Когда идёт Bluetooth-звонок (HFP), пишет собеседника (то, что звучит в наушниках) и ваш микрофон
# в один стерео-MP3: собеседник слева, вы справа. Имя файла — имя контакта из окна звонка.
# Настройки — в config.json рядом со скриптом (см. config.example.json).
param(
  [string]$OutDir   = (Join-Path ([Environment]::GetFolderPath('MyMusic')) 'Call Recordings'),
  [string]$Ffmpeg   = '',                      # пусто: ffmpeg.exe рядом со скриптом или из PATH
  [string]$MicMatch = '',                      # часть имени микрофона; пусто: микрофон связи по умолчанию
  [string]$CallWord = 'Call',                  # имя файла, если контакт не определён
  [int]$PollMs = 700,
  [switch]$DebugLog,                           # подробный журнал аудиосеансов
  [switch]$Once                                # для проверки: показать состояние и выйти
)
$ErrorActionPreference = 'Stop'
# config.json переопределяет параметры по умолчанию (но не те, что заданы в командной строке)
$cfgFile = Join-Path $PSScriptRoot 'config.json'
if (Test-Path $cfgFile) {
  $cfg = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($p in $cfg.PSObject.Properties) {
    if (-not $PSBoundParameters.ContainsKey($p.Name)) { Set-Variable -Name $p.Name -Value $p.Value }
  }
}
if (-not $Ffmpeg) {
  $local = Join-Path $PSScriptRoot 'ffmpeg.exe'
  $Ffmpeg = if (Test-Path $local) { $local } else { (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue).Source }
}
$LogFile = Join-Path $PSScriptRoot 'CallRecorder.log'
function Write-Log($m) { $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m; Add-Content -Path $LogFile -Value $line -Encoding UTF8; Write-Host $line }

# Не запускать вторую копию
$mutex = New-Object System.Threading.Mutex($false, 'Global\CallRecorder_PhoneLink')
if (-not $Once -and -not $mutex.WaitOne(0)) { exit }

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace CR {
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int EnumAudioEndpoints(int flow, int mask, out IMMDeviceCollection c); int GetDefaultAudioEndpoint(int f, int r, out IMMDevice d); int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice d); }
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

public class Dev { public string Id; public string Name; public int Flow; public override string ToString(){ return Name + " [" + Id + "]"; } }

public static class Audio {
  static IMMDeviceEnumerator En(){ return (IMMDeviceEnumerator)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"))); }
  public static List<Dev> List(){
    var r = new List<Dev>();
    for (int flow = 0; flow < 2; flow++) {
      IMMDeviceCollection c; En().EnumAudioEndpoints(flow, 1, out c); int n; c.GetCount(out n);
      for (int i = 0; i < n; i++) {
        IMMDevice d; c.Item(i, out d); string id; d.GetId(out id);
        IPropertyStore ps; d.OpenPropertyStore(0, out ps);
        var k = new PKEY { fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid = 14 }; PROPVARIANT v; ps.GetValue(ref k, out v);
        r.Add(new Dev { Id = id, Name = v.vt == 31 ? Marshal.PtrToStringUni(v.p) : "?", Flow = flow });
      }
    }
    return r;
  }
  // Звонок: служба Windows (svchost) пересылает звук телефона в наушники. Её сеанс на устройстве
  // вывода активен, а в идентификаторе есть %b{GUID} — GUID Bluetooth-микрофона телефона.
  public static string CallSourceGuid(){
    try {
      IMMDeviceCollection c; En().EnumAudioEndpoints(0, 1, out c); int n; c.GetCount(out n);
      for (int i = 0; i < n; i++) {
        IMMDevice d; c.Item(i, out d);
        Guid g = typeof(IAudioSessionManager2).GUID; object o; d.Activate(ref g, 23, IntPtr.Zero, out o);
        IAudioSessionEnumerator e; ((IAudioSessionManager2)o).GetSessionEnumerator(out e); int m; e.GetCount(out m);
        for (int j = 0; j < m; j++) {
          IAudioSessionControl2 s; e.GetSession(j, out s); int st; s.GetState(out st); if (st != 1) continue;
          IntPtr sp; s.GetSessionIdentifier(out sp); string sid = Marshal.PtrToStringUni(sp) ?? "";
          if (sid.IndexOf("svchost.exe", StringComparison.OrdinalIgnoreCase) < 0) continue;
          int b = sid.LastIndexOf("%b{"); if (b < 0) continue;
          string guid = sid.Substring(b + 2).Trim();
          if (guid.StartsWith("{00000000-0000")) continue;
          string devId; d.GetId(out devId);
          return guid.ToUpper() + "|" + devId;   // источник | устройство, где звучит звонок
        }
      }
    } catch {}
    return null;
  }
  // Краткая сводка активных сеансов на всех устройствах (для журнала)
  public static string Summary(){
    var parts = new List<string>();
    try {
      for (int flow = 0; flow < 2; flow++) {
        IMMDeviceCollection c; En().EnumAudioEndpoints(flow, 1, out c); int n; c.GetCount(out n);
        for (int i = 0; i < n; i++) {
          IMMDevice d; c.Item(i, out d); string id; d.GetId(out id);
          Guid g = typeof(IAudioSessionManager2).GUID; object o; d.Activate(ref g, 23, IntPtr.Zero, out o);
          IAudioSessionEnumerator e; ((IAudioSessionManager2)o).GetSessionEnumerator(out e); int m; e.GetCount(out m);
          for (int j = 0; j < m; j++) {
            IAudioSessionControl2 s; e.GetSession(j, out s); int st; s.GetState(out st); if (st != 1) continue;
            uint pid; s.GetProcessId(out pid); IntPtr sp; s.GetSessionIdentifier(out sp); string sid = Marshal.PtrToStringUni(sp) ?? "";
            string pn = ""; try { pn = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch {}
            int b = sid.LastIndexOf("%b"); parts.Add((flow == 0 ? "OUT" : "IN") + ":" + id.Substring(id.Length - 9, 8) + ":" + pn + (b >= 0 ? sid.Substring(b) : ""));
          }
        }
      }
    } catch (Exception ex) { parts.Add("err:" + ex.Message); }
    parts.Sort(); return string.Join(" | ", parts);
  }
  // Микрофон, который служба звонка (svchost) сейчас слушает — это и есть ваш голос в звонке
  public static string CallMicId(string phoneGuid){
    try {
      IMMDeviceCollection c; En().EnumAudioEndpoints(1, 1, out c); int n; c.GetCount(out n);
      for (int i = 0; i < n; i++) {
        IMMDevice d; c.Item(i, out d); string id; d.GetId(out id);
        if (phoneGuid != null && id.ToUpper().Contains(phoneGuid.ToUpper())) continue;   // это сам телефон
        Guid g = typeof(IAudioSessionManager2).GUID; object o; d.Activate(ref g, 23, IntPtr.Zero, out o);
        IAudioSessionEnumerator e; ((IAudioSessionManager2)o).GetSessionEnumerator(out e); int m; e.GetCount(out m);
        for (int j = 0; j < m; j++) {
          IAudioSessionControl2 s; e.GetSession(j, out s); int st; s.GetState(out st); if (st != 1) continue;
          IntPtr sp; s.GetSessionIdentifier(out sp); string sid = Marshal.PtrToStringUni(sp) ?? "";
          if (sid.IndexOf("svchost.exe", StringComparison.OrdinalIgnoreCase) >= 0) return id;
        }
      }
    } catch {}
    return null;
  }
  // Микрофон связи по умолчанию (Параметры звука -> «Устройство связи по умолчанию»)
  public static string DefaultCommMicId(){
    try { IMMDevice d; if (En().GetDefaultAudioEndpoint(1, 2, out d) == 0 && d != null) { string id; d.GetId(out id); return id; } } catch {}
    return null;
  }
}
}
'@

# Какой микрофон писать: заданный в MicMatch, иначе тот, что слушает служба звонка, иначе микрофон связи по умолчанию
function Get-MicId($phoneGuid) {
  if ($MicMatch) {
    $m = [CR.Audio]::List() | Where-Object { $_.Flow -eq 1 -and $_.Name -like "*$MicMatch*" } | Select-Object -First 1
    if ($m) { return $m.Id }
  }
  $id = [CR.Audio]::CallMicId($phoneGuid); if ($id) { return $id }
  return [CR.Audio]::DefaultCommMicId()
}


Add-Type -Path (Join-Path $PSScriptRoot 'WasapiRec.cs')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

# Тексты из окон «Связь с телефоном» (имя контакта, таймер звонка) через UI Automation
$script:TextCond = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Text)
$script:EndBtnCond = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty, 'MiniEndButton')
# Окно звонка «Связи с телефоном» (то, где есть кнопка «Завершить»):
#   заголовок "06:31 - Звонок на компьютере" (таймер появляется, когда сняли трубку), рядом — имя контакта или номер
function Get-CallWindowInfo {
  try {
    $ids = @((Get-Process PhoneExperienceHost -ErrorAction SilentlyContinue).Id)
    if (-not $ids) { return $null }
    foreach ($w in [Windows.Automation.AutomationElement]::RootElement.FindAll('Children', [Windows.Automation.Condition]::TrueCondition)) {
      if ($ids -notcontains $w.Current.ProcessId) { continue }
      if (-not $w.FindFirst('Descendants', $script:EndBtnCond)) { continue }
      $info = [pscustomobject]@{ Name = $null; Timer = -1; Title = $null }; $base = $null
      foreach ($e in $w.FindAll('Descendants', $script:TextCond)) {
        $n = ($e.Current.Name -replace '[‎‏⁨⁩]', '').Trim(); if (-not $n) { continue }
        if ($e.Current.AutomationId -eq 'TitleTextBlock') {
          $info.Title = $n
          if ($n -match '^((?:\d{1,2}:)?\d{1,2}:\d{2})\s*-\s*(.*)$') { $info.Timer = Get-TimerSeconds $Matches[1]; $base = $Matches[2] } else { $base = $n }
          continue
        }
        # Первый текст без AutomationId, кроме подписи окна («Звонок на компьютере» — как в заголовке), — имя контакта/номер
        if (-not $info.Name -and -not $e.Current.AutomationId -and $n -ne $base -and $n -ne $info.Title) { $info.Name = $n }
      }
      return $info
    }
  } catch {}
  return $null
}
# Последняя запись журнала вызовов: имя/номер и время (виден, если открыта вкладка «Вызовы»)
function Get-LastCallLog {
  try {
    $ids = @((Get-Process PhoneExperienceHost -ErrorAction SilentlyContinue).Id)
    $c = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty, 'CallHistory')
    foreach ($w in [Windows.Automation.AutomationElement]::RootElement.FindAll('Children', [Windows.Automation.Condition]::TrueCondition)) {
      if ($ids -notcontains $w.Current.ProcessId) { continue }
      $list = $w.FindFirst('Descendants', $c); if (-not $list) { continue }
      $li = $list.FindFirst('Descendants', (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::ListItem)))
      if (-not $li) { continue }
      # "Имя, Исходящий, 24.11.2026 в 9:43"
      $n = $li.Current.Name -replace '[‎‏]', ''
      if ($n -match '^(.*), ([^,]+), (\d{1,2}\.\d{1,2}\.\d{4}) в (\d{1,2}:\d{2})$') {
        $t = [datetime]::ParseExact("$($Matches[3]) $($Matches[4])", 'd.M.yyyy H:mm', $null)
        return [pscustomobject]@{ Name = $Matches[1].Trim(); Kind = $Matches[2]; Time = $t }
      }
    }
  } catch {}
  return $null
}
# "0:05", "00:05", "1:02:03" -> секунды, иначе -1
function Get-TimerSeconds($t) {
  if ($t -match '^(?:(\d{1,2}):)?(\d{1,2}):(\d{2})$') { return [int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + [int]$Matches[3] }
  return -1
}
function Get-SafeName($s) {
  $s = ($s -replace '[\\/:*?"<>|\r\n\t]', ' ' -replace '\s+', ' ').Trim()
  if ($s.Length -gt 60) { $s = $s.Substring(0, 60).Trim() }
  return $s
}

function Start-Recording($st) {
  if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }
  $stamp = '{0:yyyy-MM-dd HH-mm-ss}' -f (Get-Date)
  $tmp = Join-Path $env:TEMP "callrec_$($stamp -replace ' ','_')"
  New-Item -ItemType Directory -Force $tmp | Out-Null
  $rec = [pscustomobject]@{
    Stamp  = $stamp
    File   = $null
    Connect = $null     # через сколько секунд от начала записи сняли трубку (по таймеру звонка)
    Name   = $null      # имя контакта (или номер) из окна звонка
    Tmp    = $tmp
    Caller = New-Object CRW.Recorder($st.OutDev, $true,  (Join-Path $tmp 'caller.wav'))   # то, что звучит в наушниках
    Me     = New-Object CRW.Recorder($st.MicId, $false, (Join-Path $tmp 'me.wav'))      # ваш микрофон
    Start  = Get-Date
  }
  $rec.Caller.Start(); $rec.Me.Start()
  Write-Log "Запись начата"
  return $rec
}

function Update-CallInfo($rec) {
  $el = ((Get-Date) - $rec.Start).TotalSeconds
  $i = Get-CallWindowInfo; if (-not $i) { return }
  if ($i.Name -and $i.Name -ne $rec.Name) { $rec.Name = $i.Name; Write-Log "Контакт в окне звонка: $($i.Name)" }
  if ($i.Timer -ge 0) {
    $c = [math]::Max(0, $el - $i.Timer - 1)   # таймер показывает целые секунды — берём с запасом
    if ($null -eq $rec.Connect) { Write-Log ('Трубку сняли: ~{0:N1} сек от начала записи (таймер {1})' -f $c, $i.Title) }
    if ($null -eq $rec.Connect -or $c -lt $rec.Connect) { $rec.Connect = $c }
  }
}

function Stop-Recording($rec) {
  $rec.Caller.Stop(); $rec.Me.Stop()
  foreach ($e in $rec.Caller.Error, $rec.Me.Error) { if ($e) { Write-Log "Ошибка записи: $e" } }
  $secs = ((Get-Date) - $rec.Start).TotalSeconds
  $cw = Join-Path $rec.Tmp 'caller.wav'; $mw = Join-Path $rec.Tmp 'me.wav'
  # Начало — с момента, когда сняли трубку (с запасом 0,5 сек)
  $ss = 0; if ($null -ne $rec.Connect) { $ss = [math]::Max(0, $rec.Connect - 0.3) } else { Write-Log 'Таймер звонка не найден — запись целиком' }
  $len = $secs - $ss
  # Имя файла: имя контакта/номер из окна звонка; если окна не было — из журнала вызовов (ждём до 6 сек)
  $who = $rec.Name
  if (-not $who) {
    for ($i = 0; $i -lt 6 -and -not $who; $i++) {
      $l = Get-LastCallLog
      if ($l -and [math]::Abs(($l.Time - $rec.Start).TotalMinutes) -le 2) { $who = $l.Name; Write-Log "Журнал вызовов: $($l.Name), $($l.Kind)" }
      else { Start-Sleep -Seconds 1 }
    }
  }
  $who = if ($who) { Get-SafeName $who } else { $null }; if (-not $who) { $who = $CallWord }
  $rec.File = Join-Path $OutDir "$who $($rec.Stamp).mp3"
  if ($len -lt 3 -or -not (Test-Path $cw) -or -not (Test-Path $mw)) { Write-Log 'Запись слишком короткая, удалена' }
  else {
    $secs = $len
    # Собеседник — левый канал, вы — правый; выравнивание громкости, MP3
    $fc = '[0:a]aresample=48000,pan=mono|c0=0.5*c0+0.5*c1,dynaudnorm=f=250:g=15[a];[1:a]aresample=48000,pan=mono|c0=c0,dynaudnorm=f=250:g=15[b];[a][b]amerge=inputs=2[out]'
    $sst = $ss.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
    $out = & $Ffmpeg -hide_banner -loglevel error -y -ss $sst -i $cw -ss $sst -i $mw -filter_complex $fc -map '[out]' -ac 2 -c:a libmp3lame -b:a 96k $rec.File 2>&1
    if ($out) { Write-Log "ffmpeg: $out" }
    if (Test-Path $rec.File) { Write-Log ('Запись сохранена: {0} ({1:N0} сек, {2:N0} КБ)' -f $rec.File, $secs, ((Get-Item $rec.File).Length/1KB)) }
  }
  Remove-Item $rec.Tmp -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
}

function Get-CallState {
  $src = [CR.Audio]::CallSourceGuid()   # "{GUID}|id устройства вывода" или $null
  $st = [pscustomobject]@{ OutDev = $null; MicId = $null }
  if ($src) { $p = $src.Split('|'); $st.OutDev = $p[1]; $st.MicId = Get-MicId $p[0] }
  return $st
}

if ($Once) {
  $d = Get-CallState
  "Папка записей: $OutDir"; "ffmpeg: $Ffmpeg"
  "Звонок идёт: " + [bool]$d.OutDev; if ($d.OutDev) { "Вывод: $($d.OutDev)"; "Микрофон: $($d.MicId)" }
  exit
}
if (-not $Ffmpeg -or -not (Test-Path $Ffmpeg)) { Write-Log 'Не найден ffmpeg.exe: положите его рядом со скриптом, добавьте в PATH или укажите Ffmpeg в config.json'; exit 1 }

Write-Log 'Автозапись звонков запущена'
$rec = $null; $idle = 0; $lastSum = ''
while ($true) {
  try {
    if ($DebugLog) { $sum = [CR.Audio]::Summary(); if ($sum -ne $lastSum) { Write-Log "Сеансы: $sum"; $lastSum = $sum } }
    $d = Get-CallState
    $active = [bool]$d.OutDev -and [bool]$d.MicId
    if ($active -and -not $rec) { Write-Log 'Звонок обнаружен'; $rec = Start-Recording $d; $idle = 0 }
    elseif ($rec) {
      if ($active) { Update-CallInfo $rec }
      if (-not $active) { $idle++; if ($idle -ge 3) { Stop-Recording $rec; $rec = $null; $idle = 0 } }
      else { $idle = 0 }
    }
  } catch { Write-Log "Ошибка: $($_.Exception.Message)" }
  Start-Sleep -Milliseconds $PollMs
}