import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image_picker/image_picker.dart';

/// 拍照识词用的编辑结果：在「已经转正」的图上裁一块。
///
/// [crop] 是归一化矩形（0–1），坐标系是旋转之后那张图，不是原图。
/// 这样编辑页上拖的框和导出去的像素是同一套数字，不用来回换算。
@immutable
class ImageEditTransform {
  const ImageEditTransform({
    this.quarterTurns = 0,
    this.crop = const Rect.fromLTWH(0, 0, 1, 1),
  });

  /// 顺时针 90° 的次数。
  final int quarterTurns;

  final Rect crop;

  int get turns => quarterTurns % 4;

  bool get isIdentity => turns == 0 && isIdentityCrop(crop);
}

/// 几乎铺满整张图的裁切框，按「没裁」处理，好把原图原路送去压缩。
bool isIdentityCrop(Rect crop) {
  return crop.left.abs() < 1e-3 &&
      crop.top.abs() < 1e-3 &&
      (crop.width - 1).abs() < 1e-3 &&
      (crop.height - 1).abs() < 1e-3;
}

Size rotatedImageSize(int width, int height, int quarterTurns) {
  return quarterTurns % 2 == 0
      ? Size(width.toDouble(), height.toDouble())
      : Size(height.toDouble(), width.toDouble());
}

/// 把裁切框关进 [0,1]，并保证最小边。
Rect clampNormalizedCrop(Rect crop, {double minSize = 0.08}) {
  final min = minSize.clamp(0.02, 1.0);
  var left = crop.left;
  var top = crop.top;
  var right = crop.right;
  var bottom = crop.bottom;
  if (right - left < min) {
    final mid = ((left + right) / 2).clamp(min / 2, 1 - min / 2);
    left = mid - min / 2;
    right = mid + min / 2;
  }
  if (bottom - top < min) {
    final mid = ((top + bottom) / 2).clamp(min / 2, 1 - min / 2);
    top = mid - min / 2;
    bottom = mid + min / 2;
  }
  left = left.clamp(0.0, 1.0);
  top = top.clamp(0.0, 1.0);
  right = right.clamp(0.0, 1.0);
  bottom = bottom.clamp(0.0, 1.0);
  if (right - left < min) {
    if (left <= 0) {
      right = min;
    } else {
      left = 1 - min;
    }
  }
  if (bottom - top < min) {
    if (top <= 0) {
      bottom = min;
    } else {
      top = 1 - min;
    }
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

/// 解码并在最长边超过 [maxEdge] 时等比缩小。
///
/// 编辑页要挂一张 `ui.Image` 做预览；12MP 原图整张进 GPU 在中低端机上
/// 会把预览卡成幻灯片。OCR 自己还会压到 1600px，这里 2400 已经留足。
Future<ui.Image> decodeImageForEdit(
  Uint8List bytes, {
  int maxEdge = 2400,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    if (width <= 0 || height <= 0) {
      throw Exception('无法读取图片');
    }
    final longest = math.max(width, height);
    int? targetWidth;
    int? targetHeight;
    if (longest > maxEdge) {
      final scale = maxEdge / longest;
      targetWidth = math.max(1, (width * scale).round());
      targetHeight = math.max(1, (height * scale).round());
    }
    final codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: maxEdge,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}

/// 按 [ImageEditTransform] 把原图画进一张新图。
Future<ui.Image> renderEditedImage({
  required ui.Image source,
  required ImageEditTransform transform,
}) async {
  final turns = transform.turns;
  final rotated = rotatedImageSize(source.width, source.height, turns);
  final crop = _pixelCrop(transform.crop, rotated);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.translate(-crop.left, -crop.top);
  drawRotatedImage(canvas, source, turns);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(crop.width.round(), crop.height.round());
  } finally {
    picture.dispose();
  }
}

/// 把原图按 90° 的倍数画到「旋转后画布」的 (0,0) 原点。
void drawRotatedImage(Canvas canvas, ui.Image image, int quarterTurns) {
  final paint = Paint()..filterQuality = FilterQuality.none;
  final width = image.width.toDouble();
  final height = image.height.toDouble();
  switch (quarterTurns % 4) {
    case 1:
      canvas
        ..translate(height, 0)
        ..rotate(math.pi / 2);
      break;
    case 2:
      canvas
        ..translate(width, height)
        ..rotate(math.pi);
      break;
    case 3:
      canvas
        ..translate(0, width)
        ..rotate(-math.pi / 2);
      break;
  }
  canvas.drawImage(image, Offset.zero, paint);
}

Rect _pixelCrop(Rect normalized, Size rotated) {
  var left = (normalized.left * rotated.width).floorToDouble();
  var top = (normalized.top * rotated.height).floorToDouble();
  var right = (normalized.right * rotated.width).ceilToDouble();
  var bottom = (normalized.bottom * rotated.height).ceilToDouble();
  left = left.clamp(0, rotated.width);
  top = top.clamp(0, rotated.height);
  right = right.clamp(left + 1, rotated.width);
  bottom = bottom.clamp(top + 1, rotated.height);
  return Rect.fromLTRB(left, top, right, bottom);
}

Future<Uint8List> encodePng(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw Exception('导出图片失败');
  }
  return data.buffer.asUint8List();
}

/// 内存里的 PNG。Web 上没有真实路径；原生上 path 也是空的，压缩那边
/// 必须走 `compressWithList`，不能拿 path 当文件读。
XFile xFileFromPngBytes(Uint8List bytes, {String name = 'ocr-edit.png'}) {
  return XFile.fromData(
    bytes,
    mimeType: 'image/png',
    name: name,
  );
}
