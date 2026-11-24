# PhoneLink Call Recorder

Automatic call recording for **Microsoft Phone Link** («Связь с телефоном») on Windows 10/11.
Phone Link can make and receive phone calls over Bluetooth, but it has no way to record them. This tool fills the gap.

| | |
|---|---|
| 🇬🇧 English | Automatically records Phone Link calls on Windows: both voices in one MP3, no ringing, file named after the contact. |
| 🇷🇺 Русский | Автоматически записывает звонки «Связи с телефоном» в Windows: оба голоса в одном MP3, без гудков, файл назван по имени контакта. |
| 🇺🇿 O‘zbekcha | Windows’dagi «Telefon bilan bog‘lanish» (Phone Link) qo‘ng‘iroqlarini avtomatik yozib oladi: ikkala ovoz bitta MP3’da, gudoksiz, fayl kontakt nomi bilan. |
| 🇹🇷 Türkçe | Windows’ta Phone Link aramalarını otomatik kaydeder: iki ses tek MP3’te, çalma sesi yok, dosya adı kişinin adı. |
| 🇪🇸 Español | Graba automáticamente las llamadas de Phone Link en Windows: ambas voces en un MP3, sin tonos de llamada, archivo con el nombre del contacto. |
| 🇩🇪 Deutsch | Nimmt Phone-Link-Anrufe unter Windows automatisch auf: beide Stimmen in einer MP3, ohne Freizeichen, Datei nach dem Kontakt benannt. |
| 🇧🇷 Português | Grava automaticamente as chamadas do Phone Link no Windows: as duas vozes em um MP3, sem toque de chamada, arquivo com o nome do contato. |
| 🇨🇳 中文 | 自动录制 Windows「手机连接」(Phone Link) 的通话：双方声音合成一个 MP3，去掉等待铃声，文件以联系人命名。 |

[Русская версия ниже ↓](#по-русски)

## What it does

- Detects a Phone Link call automatically (no buttons to press).
- Records **both sides** into one stereo MP3: the other person on the **left** channel, you on the **right**. Volume is normalized.
- **Cuts off the ringing**: the recording starts the moment the call is answered (read from the call timer in the Phone Link call window).
- **Names files by contact**: `Mom 2026-11-24 10-24-43.mp3` (or the phone number if the contact is unknown).
- Runs hidden in the background and starts with Windows. No admin rights, no drivers, nothing installed except ffmpeg.

## How it works

| Piece | How |
|---|---|
| Call detection | During a Bluetooth HFP call a Windows service (`svchost`) bridges the phone audio to your headphones. Its audio session carries the GUID of the phone's Hands-Free endpoint — that's the signal. |
| Other person's voice | WASAPI **loopback** of the output device the call is playing on. (The Hands-Free endpoint itself can't be opened by other apps.) |
| Your voice | WASAPI capture of the microphone the call service is using. |
| Answer moment & contact name | UI Automation reads the Phone Link call window: the title shows the call timer (`06:31 - …`) and the window holds the contact name. |
| MP3 | ffmpeg: resample, normalize (`dynaudnorm`), merge to stereo, `libmp3lame` 96 kbps. |

All in PowerShell 5.1 + inline C# (`WasapiRec.cs`), nothing to compile.

## Install

1. Download [ffmpeg](https://github.com/BtbN/FFmpeg-Builds/releases) (`ffmpeg-master-latest-win64-gpl.zip`) and put `ffmpeg.exe` next to `CallRecorder.ps1` (or in `PATH`).
2. Optional: copy `config.example.json` to `config.json` and edit it:
   - `OutDir` — where recordings go (default: `Music\Call Recordings`)
   - `Ffmpeg` — path to ffmpeg.exe
   - `MicMatch` — part of your microphone's name (default: the mic the call uses)
   - `CallWord` — file name when the contact is unknown
3. Run `Install.ps1` (right click → *Run with PowerShell*). Done.

Check the state at any time: `powershell -ExecutionPolicy Bypass -File CallRecorder.ps1 -Once`.
Log: `CallRecorder.log`. Remove: `Uninstall.ps1`.

## Limitations

- Everything that plays in your headphones during the call ends up in the recording (e.g. notification sounds).
- The contact name and answer time depend on Phone Link's window layout; if Microsoft changes it, the file falls back to the date name and the full recording.
- Tested with Russian-language Windows 11, Galaxy Note9, HyperX Cloud III Wireless, TP-Link UB500.

## Legal

Recording laws differ between countries. In many places you must tell the other party that the call is being recorded. You are responsible for using this lawfully.

---

## По-русски

Автоматическая запись звонков приложения **«Связь с телефоном»** (Phone Link) в Windows 10/11.

- Сам замечает звонок и пишет **обе стороны** в один MP3: собеседник — левый канал, вы — правый.
- **Обрезает гудки**: запись начинается с момента, когда сняли трубку.
- **Называет файл именем контакта**: `Мама 2026-11-24 10-24-43.mp3`.
- Работает скрыто и запускается вместе с Windows. Права администратора не нужны.

**Установка:** положите `ffmpeg.exe` рядом со скриптом. При желании скопируйте `config.example.json` в `config.json` и поменяйте папку записей. Затем запустите `Install.ps1`.

**Удаление:** `Uninstall.ps1`. Сами записи при этом не удаляются.

**Ограничения:** в запись попадает всё, что звучит в наушниках во время звонка. Имя контакта берётся из окна звонка «Связи с телефоном»: если Microsoft его переделает, файл будет назван по дате.

**Закон:** во многих странах собеседника нужно предупреждать о записи разговора.

## License

MIT
