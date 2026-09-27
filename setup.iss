; ==================================================
; Defaults only: the release workflow passes the real
; values from pubspec.yaml as /DAppVersion and /DBuildNumber.
#define AppVersion "1.0.0"
#define BuildNumber "1"
; ==================================================

#define FullVersion AppVersion + "." + BuildNumber

[Setup]
AppName=SolWatt
AppVersion={#AppVersion}
AppPublisher=dev.solsynth
AppPublisherURL=https://solsynth.dev
AppUpdatesURL=https://github.com/Solsynth/SolWatt/releases
AppCopyright=Copyright © 2026 dev.solsynth
VersionInfoVersion={#FullVersion}
UninstallDisplayName=SolWatt
UninstallDisplayIcon={app}\solwatt.exe

DefaultDirName={commonpf}\SolWatt
UsePreviousAppDir=no

OutputDir=.\Installer
OutputBaseFilename=windows-x86_64-setup
SetupIconFile=.\assets\icons\icon.ico

Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=4

ArchitecturesAllowed=x64compatible
PrivilegesRequired=admin

[Files]
Source: ".\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\SolWatt"; Filename: "{app}\solwatt.exe"; IconFilename: "{app}\solwatt.exe"
Name: "{group}\{cm:UninstallProgram,SolWatt}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\SolWatt"; Filename: "{app}\solwatt.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Run]
Filename: "{app}\solwatt.exe"; Description: "Launch SolWatt"; Flags: nowait postinstall skipifsilent

; Stop the app before removing files locked by Flutter/WebView2.
[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /T /IM solwatt.exe"; Flags: runhidden waituntilterminated skipifdoesntexist

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\dev.solsynth\solwatt"
Type: files; Name: "{group}\SolWatt.lnk"
Type: files; Name: "{autodesktop}\SolWatt.lnk"
