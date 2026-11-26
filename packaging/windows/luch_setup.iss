#ifndef MyAppVersion
  #define MyAppVersion "0.0.2a"
#endif

[Setup]
AppId={{8D6B2A1E-5B44-4E2F-9F1A-3B9C102D5E01}
AppName=Луч (Luch)
AppVersion={#MyAppVersion}
AppPublisher=Luch
DefaultDirName={autopf}\Luch
DefaultGroupName=Луч
UninstallDisplayIcon={app}\luch.exe
OutputBaseFilename=Luch-Windows-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Луч"; Filename: "{app}\luch.exe"
Name: "{autodesktop}\Луч"; Filename: "{app}\luch.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\luch.exe"; Description: "{cm:LaunchProgram,Луч}"; Flags: nowait postinstall skipifsilent
