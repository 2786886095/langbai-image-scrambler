# Archive test fixtures

- `encrypted-mixed.7z`：本项目生成的最小加密 7Z，密码 `langbai-test`，包含中文目录、图片、TXT 与应跳过文件。
- `rar5-password-junrar.rar`：来自 Junrar 8.0.0 测试资源的最小 RAR5 密码夹具，密码 `junrar`；上游采用 Apache-2.0。

这些文件只用于 JVM 单元测试，不会打入 APK 或 Windows 发布包。
