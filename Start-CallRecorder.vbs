' Hidden launcher for CallRecorder.ps1 (no console window). Uses the folder this file is in.
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\CallRecorder.ps1""", 0, False