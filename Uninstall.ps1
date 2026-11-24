# Removes PhoneLink Call Recorder from startup and stops it. Recordings are kept.
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'CallRecorder' -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -like '*CallRecorder.ps1*' |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Write-Host 'Uninstalled. Recordings were not touched.'
