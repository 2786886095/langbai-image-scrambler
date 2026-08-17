import 'package:path/path.dart' as path;

import '../archive_service.dart';
import '../models.dart';

const supportedVideoExtensions = {'mp4', 'mkv', 'webm', 'mov', 'm4v', 'avi'};

bool isSupportedVideoName(String name) => supportedVideoExtensions.contains(
  path.extension(name).replaceFirst('.', '').toLowerCase(),
);

class VideoBatchInput {
  const VideoBatchInput({
    required this.id,
    required this.name,
    this.sourcePath,
    this.sourceUri,
    this.relativeDirectory = '',
    this.sourceRootName = '',
    this.sourceRootId = '',
    this.sizeBytes = 0,
  });

  final String id;
  final String name;
  final String? sourcePath;
  final String? sourceUri;
  final String relativeDirectory;
  final String sourceRootName;
  final String sourceRootId;
  final int sizeBytes;
}

class VideoBatchOutput {
  const VideoBatchOutput({
    required this.input,
    required this.path,
    required this.outputName,
  });

  final VideoBatchInput input;
  final String path;
  final String outputName;
}

List<ArchiveGroupPlan> planVideoArchives({
  required List<VideoBatchOutput> outputs,
  required CompressionGrouping grouping,
  DateTime? now,
}) {
  if (outputs.isEmpty) return const [];
  ArchiveEntryInput entry(VideoBatchOutput output, {bool includeRoot = false}) {
    final segments = <String>[
      if (includeRoot && output.input.sourceRootName.isNotEmpty)
        output.input.sourceRootName,
      if (output.input.relativeDirectory.isNotEmpty)
        ...output.input.relativeDirectory.split(RegExp(r'[/\\]+')),
      output.outputName,
    ].map(sanitizeFileName).toList();
    return ArchiveEntryInput(
      sourcePath: output.path,
      archivePath: segments.join('/'),
    );
  }

  switch (grouping) {
    case CompressionGrouping.perFile:
      return [
        for (final output in outputs)
          ArchiveGroupPlan(
            baseName: sanitizeFileName(
              basenameWithoutExtension(output.outputName),
            ),
            entries: [entry(output)],
          ),
      ];
    case CompressionGrouping.perFolder:
      final grouped = <String, List<VideoBatchOutput>>{};
      for (final output in outputs) {
        final key = output.input.sourceRootId.isNotEmpty
            ? output.input.sourceRootId
            : output.input.id;
        grouped.putIfAbsent(key, () => []).add(output);
      }
      return [
        for (final group in grouped.values)
          ArchiveGroupPlan(
            baseName: sanitizeFileName(
              group.first.input.sourceRootName.isNotEmpty
                  ? group.first.input.sourceRootName
                  : basenameWithoutExtension(group.first.outputName),
            ),
            entries: _uniqueArchiveEntries([
              for (final output in group) entry(output),
            ]),
          ),
      ];
    case CompressionGrouping.combined:
      final instant = now ?? DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');
      final stamp =
          '${instant.year}${two(instant.month)}${two(instant.day)}_'
          '${two(instant.hour)}${two(instant.minute)}${two(instant.second)}';
      return [
        ArchiveGroupPlan(
          baseName: 'Langbai_视频混淆_$stamp',
          entries: _uniqueArchiveEntries([
            for (final output in outputs) entry(output, includeRoot: true),
          ]),
        ),
      ];
  }
}

List<ArchiveEntryInput> _uniqueArchiveEntries(List<ArchiveEntryInput> entries) {
  final used = <String>{};
  return [
    for (final entry in entries)
      ArchiveEntryInput(
        sourcePath: entry.sourcePath,
        archivePath: _reserveArchivePath(entry.archivePath, used),
      ),
  ];
}

String _reserveArchivePath(String desired, Set<String> used) {
  final normalized = desired.replaceAll('\\', '/');
  if (used.add(normalized.toLowerCase())) return normalized;
  final extension = path.extension(normalized);
  final base = normalized.substring(0, normalized.length - extension.length);
  var index = 1;
  while (true) {
    final candidate = '$base（$index）$extension';
    if (used.add(candidate.toLowerCase())) return candidate;
    index++;
  }
}
