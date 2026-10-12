import 'dart:io';
import 'package:image/image.dart' as img;

int _quantize8(int v) => (v ~/ 16).clamp(0, 15);

bool _isNearWhite(int r, int g, int b) => r > 245 && g > 245 && b > 245;

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'assets/icon/icon.png';
  final bytes = File(path).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    stderr.writeln('Failed to decode image: $path');
    exitCode = 1;
    return;
  }

  final counts = <int, int>{};
  for (var y = 0; y < decoded.height; y += 2) {
    for (var x = 0; x < decoded.width; x += 2) {
      final p = decoded.getPixel(x, y);
      final a = p.a.toInt();
      if (a < 220) continue;
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      if (_isNearWhite(r, g, b)) continue;
      final key = (_quantize8(r) << 8) | (_quantize8(g) << 4) | _quantize8(b);
      counts.update(key, (v) => v + 1, ifAbsent: () => 1);
    }
  }

  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final top = sorted.take(20).toList();
  stdout.writeln('Top colors (quantized, excluding near-white background):');
  for (final e in top) {
    final r4 = (e.key >> 8) & 0xF;
    final g4 = (e.key >> 4) & 0xF;
    final b4 = e.key & 0xF;
    final r = (r4 * 16 + 8).clamp(0, 255);
    final g = (g4 * 16 + 8).clamp(0, 255);
    final b = (b4 * 16 + 8).clamp(0, 255);
    final hex = '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
    stdout.writeln('$hex\tcount=${e.value}');
  }
}
