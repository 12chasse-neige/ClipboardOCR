#ifndef StageDir
  #error StageDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef AppVersion
  #define AppVersion "0.3.1"
#endif

[Setup]
AppId={{8CA1D626-F6A6-4B7B-81F7-17886B7C43D1}
AppName=Clipboard OCR
AppVersion={#AppVersion}
AppPublisher=Clipboard OCR contributors
AppPublisherURL=https://github.com/12chasse-neige/ClipboardOCR
DefaultDirName={localappdata}\Programs\ClipboardOCR
DefaultGroupName=Clipboard OCR
DisableDirPage=no
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#StageDir}\assets\AppIcon.ico
UninstallDisplayIcon={app}\assets\AppIcon.ico
OutputDir={#OutputDir}
OutputBaseFilename=ClipboardOCR-{#AppVersion}-windows-x64-setup
VersionInfoVersion={#AppVersion}.0
AppMutex=Local\ClipboardOCR.Windows
CloseApplications=yes
RestartApplications=no

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Complete Clipboard OCR Setup"; Filename: "{app}\windows\setup.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\assets\AppIcon.ico"
Name: "{group}\Uninstall Clipboard OCR"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\windows\setup.cmd"; WorkingDir: "{app}"; Description: "Download and verify the GPU runtime and models now (required before first use)"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\.windows"
Type: files; Name: "{userdesktop}\Clipboard OCR.lnk"
Type: filesandordirs; Name: "{app}\backend\__pycache__"
Type: filesandordirs; Name: "{app}\windows\__pycache__"
; {app}\data is deliberately not removed: it holds the Python runtime, setup
; cache and model files. This preserves data during upgrades and allows a user
; to inspect/remove it explicitly after uninstall. Setup logs remain under
; %LOCALAPPDATA%\ClipboardOCR\logs.
