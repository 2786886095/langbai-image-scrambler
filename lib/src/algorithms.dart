import 'dart:math';
import 'dart:typed_data';

import 'models.dart';

class ImageRaster {
  const ImageRaster(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;
}

class ScrambleEngine {
  const ScrambleEngine._();

  static ImageRaster transform(
    ImageRaster source,
    ScrambleAlgorithm algorithm,
    int seed, {
    required bool reverse,
  }) {
    return switch (algorithm) {
      ScrambleAlgorithm.blockShuffle => _blockShuffle(source, seed, reverse),
      ScrambleAlgorithm.rowShift => _rowShift(source, seed, reverse),
      ScrambleAlgorithm.columnShift => _columnShift(source, seed, reverse),
      ScrambleAlgorithm.pixelPermutation => _pixelPermutation(
        source,
        seed,
        reverse,
      ),
      ScrambleAlgorithm.channelDisturbance => _channelDisturbance(
        source,
        seed,
        reverse,
      ),
      ScrambleAlgorithm.composite => _composite(source, seed, reverse),
      ScrambleAlgorithm.cherryTomato => _cherryTomato(source, reverse),
      ScrambleAlgorithm.auto => throw ArgumentError(
        'Automatic mode must resolve to an algorithm first.',
      ),
    };
  }

  static ImageRaster _blockShuffle(ImageRaster source, int seed, bool reverse) {
    final blockSize = 24 + (seed.abs() % 41);
    final groups = <String, List<_Tile>>{};
    for (var y = 0; y < source.height; y += blockSize) {
      for (var x = 0; x < source.width; x += blockSize) {
        final width = min(blockSize, source.width - x);
        final height = min(blockSize, source.height - y);
        groups
            .putIfAbsent('$width:$height', () => <_Tile>[])
            .add(_Tile(x, y, width, height));
      }
    }

    final output = Uint8List(source.rgba.length);
    final random = StableRandom(seed);
    for (final group in groups.values) {
      final permutation = List<int>.generate(group.length, (index) => index);
      random.shuffle(permutation);
      for (
        var destinationIndex = 0;
        destinationIndex < group.length;
        destinationIndex++
      ) {
        final sourceIndex = permutation[destinationIndex];
        final sourceTile = reverse
            ? group[destinationIndex]
            : group[sourceIndex];
        final destinationTile = reverse
            ? group[sourceIndex]
            : group[destinationIndex];
        _copyTile(source, output, sourceTile, destinationTile);
      }
    }
    return ImageRaster(source.width, source.height, output);
  }

  static ImageRaster _rowShift(ImageRaster source, int seed, bool reverse) {
    final output = Uint8List(source.rgba.length);
    if (source.width <= 1) {
      return ImageRaster(
        source.width,
        source.height,
        Uint8List.fromList(source.rgba),
      );
    }
    final random = StableRandom(seed);
    for (var y = 0; y < source.height; y++) {
      final shift = random.nextInt(source.width);
      for (var x = 0; x < source.width; x++) {
        final sourceX = reverse ? (x + shift) % source.width : x;
        final destinationX = reverse ? x : (x + shift) % source.width;
        _copyPixel(
          source.rgba,
          (y * source.width + sourceX) * 4,
          output,
          (y * source.width + destinationX) * 4,
        );
      }
    }
    return ImageRaster(source.width, source.height, output);
  }

  static ImageRaster _columnShift(ImageRaster source, int seed, bool reverse) {
    final output = Uint8List(source.rgba.length);
    if (source.height <= 1) {
      return ImageRaster(
        source.width,
        source.height,
        Uint8List.fromList(source.rgba),
      );
    }
    final random = StableRandom(seed);
    for (var x = 0; x < source.width; x++) {
      final shift = random.nextInt(source.height);
      for (var y = 0; y < source.height; y++) {
        final sourceY = reverse ? (y + shift) % source.height : y;
        final destinationY = reverse ? y : (y + shift) % source.height;
        _copyPixel(
          source.rgba,
          (sourceY * source.width + x) * 4,
          output,
          (destinationY * source.width + x) * 4,
        );
      }
    }
    return ImageRaster(source.width, source.height, output);
  }

