#ifndef MyAppName
  #define MyAppName "Langbai 图片混淆"
#endif
#ifndef MyAppVersion
  #define MyAppVersion "1.2.6"
#endif
#ifndef MyAppPublisher
  #define MyAppPublisher "Langbai"
#endif
#ifndef MyAppExeName
  #define MyAppExeName "langbai_image_scrambler.exe"
#endif
#ifndef MyAppId
  #define MyAppId "{{9C0211F3-BD6A-4B64-8FE6-A5884B485CAE}"
#endif
#ifndef MyDefaultDirName
  #define MyDefaultDirName "Langbai Image Scrambler"
#endif
#ifndef MyOutputBaseFilename
  #define MyOutputBaseFilename "Langbai-Image-Scrambler-Setup-v" + MyAppVersion
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\{#MyDefaultDirName}
DisableDirPage=no
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\release
OutputBaseFilename={#MyOutputBaseFilename}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=..\LICENSE
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Windows 安装程序
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "chinesesimp"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: checkedonce

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
