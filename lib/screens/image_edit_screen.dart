import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../services/image_edit.dart';
import '../services/ocr.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';

/// 拍照 / 选图之后、识别之前的编辑页：裁切 + 90° 旋转。
///
/// 不用原生裁切插件（uCrop / TOCropViewController）：那套 UI 跟本应用
/// 对不上，Web 还得另引 Cropper.js。这里用 `dart:ui` 自己画，三端同一套。
Future<XFile?> openImageEditor(BuildContext context, XFile file) {
  return Navigator.of(context).push<XFile>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImageEditScreen(file: file),
    ),
  );
}

class ImageEditScreen extends StatefulWidget {
  const ImageEditScreen({
    super.key,
    required this.file,
    @visibleForTesting this.decodedImage,
  });

  final XFile file;

  /// 测试里跳过异步解码，避免转圈动画把 `pumpAndSettle` 卡死。
  final ui.Image? decodedImage;

  @override
  State<ImageEditScreen> createState() => _ImageEditScreenState();
}

enum _LoadStatus { loading, ready, failed }

class _ImageEditScreenState extends State<ImageEditScreen> {
  _LoadStatus _status = _LoadStatus.loading;
  ui.Image? _image;
  int _turns = 0;
  Rect _crop = const Rect.fromLTWH(0, 0, 1, 1);
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final preload = widget.decodedImage;
    if (preload != null) {
      _image = preload;
      _status = _LoadStatus.ready;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.file.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('empty');
      }
      final image = await decodeImageForEdit(bytes);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image = image;
        _status = _LoadStatus.ready;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _status = _LoadStatus.failed);
      }
    }
  }

  void _rotate(int delta) {
    Haptics.tapLight();
    setState(() {
      _turns = (_turns + delta) % 4;
      _crop = const Rect.fromLTWH(0, 0, 1, 1);
    });
  }

  void _resetCrop() {
    Haptics.tapLight();
    setState(() => _crop = const Rect.fromLTWH(0, 0, 1, 1));
  }

  void _cancel() => Navigator.of(context).pop();

  Future<void> _confirm() async {
    final image = _image;
    if (image == null || _exporting) return;

    final transform = ImageEditTransform(quarterTurns: _turns, crop: _crop);
    if (transform.isIdentity) {
      Navigator.of(context).pop(widget.file);
      return;
    }

    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final edited = await renderEditedImage(
        source: image,
        transform: transform,
      );
      Uint8List png;
      try {
        png = await encodePng(edited);
      } finally {
        edited.dispose();
      }
      if (!mounted) return;
      Navigator.of(context).pop(xFileFromPngBytes(png));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _error = '导出失败，请重试';
      });
    }
  }

  void _skipEdit() => Navigator.of(context).pop(widget.file);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              colors: colors,
              onCancel: _exporting ? null : _cancel,
              onConfirm: _status == _LoadStatus.ready && !_exporting
                  ? _confirm
                  : null,
            ),
            Expanded(child: _buildBody(colors)),
            if (_status == _LoadStatus.ready) _Toolbar(onRotate: _rotate, onReset: _resetCrop),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppColors colors) {
    switch (_status) {
      case _LoadStatus.loading:
        return Center(
          child: CircularProgressIndicator(color: colors.primary),
        );
      case _LoadStatus.failed:
        return _FailedPane(
          colors: colors,
          onCancel: _cancel,
          onSkip: _skipEdit,
        );
      case _LoadStatus.ready:
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: colors.surfaceSunken,
              child: _CropViewport(
                image: _image!,
                quarterTurns: _turns,
                crop: _crop,
                onCropChanged: (crop) => setState(() => _crop = crop),
              ),
            ),
            if (_error != null)
              Positioned(
                left: Spacing.lg,
                right: Spacing.lg,
                bottom: Spacing.sm,
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: colors.danger),
                ),
              ),
            if (_exporting)
              ColoredBox(
                color: colors.overlay,
                child: Center(
                  child: CircularProgressIndicator(color: colors.primary),
                ),
              ),
          ],
        );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.colors,
    required this.onCancel,
    required this.onConfirm,
  });

  final AppColors colors;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.xs,
      ),
      child: Row(
        children: [
          _HeaderAction(
            label: '取消',
            color: colors.muted,
            onTap: onCancel,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '调整图片',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.displayZh,
                    fontSize: 18,
                    letterSpacing: 0.3,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '裁切出单词区域，旋转纠正方向',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: colors.subtle),
                ),
              ],
            ),
          ),
          _HeaderAction(
            label: '完成',
            color: colors.primary,
            onTap: onConfirm,
          ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 36),
          child: Align(
            alignment: Alignment.center,
            child: Opacity(
              opacity: onTap == null ? 0.4 : 1,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.onRotate, required this.onReset});

  final void Function(int delta) onRotate;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ToolButton(
            icon: AppIcons.rotateLeft,
            label: '向左旋转',
            colors: colors,
            onTap: () => onRotate(-1),
          ),
          _ToolButton(
            icon: AppIcons.rotateRight,
            label: '向右旋转',
            colors: colors,
            onTap: () => onRotate(1),
          ),
          _ToolButton(
            icon: AppIcons.refresh,
            label: '重置裁切',
            colors: colors,
            onTap: onReset,
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: colors.foreground),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FailedPane extends StatelessWidget {
  const _FailedPane({
    required this.colors,
    required this.onCancel,
    required this.onSkip,
  });

  final AppColors colors;
  final VoidCallback onCancel;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.alertCircle, size: 28, color: colors.danger),
          const SizedBox(height: Spacing.md),
          Text(
            '无法打开这张图片',
            style: TextStyle(
              fontFamily: AppFonts.displayZh,
              fontSize: 17,
              color: colors.foreground,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            '可以跳过编辑，直接拿原图去识别。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: colors.muted),
          ),
          const SizedBox(height: Spacing.xl),
          AppButton(
            label: '仍要识别',
            variant: ButtonVariant.primary,
            onPressed: onSkip,
          ),
          const SizedBox(height: Spacing.sm),
          AppButton(
            label: '取消',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

enum _Grab { none, move, n, s, e, w, ne, nw, se, sw }

class _CropViewport extends StatefulWidget {
  const _CropViewport({
    required this.image,
    required this.quarterTurns,
    required this.crop,
    required this.onCropChanged,
  });

  final ui.Image image;
  final int quarterTurns;
  final Rect crop;
  final ValueChanged<Rect> onCropChanged;

  @override
  State<_CropViewport> createState() => _CropViewportState();
}

class _CropViewportState extends State<_CropViewport> {
  static const double _pad = 24;
  static const double _handleHit = 22;

  _Grab _grab = _Grab.none;
  Rect _startCrop = Rect.zero;
  Offset _startPos = Offset.zero;
  _Layout? _layout;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _measure(constraints.biggest);
        _layout = layout;

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: (_) => _grab = _Grab.none,
          child: CustomPaint(
            size: constraints.biggest,
            painter: _CropPainter(
              image: widget.image,
              quarterTurns: widget.quarterTurns,
              crop: widget.crop,
              layout: layout,
              gold: context.colors.gold,
              overlay: context.colors.overlay,
            ),
          ),
        );
      },
    );
  }

  _Layout _measure(Size viewport) {
    final rotated = rotatedImageSize(
      widget.image.width,
      widget.image.height,
      widget.quarterTurns,
    );
    final box = Size(
      (viewport.width - _pad * 2).clamp(1, viewport.width),
      (viewport.height - _pad * 2).clamp(1, viewport.height),
    );
    final scale = (box.width / rotated.width).clamp(0, double.infinity);
    final scaleY = box.height / rotated.height;
    final used = scale < scaleY ? scale : scaleY;
    final disp = Size(rotated.width * used, rotated.height * used);
    final origin = Offset(
      (viewport.width - disp.width) / 2,
      (viewport.height - disp.height) / 2,
    );
    return _Layout(origin: origin, display: disp, minNorm: (
      width: (32 / disp.width).clamp(0.02, 0.5),
      height: (32 / disp.height).clamp(0.02, 0.5),
    ));
  }

  Rect _viewCrop(_Layout layout) {
    return Rect.fromLTWH(
      layout.origin.dx + widget.crop.left * layout.display.width,
      layout.origin.dy + widget.crop.top * layout.display.height,
      widget.crop.width * layout.display.width,
      widget.crop.height * layout.display.height,
    );
  }

  void _onDown(PointerDownEvent event) {
    final layout = _layout;
    if (layout == null) return;
    _grab = _hitTest(event.localPosition, _viewCrop(layout));
    _startCrop = widget.crop;
    _startPos = event.localPosition;
  }

  void _onMove(PointerMoveEvent event) {
    final layout = _layout;
    if (layout == null || _grab == _Grab.none) return;
    final dx = (event.localPosition.dx - _startPos.dx) / layout.display.width;
    final dy = (event.localPosition.dy - _startPos.dy) / layout.display.height;
    final min = layout.minNorm.width > layout.minNorm.height
        ? layout.minNorm.width
        : layout.minNorm.height;
    widget.onCropChanged(_applyGrab(_startCrop, _grab, dx, dy, min));
  }

  void _onUp(PointerUpEvent event) {
    _grab = _Grab.none;
  }

  _Grab _hitTest(Offset point, Rect crop) {
    bool near(Offset corner) => (point - corner).distance <= _handleHit;
    if (near(crop.topLeft)) return _Grab.nw;
    if (near(crop.topRight)) return _Grab.ne;
    if (near(crop.bottomLeft)) return _Grab.sw;
    if (near(crop.bottomRight)) return _Grab.se;

    bool onH(double y) =>
        (point.dy - y).abs() <= 16 &&
        point.dx >= crop.left &&
        point.dx <= crop.right;
    bool onV(double x) =>
        (point.dx - x).abs() <= 16 &&
        point.dy >= crop.top &&
        point.dy <= crop.bottom;
    if (onH(crop.top)) return _Grab.n;
    if (onH(crop.bottom)) return _Grab.s;
    if (onV(crop.left)) return _Grab.w;
    if (onV(crop.right)) return _Grab.e;
    if (crop.contains(point)) return _Grab.move;
    return _Grab.none;
  }

  Rect _applyGrab(Rect start, _Grab grab, double dx, double dy, double min) {
    if (grab == _Grab.move) {
      final width = start.width;
      final height = start.height;
      final left = (start.left + dx).clamp(0.0, 1.0 - width);
      final top = (start.top + dy).clamp(0.0, 1.0 - height);
      return Rect.fromLTWH(left, top, width, height);
    }

    var left = start.left;
    var top = start.top;
    var right = start.right;
    var bottom = start.bottom;

    if (grab == _Grab.w || grab == _Grab.nw || grab == _Grab.sw) {
      left = start.left + dx;
    }
    if (grab == _Grab.e || grab == _Grab.ne || grab == _Grab.se) {
      right = start.right + dx;
    }
    if (grab == _Grab.n || grab == _Grab.nw || grab == _Grab.ne) {
      top = start.top + dy;
    }
    if (grab == _Grab.s || grab == _Grab.sw || grab == _Grab.se) {
      bottom = start.bottom + dy;
    }

    if (right - left < min) {
      if (grab == _Grab.w || grab == _Grab.nw || grab == _Grab.sw) {
        left = right - min;
      } else {
        right = left + min;
      }
    }
    if (bottom - top < min) {
      if (grab == _Grab.n || grab == _Grab.nw || grab == _Grab.ne) {
        top = bottom - min;
      } else {
        bottom = top + min;
      }
    }

    return clampNormalizedCrop(
      Rect.fromLTRB(left, top, right, bottom),
      minSize: min,
    );
  }
}

