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

其余 Flutter/Dart 依赖的许可证可通过对应包仓库或发布包中的许可证清单查看。
