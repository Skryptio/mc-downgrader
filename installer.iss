[Setup]
AppName=Chunker Downgrader
AppVersion=1.0
DefaultDirName={pf}\ChunkerDowngrader
DefaultGroupName=ChunkerDowngrader
UninstallDisplayIcon={app}\ChunkerDowngrader.exe
Compression=lzma2
SolidCompression=yes
OutputDir=D:\Output
OutputBaseFilename=ChunkerDowngrader_Installer
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons"; Flags: unchecked
Name: "startmenuicon"; Description: "Create a Start Menu shortcut"; GroupDescription: "Additional icons"; Flags: unchecked

[Icons]
Name: "{commondesktop}\Chunker Downgrader"; Filename: "{app}\ChunkerDowngrader.exe"; IconFilename: "{app}\icon.ico"; Tasks: desktopicon
Name: "{group}\Chunker Downgrader"; Filename: "{app}\ChunkerDowngrader.exe"; IconFilename: "{app}\icon.ico"; Tasks: startmenuicon
Name: "{group}\Uninstall Chunker Downgrader"; Filename: "{uninstallexe}"

[Registry]
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\ChunkerDowngrader"; ValueType: string; ValueName: "DisplayName"; ValueData: "Chunker Downgrader"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\ChunkerDowngrader"; ValueType: string; ValueName: "DisplayIcon"; ValueData: "{app}\icon.ico"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\ChunkerDowngrader.exe"; ValueType: string; ValueName: ""; ValueData: "{app}\ChunkerDowngrader.exe"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\ChunkerDowngrader.exe"; ValueType: string; ValueName: "Path"; ValueData: "{app}"; Flags: uninsdeletekey

[Code]
procedure RunCommand(Command: string);
var
  ResultCode: Integer;
begin
  if not Exec(ExpandConstant('{cmd}'), '/C ' + Command, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    RaiseException('Command failed: ' + Command);
end;

function GetLatestJarName(): String;
var
  JsonFile, OutputFile, JarFile, Command: String;
  FileHandle: TStringList;
begin
  JsonFile := ExpandConstant('{tmp}\latest_release.json');
  OutputFile := ExpandConstant('{tmp}\latest_jar.txt');
  JarFile := '';

  // Fetch the latest release metadata from GitHub
  RunCommand('curl -s -L "https://api.github.com/repos/HiveGamesOSS/Chunker/releases/latest" -o "' + JsonFile + '"');

  // Extract the filename dynamically from the JSON using PowerShell
  Command := 'powershell -ExecutionPolicy Bypass -Command "$json = Get-Content ''' + JsonFile + ''' | ConvertFrom-Json; ';
  Command := Command + '$json.assets | Where-Object { $_.name -match ''chunker-cli.*\.jar'' } | ';
  Command := Command + 'Select-Object -ExpandProperty name | Out-File -Encoding utf8 ''' + OutputFile + '''"';
  
  RunCommand(Command);

  // Read the extracted filename
  if FileExists(OutputFile) then
  begin
    FileHandle := TStringList.Create;
    try
      FileHandle.LoadFromFile(OutputFile);
      if FileHandle.Count > 0 then
        JarFile := Trim(FileHandle[0]);
    finally
      FileHandle.Free;
    end;
  end;

  if JarFile = '' then
    RaiseException('Failed to retrieve JAR name from GitHub');

  Result := JarFile;
end;

procedure InstallGit();
begin
  RunCommand('winget install --silent --accept-source-agreements --accept-package-agreements Git.Git');
end;

procedure InstallNodeJS();
begin
  RunCommand('winget install --silent --accept-source-agreements --accept-package-agreements OpenJS.NodeJS');
end;

procedure EnsureGradlewIsExecutable(GradlewPath: string);
begin
  RunCommand('icacls "' + GradlewPath + '" /grant Everyone:F');
end;

procedure WaitForFile(FilePath: string; Timeout: Integer);
var
  i: Integer;
begin
  for i := 0 to Timeout do
  begin
    if FileExists(FilePath) then
      Exit;
    Sleep(1000); // Wait 1 second
  end;
  RaiseException('File not found after waiting: ' + FilePath);
end;

procedure BuildChunker(InstallPath: string);
var
  ChunkerPath, GradleLogPath, GradlewPath, JarName, JarPath: string;
begin
  ChunkerPath := InstallPath + '\Chunker';
  GradleLogPath := InstallPath + '\gradle_build.log';
  GradlewPath := ChunkerPath + '\gradlew.bat';

  // Clone Chunker repository
  RunCommand('git clone https://github.com/HiveGamesOSS/Chunker "' + ChunkerPath + '"');

  // Ensure Node.js is installed before running npm commands
  InstallNodeJS();

  // Ensure gradlew.bat is executable
  if not FileExists(GradlewPath) then
  begin
    MsgBox('gradlew.bat not found in ' + ChunkerPath, mbError, MB_OK);
    RaiseException('Gradlew missing: ' + GradlewPath);
  end;

  EnsureGradlewIsExecutable(GradlewPath);

  // Run npm install in non-interactive mode
  RunCommand('cd "' + ChunkerPath + '\app" && npm install --no-progress --quiet');

  // Run CLI build separately
  RunCommand('cd "' + ChunkerPath + '" && "' + GradlewPath + '" :cli:shadowJar --stacktrace > "' + GradleLogPath + '" 2>&1');

  // Get the correct JAR filename dynamically
  JarName := GetLatestJarName();
  JarPath := ChunkerPath + '\cli\build\libs\' + JarName;

  // Wait for the .jar file to appear (up to 20 seconds)
  WaitForFile(JarPath, 20);

  // Verify the build output
  if not FileExists(JarPath) then
  begin
    MsgBox('Chunker build failed! Check logs: ' + GradleLogPath, mbError, MB_OK);
    RaiseException('Chunker build failed. See log: ' + GradleLogPath);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  InstallPath, ChunkerExe, ChunkerJar, IconFile, ConfigFile, JarName: String;
  Config: TStrings;
begin
  if CurStep = ssInstall then
  begin
    InstallPath := ExpandConstant('{app}');
    ChunkerExe := InstallPath + '\ChunkerDowngrader.exe';
    IconFile := InstallPath + '\icon.ico';
    ConfigFile := InstallPath + '\install_config.ini';

    if not DirExists(InstallPath) then
      CreateDir(InstallPath);

    InstallGit();
    BuildChunker(InstallPath);

    // Retrieve correct JAR name dynamically
    JarName := GetLatestJarName();
    ChunkerJar := InstallPath + '\Chunker\cli\build\libs\' + JarName;

    RunCommand('curl -L -o "' + ChunkerExe + '" "https://github.com/Skryptio/mc-downgrader/releases/latest/download/ChunkerDowngrader.exe"');
    RunCommand('curl -L -o "' + IconFile + '" "https://github.com/Skryptio/mc-downgrader/releases/latest/download/icon.ico"');

    Config := TStringList.Create;
    Config.Add('[Installation]');
    Config.Add('Path=' + InstallPath);
    Config.Add('Jar=' + ChunkerJar);
    Config.SaveToFile(ConfigFile);
    Config.Free;
  end;
end;

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Run]
Filename: "{app}\ChunkerDowngrader.exe"; Description: "Launch Chunker Downgrader"; Flags: nowait postinstall skipifsilent