class _Layout {
  const _Layout({
    required this.origin,
    required this.display,
    required this.minNorm,
  });

  final Offset origin;
  final Size display;
  final ({double width, double height}) minNorm;
}

class _CropPainter extends CustomPainter {
  const _CropPainter({
    required this.image,
    required this.quarterTurns,
    required this.crop,
    required this.layout,
    required this.gold,
    required this.overlay,
  });

  final ui.Image image;
  final int quarterTurns;
  final Rect crop;
  final _Layout layout;
  final Color gold;
  final Color overlay;

  @override
  void paint(Canvas canvas, Size size) {
    final imageRect = layout.origin & layout.display;
    canvas.save();
    canvas.translate(layout.origin.dx, layout.origin.dy);
    canvas.scale(
      layout.display.width /
          rotatedImageSize(image.width, image.height, quarterTurns).width,
    );
    drawRotatedImage(canvas, image, quarterTurns);
    canvas.restore();

    final cropRect = Rect.fromLTWH(
      imageRect.left + crop.left * imageRect.width,
      imageRect.top + crop.top * imageRect.height,
      crop.width * imageRect.width,
      crop.height * imageRect.height,
    );

    final dim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(cropRect),
    );
    canvas.drawPath(dim, Paint()..color = overlay);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = gold;
    canvas.drawRect(cropRect, border);

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = gold.withValues(alpha: 0.35);
    for (var i = 1; i <= 2; i++) {
      final x = cropRect.left + cropRect.width * i / 3;
      final y = cropRect.top + cropRect.height * i / 3;
      canvas.drawLine(Offset(x, cropRect.top), Offset(x, cropRect.bottom), grid);
      canvas.drawLine(Offset(cropRect.left, y), Offset(cropRect.right, y), grid);
    }

    final handle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.square
      ..color = gold;
    const arm = 18.0;
    _corner(canvas, handle, cropRect.topLeft, arm, arm);
    _corner(canvas, handle, cropRect.topRight, -arm, arm);
    _corner(canvas, handle, cropRect.bottomLeft, arm, -arm);
    _corner(canvas, handle, cropRect.bottomRight, -arm, -arm);
  }

  void _corner(Canvas canvas, Paint paint, Offset origin, double dx, double dy) {
    canvas.drawLine(origin, origin.translate(dx, 0), paint);
    canvas.drawLine(origin, origin.translate(0, dy), paint);
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) {
    return old.image != image ||
        old.quarterTurns != quarterTurns ||
        old.crop != crop ||
        old.layout.origin != layout.origin ||
        old.layout.display != layout.display ||
        old.gold != gold ||
        old.overlay != overlay;
  }
}
