Option Explicit

Dim files, shell, root, python, app, command
Set files = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

root = files.GetParentFolderName(files.GetParentFolderName(WScript.ScriptFullName))
python = root & "\.windows\runtime\Scripts\python.exe"
app = root & "\windows\app.py"
command = Chr(34) & python & Chr(34) & " " & Chr(34) & app & Chr(34)

shell.CurrentDirectory = root
shell.Run command, 0, False
