enum FunToolType { prism, cloak }

enum CloakVersion { v0, v1, v2, v3, v4, v5 }

extension CloakVersionX on CloakVersion {
  int get number => index;

  bool get carriesFile => number <= 3;

  bool get needsCover => number != 3;

  String get title => switch (this) {
    CloakVersion.v0 => 'v0 · 均衡隐藏',
    CloakVersion.v1 => 'v1 · 稳定隐藏',
    CloakVersion.v2 => 'v2 · 高容量隐藏',
    CloakVersion.v3 => 'v3 · 纯文件载体',
    CloakVersion.v4 => 'v4 · 经典灰度幻影',
    CloakVersion.v5 => 'v5 · 彩色幻影',
  };

  String get description => switch (this) {
    CloakVersion.v0 => '棋盘格里图与表图，同时按色差动态写入文件；容量与观感较均衡。',
    CloakVersion.v1 => '使用单比特与奇偶校验保存文件，容量较低，适合优先保证识别稳定性。',
    CloakVersion.v2 => '每通道保存两位数据，容量高于 v1，适合隐藏较大的文件。',
    CloakVersion.v3 => '不需要表图，生成接近白色的 PNG 文件载体，重点是保存与提取文件。',
    CloakVersion.v4 => '使用灰度与透明度混合两张图片；只生成视觉效果，不保存可提取的原文件。',
    CloakVersion.v5 => '使用彩色 RGBA 混合，保留更多颜色；只生成视觉效果，不保存可提取的原文件。',
  };

  String get notice => carriesFile
      ? '必须保留原始 PNG；压缩、缩放或重新编码可能破坏隐藏数据。'
      : '这是视觉合成模式，生成结果不包含两张来源图的无损副本。';

  String titleFor(bool traditional) => traditional
      ? switch (this) {
          CloakVersion.v0 => 'v0 · 均衡隱藏',
          CloakVersion.v1 => 'v1 · 穩定隱藏',
          CloakVersion.v2 => 'v2 · 高容量隱藏',
          CloakVersion.v3 => 'v3 · 純檔案載體',
          CloakVersion.v4 => 'v4 · 經典灰階幻影',
          CloakVersion.v5 => 'v5 · 彩色幻影',
        }
      : title;

  String descriptionFor(bool traditional) => traditional
      ? switch (this) {
          CloakVersion.v0 => '棋盤格裡圖與表圖，同時按色差動態寫入檔案；容量與觀感較均衡。',
          CloakVersion.v1 => '使用單位元與奇偶校驗儲存檔案，容量較低，適合優先保證識別穩定性。',
          CloakVersion.v2 => '每通道儲存兩位資料，容量高於 v1，適合隱藏較大的檔案。',
          CloakVersion.v3 => '不需要表圖，生成接近白色的 PNG 檔案載體，重點是儲存與提取檔案。',
          CloakVersion.v4 => '使用灰階與透明度混合兩張圖片；只生成視覺效果，不儲存可提取的原檔案。',
          CloakVersion.v5 => '使用彩色 RGBA 混合，保留更多顏色；只生成視覺效果，不儲存可提取的原檔案。',
        }
      : description;

  String noticeFor(bool traditional) => traditional
      ? (carriesFile
            ? '必須保留原始 PNG；壓縮、縮放或重新編碼可能破壞隱藏資料。'
            : '這是視覺合成模式，生成結果不包含兩張來源圖的無損副本。')
      : notice;
}

class PrismConfig {
  const PrismConfig({
    this.innerThreshold = 24,
    this.coverThreshold = 42,
    this.slope = 1,
    this.gap = 1,
    this.reverse = false,
    this.innerGray = false,
    this.coverGray = true,
  });

  final int innerThreshold;
  final int coverThreshold;
  final int slope;
  final int gap;
  final bool reverse;
  final bool innerGray;
  final bool coverGray;
}

class CloakConfig {
  const CloakConfig({
    this.version = CloakVersion.v5,
    this.difference = 24,
    this.innerScale = 0.3,
    this.coverScale = 0.2,
    this.innerWeight = 0.7,
    this.grayMode = false,
  });

  final CloakVersion version;
  final int difference;
  final double innerScale;
  final double coverScale;
  final double innerWeight;
  final bool grayMode;
}

class CloakDecodedFile {
  const CloakDecodedFile({
    required this.version,
    required this.extension,
    required this.bytes,
  });

  final CloakVersion version;
  final String extension;
  final List<int> bytes;
}

class FunToolException implements Exception {
  const FunToolException(this.message);

  final String message;

  @override
  String toString() => message;
}
