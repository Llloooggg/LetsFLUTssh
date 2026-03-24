; LetsFLUTssh — Inno Setup installer script
; Build: iscc setup.iss

#define MyAppName "LetsFLUTssh"
#define MyAppVersion GetEnv('APP_VERSION')
#if MyAppVersion == ""
  #define MyAppVersion "0.9.1"
#endif
#define MyAppPublisher "LetsFLUTssh"
#define MyAppURL "https://github.com/Llloooggg/LetsFLUTssh"
#define MyAppExeName "letsflutssh.exe"
#define BuildDir GetEnv('BUILD_DIR')
#if BuildDir == ""
  #define BuildDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{7A2E3B4C-1D5F-4E6A-8B9C-0D1E2F3A4B5C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputBaseFilename=letsflutssh-{#MyAppVersion}-windows-x64-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKCU; Subkey: "Software\Classes\letsflutssh"; ValueType: string; ValueName: ""; ValueData: "URL:LetsFLUTssh Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\letsflutssh"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\letsflutssh\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""
