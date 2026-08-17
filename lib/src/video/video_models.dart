enum VideoAlgorithm { auto, gilbert, blockShuffle, rowColumnShift }

extension VideoAlgorithmX on VideoAlgorithm {
  String get id => switch (this) {
    VideoAlgorithm.auto => 'auto',
    VideoAlgorithm.gilbert => 'gilbert',
    VideoAlgorithm.blockShuffle => 'block_shuffle',
    VideoAlgorithm.rowColumnShift => 'row_column_shift',
  };

  String get title => switch (this) {
    VideoAlgorithm.auto => '自动识别',
    VideoAlgorithm.gilbert => 'Gilbert 曲线逐帧混淆',
    VideoAlgorithm.blockShuffle => '网格分块打乱',
    VideoAlgorithm.rowColumnShift => '行列循环位移',
  };

  String get description => switch (this) {
    VideoAlgorithm.auto => '优先读取视频内的 Langbai 标识；识别不到时再手动选择。',
    VideoAlgorithm.gilbert => '沿 Gilbert 空间填充曲线循环移动每帧像素，画面连贯且可逆。',
    VideoAlgorithm.blockShuffle => '使用固定随机种子重排每一帧的网格块，处理速度较快。',
    VideoAlgorithm.rowColumnShift => '分别循环移动每一行和每一列，形成条带式动态混淆。',
  };

  String titleFor(bool traditional) => traditional
      ? switch (this) {
          VideoAlgorithm.auto => '自動識別',
          VideoAlgorithm.gilbert => 'Gilbert 曲線逐幀混淆',
          VideoAlgorithm.blockShuffle => '網格分塊打亂',
          VideoAlgorithm.rowColumnShift => '行列循環位移',
        }
      : title;

  String descriptionFor(bool traditional) => traditional
      ? switch (this) {
          VideoAlgorithm.auto => '優先讀取影片內的 Langbai 標識；識別不到時再手動選擇。',
          VideoAlgorithm.gilbert => '沿 Gilbert 空間填充曲線循環移動每幀像素，畫面連貫且可逆。',
          VideoAlgorithm.blockShuffle => '使用固定隨機種子重排每一幀的網格塊，處理速度較快。',
          VideoAlgorithm.rowColumnShift => '分別循環移動每一行和每一列，形成條帶式動態混淆。',
        }
      : description;

  static VideoAlgorithm fromId(String? value) =>
      VideoAlgorithm.values.firstWhere(
        (item) => item.id == value,
        orElse: () => VideoAlgorithm.auto,
      );
}

enum VideoAudioMode { keep, reversibleScramble }

extension VideoAudioModeX on VideoAudioMode {
  String get id => this == VideoAudioMode.keep ? 'keep' : 'reverse';
  String get title => this == VideoAudioMode.keep ? '保留正常音频' : '可逆混淆音频';

  String titleFor(bool traditional) =>
      traditional ? (this == VideoAudioMode.keep ? '保留正常音訊' : '可逆混淆音訊') : title;

  static VideoAudioMode fromId(String? value) => value == 'reverse'
      ? VideoAudioMode.reversibleScramble
      : VideoAudioMode.keep;
}

class VideoManifest {
  const VideoManifest({
    required this.originalName,
    required this.originalLength,
    required this.originalSha256,
    required this.algorithm,
    required this.audioMode,
    required this.seed,
    required this.passwordProtected,
    required this.chunkSize,
    this.salt,
    this.baseNonce,
  });

  final String originalName;
  final int originalLength;
  final String originalSha256;
  final VideoAlgorithm algorithm;
  final VideoAudioMode audioMode;
  final int seed;
  final bool passwordProtected;
  final int chunkSize;
  final List<int>? salt;
  final List<int>? baseNonce;
}

class VideoInspection {
  const VideoInspection({
    required this.hasExactPayload,
    required this.algorithm,
    required this.audioMode,
    required this.seed,
    this.originalName,
    this.passwordProtected = false,
  });

  final bool hasExactPayload;
  final VideoAlgorithm algorithm;
  final VideoAudioMode audioMode;
  final int seed;
  final String? originalName;
  final bool passwordProtected;
}

class VideoProcessResult {
  const VideoProcessResult({
    required this.path,
    required this.outputName,
    required this.exact,
    required this.algorithm,
  });

  final String path;
  final String outputName;
  final bool exact;
  final VideoAlgorithm algorithm;
}

class VideoProcessException implements Exception {
  const VideoProcessException(this.message);
  final String message;

  @override
  String toString() => message;
}
