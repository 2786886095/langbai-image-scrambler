param(
    [string]$ReleaseNotesFile,
    [switch]$SkipBuild,
    [switch]$SkipGitHub,
    [switch]$SkipCloud
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$flutter = 'F:\flutter-3.44\bin\flutter.bat'
$env:PATH = (Join-Path $root 'tooling\nuget') + ';' + $env:PATH
$env:PUB_CACHE = 'F:\AI\agent\codex\.pub-cache-ascii'
$versionLine = Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$'
if (-not $versionLine) { throw 'pubspec.yaml 中的版本格式不正确' }
$version = $versionLine.Matches[0].Groups[1].Value
$tag = "v$version"
$setup = Join-Path $root "release\Langbai-Image-Scrambler-Setup-v$version.exe"
$apk = Join-Path $root "release\Langbai-Image-Scrambler-v$version-android.apk"
$checksums = Join-Path $root "release\SHA256SUMS-v$version.txt"

if (-not $SkipBuild) {
    & $flutter analyze
    if ($LASTEXITCODE) { throw 'flutter analyze 失败' }
    & $flutter test --exclude-tags=golden
    if ($LASTEXITCODE) { throw 'flutter test 失败' }
    & $flutter test test/ui_golden_test.dart '--dart-define=RUN_GOLDENS=true'
    if ($LASTEXITCODE) { throw 'UI 截图回归失败' }
    & $flutter build windows --release
    if ($LASTEXITCODE) { throw 'Windows 构建失败' }
    & $flutter build apk --release
    if ($LASTEXITCODE) { throw 'Android 构建失败' }
    Copy-Item 'build\app\outputs\flutter-apk\app-release.apk' $apk -Force
    & 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' "/DMyAppVersion=$version" 'installer\langbai-image-scrambler.iss'
    if ($LASTEXITCODE) { throw 'Setup 构建失败' }
    $hashLines = @($setup, $apk) | ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $(Split-Path -Leaf $_)"
    }
    [IO.File]::WriteAllLines($checksums, $hashLines, [Text.UTF8Encoding]::new($false))
}

foreach ($file in @($setup, $apk, $checksums)) {
    if (-not (Test-Path -LiteralPath $file) -or (Get-Item -LiteralPath $file).Length -eq 0) {
        throw "发布文件缺失：$file"
    }
}

if (-not $SkipGitHub) {
    if (-not $ReleaseNotesFile) { $ReleaseNotesFile = "release\release-notes-v$version.md" }
    if (-not (Test-Path -LiteralPath $ReleaseNotesFile)) { throw "发布说明缺失：$ReleaseNotesFile" }
    $pending = git status --porcelain
    if ($pending) { throw 'Git 工作区需先提交，避免发布未提交代码' }
    git push
    if ($LASTEXITCODE) { throw 'Git 推送失败' }
    gh release view $tag --repo 2786886095/langbai-image-scrambler --json url | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "GitHub Release 已存在，继续执行网盘同步：$tag"
    } else {
        gh release create $tag --repo 2786886095/langbai-image-scrambler --title "小番茄图片混淆 $tag" --notes-file $ReleaseNotesFile $setup $apk $checksums
        if ($LASTEXITCODE) { throw 'GitHub Release 发布失败' }
    }
}

if (-not $SkipCloud) {
    node tooling\publish-cloud-release.mjs --setup $setup --apk $apk
    if ($LASTEXITCODE) { throw '三网盘发布失败' }
}

Write-Host "发布完成：$tag"