  static ImageRaster _pixelPermutation(
    ImageRaster source,
    int seed,
    bool reverse,
  ) {
    final count = source.width * source.height;
    if (count <= 1) {
      return ImageRaster(
        source.width,
        source.height,
        Uint8List.fromList(source.rgba),
      );
    }
    final random = StableRandom(seed);
    var multiplier = random.nextInt(count - 1) + 1;
    while (_gcd(multiplier, count) != 1) {
      multiplier++;
      if (multiplier >= count) multiplier = 1;
    }
    final offset = random.nextInt(count);
    final output = Uint8List(source.rgba.length);
    for (var index = 0; index < count; index++) {
      final mapped = (multiplier * index + offset) % count;
      final sourceIndex = reverse ? mapped : index;
      final destinationIndex = reverse ? index : mapped;
      _copyPixel(source.rgba, sourceIndex * 4, output, destinationIndex * 4);
    }
    return ImageRaster(source.width, source.height, output);
  }

  static ImageRaster _channelDisturbance(
    ImageRaster source,
    int seed,
    bool reverse,
  ) {
    const permutations = <List<int>>[
      [0, 1, 2],
      [0, 2, 1],
      [1, 0, 2],
      [1, 2, 0],
      [2, 0, 1],
      [2, 1, 0],
    ];
    final permutation = permutations[seed.abs() % permutations.length];
    final random = StableRandom(seed ^ 0x7f4a7c15);
    final output = Uint8List(source.rgba.length);
    for (var index = 0; index < source.rgba.length; index += 4) {
      final mask = random.nextUint32();
      final maskChannels = [
        mask & 0xff,
        (mask >> 8) & 0xff,
        (mask >> 16) & 0xff,
      ];
      if (!reverse) {
        final mixed = <int>[
          source.rgba[index] ^ maskChannels[0],
          source.rgba[index + 1] ^ maskChannels[1],
          source.rgba[index + 2] ^ maskChannels[2],
        ];
        output[index] = mixed[permutation[0]];
        output[index + 1] = mixed[permutation[1]];
        output[index + 2] = mixed[permutation[2]];
      } else {
        final mixed = List<int>.filled(3, 0);
        mixed[permutation[0]] = source.rgba[index];
        mixed[permutation[1]] = source.rgba[index + 1];
        mixed[permutation[2]] = source.rgba[index + 2];
        output[index] = mixed[0] ^ maskChannels[0];
        output[index + 1] = mixed[1] ^ maskChannels[1];
        output[index + 2] = mixed[2] ^ maskChannels[2];
      }
      output[index + 3] = source.rgba[index + 3];
    }
    return ImageRaster(source.width, source.height, output);
  }

  static ImageRaster _composite(ImageRaster source, int seed, bool reverse) {
    if (!reverse) {
      final blocked = _blockShuffle(source, seed ^ 0x13579bdf, false);
      final shifted = _rowShift(blocked, seed ^ 0x2468ace0, false);
      return _channelDisturbance(shifted, seed ^ 0x5bd1e995, false);
    }
    final channels = _channelDisturbance(source, seed ^ 0x5bd1e995, true);
    final shifted = _rowShift(channels, seed ^ 0x2468ace0, true);
    return _blockShuffle(shifted, seed ^ 0x13579bdf, true);
  }

  static ImageRaster _cherryTomato(ImageRaster source, bool reverse) {
    final curve = _gilbert2d(source.width, source.height);
    final total = source.width * source.height;
    final offset = (((sqrt(5) - 1) / 2) * total).round();
    final output = Uint8List(source.rgba.length);
    for (var index = 0; index < total; index++) {
      final oldPosition = curve[index];
      final newPosition = curve[(index + offset) % total];
      final sourcePosition = reverse ? newPosition : oldPosition;
      final destinationPosition = reverse ? oldPosition : newPosition;
      _copyPixel(
        source.rgba,
        sourcePosition * 4,
        output,
        destinationPosition * 4,
      );
    }
    return ImageRaster(source.width, source.height, output);
  }

