; Inno Setup script for Broken IPTV (Windows)
; Compile with: ISCC.exe installer\broken_iptv.iss
; No admin rights required; single interactive page; dark theme.

#define MyAppName "Broken IPTV"
#define MyAppVersion "1.3.1"
#define MyAppPublisher "Broken IPTV"
#define MyAppExeName "broken_iptv.exe"
#define MyBuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{3ED13CFC-1BC0-4683-B6DC-0208EE87CA87}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
; Per-user install: never requires administrator rights. Avoiding the words
; "setup"/"install" in the filename also prevents Windows' installer-detection
; heuristic from forcing a UAC prompt.
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
DisableWelcomePage=yes
DisableReadyPage=yes
DisableDirPage=yes
DisableFinishedPage=yes
OutputDir=output
OutputBaseFilename=BrokenIPTV
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=no
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\windows\runner\resources\app_icon.ico
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"

[Tasks]
Name: "desktopicon"; Description: "Crea un'icona sul desktop"; GroupDescription: "Collegamenti:"
Name: "startmenuicon"; Description: "Aggiungi al menu Start"; GroupDescription: "Collegamenti:"

[Files]
Source: "{#MyBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Place the Start-menu shortcut directly in the user's Programs folder so it
; shows up in Start search immediately (no subfolder).
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startmenuicon
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Avvia {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
const
  clDarkBg = $000000;
  clDarkPanel = $1C1C1C;
  clWhiteTxt = $F5F5F5;

procedure InitializeWizard;
begin
  // Dark theme, matching the app.
  WizardForm.Color := clDarkBg;
  WizardForm.MainPanel.Color := clDarkBg;
  WizardForm.InnerPage.Color := clDarkBg;
  WizardForm.Bevel.Visible := False;
  WizardForm.Bevel1.Visible := False;

  WizardForm.PageNameLabel.Font.Color := clWhiteTxt;
  WizardForm.PageDescriptionLabel.Font.Color := clWhiteTxt;
  WizardForm.SelectTasksLabel.Font.Color := clWhiteTxt;
  WizardForm.FinishedLabel.Font.Color := clWhiteTxt;
  WizardForm.FinishedHeadingLabel.Font.Color := clWhiteTxt;

  WizardForm.TasksList.Color := clDarkPanel;
  WizardForm.TasksList.Font.Color := clWhiteTxt;
  WizardForm.RunList.Color := clDarkPanel;
  WizardForm.RunList.Font.Color := clWhiteTxt;
end;
