# Apache Commons Compress supports Zstandard through an optional dependency.
# This app only uses its ZIP/7Z/RAR paths, so the absent Zstd adapter is never
# instantiated and can be omitted from the release package.
-dontwarn com.github.luben.zstd.ZstdInputStream

# Keep the embedded yt-dlp/FFmpeg Java bridge and its exception surface.
-keep class com.yausername.** { *; }
