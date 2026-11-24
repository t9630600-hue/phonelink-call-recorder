# Adds PhoneLink Call Recorder to Windows startup (current user, no admin rights) and starts it now.
$vbs = Join-Path $PSScriptRoot 'Start-CallRecorder.vbs'
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'CallRecorder' -Value "wscript.exe `"$vbs`""
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -like '*CallRecorder.ps1*' |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Process wscript.exe "`"$vbs`""
Write-Host 'Installed: starts with Windows. Running now. Log: CallRecorder.log'
