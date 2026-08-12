# 签名与发布

## Android 更新连续性

Android 将“包名 + 签名证书”视为应用身份。后续版本必须保持：

- `applicationId = com.langbai.imagescrambler`
- 同一 `langbai-image-scrambler-release.jks`
- 同一 alias 与密码
- 递增的 `versionCode`

密钥遗失后，已安装用户无法直接覆盖升级。密钥、密码和 SHA-256 指纹应至少保留两份离线备份，不应提交到公开 Git 仓库。

## Windows

当前 Windows 安装器未使用商业代码签名证书，因此 Windows SmartScreen 可能在首次下载时显示来源提醒。正式获得 Authenticode 证书后，可在上传 Release 前对安装器签名，应用内 GitHub Releases 检查不需要更改。

Setup 必须保持 `DisableDirPage=no`，使用户每次手动安装时都能确认或更改安装路径。软件内更新使用随程序安装的 `langbai_update_helper.exe`，等待旧进程退出后以静默参数覆盖当前路径并重启。更新助手与 Inno Setup 日志位于 `%LocalAppData%\LangbaiImageScrambler\logs`。

`v1.2.4` 及更早版本使用旧的 PowerShell 交接逻辑，无法通过发布新版文件反向获得原生助手。因此升级到首个修复版 `v1.2.5` 时需要手动运行一次 Setup；此后的软件内更新才由原生助手接管。

## GitHub Release 资产命名

- `Langbai-Image-Scrambler-Setup-vX.Y.Z.exe`
- `Langbai-Image-Scrambler-vX.Y.Z-android.apk`
- 可选：`Langbai-Image-Scrambler-vX.Y.Z-windows-portable.zip`

应用会从 `2786886095/langbai-image-scrambler` 的最新 Release 中选择当前平台对应的 `.exe` 或 `.apk` 资产。