  static Int32List _gilbert2d(int width, int height) {
    final coordinates = Int32List(width * height);
    var cursor = 0;

    void generate(int x, int y, int ax, int ay, int bx, int by) {
      final w = (ax + ay).abs();
      final h = (bx + by).abs();
      final dax = ax.sign;
      final day = ay.sign;
      final dbx = bx.sign;
      final dby = by.sign;

      if (h == 1) {
        for (var index = 0; index < w; index++) {
          coordinates[cursor++] = x + y * width;
          x += dax;
          y += day;
        }
        return;
      }
      if (w == 1) {
        for (var index = 0; index < h; index++) {
          coordinates[cursor++] = x + y * width;
          x += dbx;
          y += dby;
        }
        return;
      }

      var ax2 = _floorHalf(ax);
      var ay2 = _floorHalf(ay);
      var bx2 = _floorHalf(bx);
      var by2 = _floorHalf(by);
      final w2 = (ax2 + ay2).abs();
      final h2 = (bx2 + by2).abs();

      if (2 * w > 3 * h) {
        if (w2.isOdd && w > 2) {
          ax2 += dax;
          ay2 += day;
        }
        generate(x, y, ax2, ay2, bx, by);
        generate(x + ax2, y + ay2, ax - ax2, ay - ay2, bx, by);
      } else {
        if (h2.isOdd && h > 2) {
          bx2 += dbx;
          by2 += dby;
        }
        generate(x, y, bx2, by2, ax2, ay2);
        generate(x + bx2, y + by2, ax, ay, bx - bx2, by - by2);
        generate(
          x + (ax - dax) + (bx2 - dbx),
          y + (ay - day) + (by2 - dby),
          -bx2,
          -by2,
          -(ax - ax2),
          -(ay - ay2),
        );
      }
    }

    if (width >= height) {
      generate(0, 0, width, 0, 0, height);
    } else {
      generate(0, 0, 0, height, width, 0);
    }
    return coordinates;
  }

  static int _floorHalf(int value) =>
      value >= 0 ? value ~/ 2 : -(((-value) + 1) ~/ 2);

  static int _gcd(int a, int b) {
    while (b != 0) {
      final remainder = a % b;
      a = b;
      b = remainder;
    }
    return a.abs();
  }

  static void _copyTile(
    ImageRaster source,
    Uint8List destination,
    _Tile sourceTile,
    _Tile destinationTile,
  ) {
    for (var row = 0; row < sourceTile.height; row++) {
      final sourceOffset =
          ((sourceTile.y + row) * source.width + sourceTile.x) * 4;
      final destinationOffset =
          ((destinationTile.y + row) * source.width + destinationTile.x) * 4;
      final byteLength = sourceTile.width * 4;
      destination.setRange(
        destinationOffset,
        destinationOffset + byteLength,
        source.rgba,
        sourceOffset,
      );
    }
  }

  static void _copyPixel(
    Uint8List source,
    int sourceOffset,
    Uint8List destination,
    int destinationOffset,
  ) {
    destination[destinationOffset] = source[sourceOffset];
    destination[destinationOffset + 1] = source[sourceOffset + 1];
    destination[destinationOffset + 2] = source[sourceOffset + 2];
    destination[destinationOffset + 3] = source[sourceOffset + 3];
  }
}

class StableRandom {
  StableRandom(int seed) : _state = seed & 0xffffffff {
    if (_state == 0) _state = 0x6d2b79f5;
  }

  int _state;

  int nextUint32() {
    _state = ((_state * 1664525) + 1013904223) & 0xffffffff;
    return _state;
  }

  int nextInt(int maximum) {
    if (maximum <= 0) return 0;
    return nextUint32() % maximum;
  }

  void shuffle<T>(List<T> values) {
    for (var index = values.length - 1; index > 0; index--) {
      final other = nextInt(index + 1);
      final temporary = values[index];
      values[index] = values[other];
      values[other] = temporary;
    }
  }
}

class _Tile {
  const _Tile(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;
}
