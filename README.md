# Langbai 图片混淆

Windows 与 Android 双端离线批量图片混淆/还原工具。生成结果仍是可正常打开的 PNG，但画面被可逆地打乱；未经压缩、缩放或重新编码时，可逐像素精确还原。

![Windows 工作台](docs/screenshots/home-desktop.png)

<p align="center">
  <img src="docs/screenshots/home-android.png" width="360" alt="Android 工作台">
</p>

## 功能

- **7 种可逆算法**：网格块打乱、行循环位移、列循环位移、像素级伪随机置换、RGB 通道扰动、复合混淆、小番茄图片混淆。
- **自动识别还原**：本软件生成的 PNG 内含私有算法标识、随机种子、版本和原像素 SHA-256；还原后自动校验。
- **可选密码保护**：使用 PBKDF2-HMAC-SHA256（210,000 次）派生密钥，以 AES-256-GCM 加密算法参数。密码不会写入文件。
- **批量与目录处理**：支持图片多选、文件夹递归导入、保留全部子目录结构。
- **符合导出规则**：单图导出一个 PNG；多图在所选位置建立批次文件夹；文件夹导入时输出根文件夹名称保持不变。
- **两种导出习惯**：每次询问路径，或保存固定导出文件夹。
- **Android 专项适配**：Android 8.0（API 26）起，使用系统 Storage Access Framework 取得持久目录权限，无需全盘存储权限。
- **简体/繁体中文**、深浅主题、键盘与触控响应式布局。
- **完全离线**：图片、密码和算法参数均在本机处理；仅“检查更新”会访问 GitHub Releases API。

## 无损边界

逐像素精确还原要求使用本软件输出的原始 PNG。微信、QQ、B站或其他平台若对图片执行 JPEG 压缩、缩放、裁剪或重新编码，原像素已经改变，校验会失败。

“小番茄图片混淆”与参考工具在 Gilbert 曲线像素映射上双向兼容。参考工具若输出 JPEG，其有损编码本身不满足逐像素无损；本软件自身的 PNG 往返保持精确。

## 使用

1. 选择“生成混淆图”或“自动还原”。
2. 选择图片、导入文件夹，或在 Windows 拖入文件/文件夹。
3. 生成时选择算法，可按需启用密码；还原时默认自动识别。
4. 点击主按钮并选择导出位置。
5. 识别不到外部小番茄图片时，手动选择“小番茄图片混淆”。其他无标识算法需要同时提供生成时的随机种子。

## 构建

项目使用 Flutter 3.44 / Dart 3.12。

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build windows --release
```

Android 最低版本为 API 26，固定 `applicationId`：`com.langbai.imagescrambler`。

## Android 签名与升级

正式更新必须永久复用同一个 keystore、alias 和 `applicationId`。`android/key.properties` 已加入 `.gitignore`，公开仓库不包含私钥。配置格式：

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=langbai-release
storeFile=C:/secure/location/langbai-image-scrambler-release.jks
```

当前正式发布密钥由项目所有者离线保管。详见 [发布说明](docs/SIGNING_AND_RELEASE.md)。

## 测试

- 七种算法对非方形 RGBA 图执行正向/逆向逐字节对比。
- 小番茄算法与参考 Python 实现的固定映射夹具对比。
- PNG 自动识别、AES-GCM 正确密码、错误密码、像素 SHA-256 校验。
- 1440×900 Windows 与 390×844 Android 黄金图布局检查。

## 许可证

项目采用 [MIT License](LICENSE)。小番茄兼容算法与字体来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
