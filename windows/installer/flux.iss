; Inno Setup script for NN4K — installer that updates in place instead of
; the current portable Release-folder build (see ROADMAP.md, трек 13).
;
; Build with: iscc windows\installer\flux.iss
; scripts\build_installer.ps1 builds the app, installer, ZIP and checksums.
;
; #AppVersion is passed in from the build script via /DAppVersion=... so the
; installer version always matches pubspec.yaml without editing this file by
; hand on every release.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Fixed GUID — this is what makes a later run of the installer recognize an
; existing install as "the same app" and update it in place instead of
; creating a second, parallel installation. Never regenerate this once a
; version has shipped.
AppId={{8EF5C60B-CBFC-4B32-9EF3-267C79268C4E}
AppName=NN4K
AppVersion={#AppVersion}
AppPublisher=NN4K
DefaultDirName={localappdata}\NN4K
; Per-user install, no admin prompt for the installer itself — TUN mode
; already asks for elevation separately at runtime when needed (see
; lib/engines/xray/windows_elevation.dart), the installer doesn't need it.
PrivilegesRequired=lowest
; The packaged Wintun driver is amd64: do not offer this build on 32-bit
; Windows or ARM64 systems that can emulate an x64 application but not its driver.
ArchitecturesAllowed=x64os
DisableProgramGroupPage=yes
OutputBaseFilename=NN4KSetup-{#AppVersion}
OutputDir=..\..\build\installer
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Overwriting nn4k.exe/DLLs while the app is running would otherwise fail —
; Inno's Restart Manager integration detects processes holding a lock on
; files being replaced (no named mutex needed) and asks to close them.
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\nn4k.exe

[Files]
; Whole Release output — xray-core/sing-box (assets/xray, assets/sing-box)
; are already copied in here by windows/CMakeLists.txt's install() rules, so
; this one line bundles everything the portable build has today.
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\NN4K"; Filename: "{app}\nn4k.exe"
Name: "{autodesktop}\NN4K"; Filename: "{app}\nn4k.exe"; Tasks: desktopicon

[Tasks]
Name: desktopicon; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительные значки:"

[Run]
Filename: "{app}\nn4k.exe"; Description: "Запустить NN4K"; Flags: nowait postinstall skipifsilent; Check: not IsUpdateInstall
Filename: "{app}\nn4k.exe"; Flags: nowait; Check: IsUpdateInstall

[Code]
function OpenProcess(Access: LongWord; Inherit: Boolean; ProcessId: LongWord): THandle;
  external 'OpenProcess@kernel32.dll stdcall';
function WaitForSingleObject(Handle: THandle; Milliseconds: LongWord): LongWord;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function CloseHandle(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';
function GetLastError: LongWord;
  external 'GetLastError@kernel32.dll stdcall';

function IsUpdateInstall: Boolean;
begin
  Result := ExpandConstant('{param:NN4KUPDATE|0}') = '1';
end;

function InitializeSetup: Boolean;
var
  ProcessId: Integer;
  ProcessHandle: THandle;
begin
  Result := True;
  if not IsUpdateInstall then Exit;
  ProcessId := StrToIntDef(ExpandConstant('{param:WAITPID|0}'), 0);
  if ProcessId <= 0 then
  begin
    Result := False;
    Exit;
  end;
  { Do not forcibly kill the VPN process. Dart stops its engines, restores the
    proxy and exits; only then may Setup replace the EXE/DLLs. }
  ProcessHandle := OpenProcess($00100000, False, ProcessId); { SYNCHRONIZE }
  if ProcessHandle <> 0 then
  begin
    Result := WaitForSingleObject(ProcessHandle, 120000) = 0;
    CloseHandle(ProcessHandle);
  end
  else
    { ERROR_INVALID_PARAMETER means the caller PID has already exited. Other
      failures, especially ACCESS_DENIED, must not bypass the wait. }
    Result := GetLastError = 87;
end;

{ Deliberately NOT removing %AppData%\flux (settings, profile.json,
  ping_cache.json) on uninstall: that is user data, not installation files.
  See ROADMAP.md, track 13. }
