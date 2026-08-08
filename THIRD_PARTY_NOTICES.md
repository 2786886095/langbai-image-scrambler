# Third-party notices

## 小番茄图片混淆兼容算法

`cherry_tomato_gilbert` 的兼容行为依据以下 MIT 项目实现并通过独立映射夹具验证：

- [ok8634673/Cherry-tomato-image-obfuscation](https://github.com/ok8634673/Cherry-tomato-image-obfuscation)
- [jakubcerveny/gilbert](https://github.com/jakubcerveny/gilbert)

该算法使用 Gilbert 广义 Hilbert 空间填充曲线，并按
`round((sqrt(5) - 1) / 2 * width * height)` 执行黄金比例循环偏移。

## Noto Sans CJK

应用内置 Noto Sans CJK SC/TC Regular，来源为
[notofonts/noto-cjk](https://github.com/notofonts/noto-cjk)，采用 SIL Open Font License 1.1。
许可证原文位于 `assets/fonts/OFL-1.1.txt`。

## 压缩、解压与安全存储

- Dart `archive` 4.0.9（MIT）：生成 ZIP，并提供 WinZip AES-256 加密。
- Zip4j 2.11.6（Apache-2.0）：Android ZIP 解压与 AES 密码处理。
- Apache Commons Compress 1.28.0（Apache-2.0）与 XZ for Java 1.10（Public Domain）：Android 7Z 读写。
- Junrar 8.0.0（Apache-2.0）：Android RAR/RAR5 解压。
- `flutter_secure_storage` 10.3.1 / Windows 4.1.0（BSD-3-Clause）：通过 Android 系统密钥与 Windows Credential Manager 保护密码库。仓库内的 Windows 构建副本只把 ATL 字符串宏替换为等价 Win32 UTF‑8/UTF‑16 转换，以移除构建机 ATL 依赖；原许可证保存在 `third_party/flutter_secure_storage_windows/LICENSE`。
- Windows 发布包内置官方 `7zr.exe` 26.02，用于 7Z 创建。该精简命令行程序声明为 Public Domain；来源为 [7-zip.org](https://www.7-zip.org/)，本仓库文件 SHA-256 为 `56b8cc9f4971cef253644fafe54063ed7fdca551d4dee0f8c6baa81b855acd72`。
- Windows 发布包同时内置官方 7-Zip 26.02 的 `7z.exe` 与 `7z.dll`，用于 ZIP、7Z、RAR 导入和旧式 GBK ZIP 文件名兼容。7-Zip 主体采用 GNU LGPL，部分代码采用 BSD 3-Clause，并包含 unRAR 解压限制；许可证原文位于 `assets/bin/windows/7z-license.txt`。`7z.exe` SHA-256 为 `83967f1b02b43c4efeda302795722c809e0e81b8307de73558d10484d5676a7d`，`7z.dll` SHA-256 为 `69fd4df057985c40e510e2fac182881c7f85e90aa13ec703f763a8fdb2ce61f8`。

RAR 仅用于导入和解压；应用不生成 RAR。

其余 Flutter/Dart 依赖的许可证可通过对应包仓库或发布包中的许可证清单查看。
