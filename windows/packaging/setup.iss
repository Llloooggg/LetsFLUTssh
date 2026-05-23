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
; Output arch slug that lands in the installer filename and the
; ArchitecturesAllowed gate. CI release matrix passes `x64` for the
; AMD64 build and `arm64` for the windows-11-arm runner; local
; `iscc setup.iss` invocations without the env var fall back to x64
; so contributor builds keep working.
#define OutputArch GetEnv('OUTPUT_ARCH')
#if OutputArch == ""
  #define OutputArch "x64"
#endif

[Setup]
AppId={{7A2E3B4C-1D5F-4E6A-8B9C-0D1E2F3A4B5C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputBaseFilename=letsflutssh-{#MyAppVersion}-windows-{#OutputArch}-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
; `x64compatible` matches both AMD64 and ARM64 hosts in Inno Setup
; 6.3+. The CI release matrix ships choco's latest Inno Setup (>6.4
; at time of writing), so a single arch directive covers both
; runner shapes — no per-arch `#if` required.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

; Uninstall-time tasks (shown in the uninstaller wizard)
[UninstallDelete]
; Inno removes only the files it installed, so anything the running
; app or a plugin drops into the install tree (Flutter engine
; sidecars, crash dumps, a locked DLL re-created on next launch)
; leaves the directory behind — the user sees an empty
; `…\Programs\LetsFLUTssh` folder after uninstall. Force-remove the
; whole tree so nothing lingers. User data lives in `{userappdata}`
; and is untouched here (handled opt-in by the Code section below).
Type: filesandordirs; Name: "{app}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Registry]
; URL scheme letsflutssh:// — opens deep links from browser/Mail/etc.
Root: HKCU; Subkey: "Software\Classes\letsflutssh"; ValueType: string; ValueName: ""; ValueData: "URL:LetsFLUTssh Protocol"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\letsflutssh"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\letsflutssh\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

; No file-extension associations. The app does not claim .lfs / .pem /
; .key / .pub — generic SSH formats belong to the user's editor, and
; .lfs archives import via drag-drop or the in-app picker, not an OS
; double-click hand-off. Only the letsflutssh:// URL scheme above is
; registered.

; ─────────────────────────────────────────────────────────────────
; Uninstaller: optional removal of user data
; (sessions DB, master password salt/verifier, logs, etc. in %APPDATA%\letsflutssh)
; ─────────────────────────────────────────────────────────────────
[Code]
var
  RemoveDataCheckBox: TNewCheckBox;

procedure InitializeUninstallProgressForm();
var
  Page: TNewNotebookPage;
  DataPath: string;
begin
  DataPath := ExpandConstant('{userappdata}\letsflutssh');
  if not DirExists(DataPath) then exit;

  Page := UninstallProgressForm.InnerNotebook.Pages[0];

  RemoveDataCheckBox := TNewCheckBox.Create(UninstallProgressForm);
  RemoveDataCheckBox.Parent := Page;
  RemoveDataCheckBox.Top := Page.Height - ScaleY(28);
  RemoveDataCheckBox.Left := 0;
  RemoveDataCheckBox.Width := Page.Width;
  RemoveDataCheckBox.Height := ScaleY(20);
  RemoveDataCheckBox.Caption := 'Also delete user data (sessions, keys, logs)';
  RemoveDataCheckBox.Checked := False;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataPath: string;
begin
  if (CurUninstallStep = usPostUninstall) and Assigned(RemoveDataCheckBox)
     and RemoveDataCheckBox.Checked then begin
    DataPath := ExpandConstant('{userappdata}\letsflutssh');
    if DirExists(DataPath) then
      DelTree(DataPath, True, True, True);
  end;
end;
