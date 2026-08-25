import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/image_ops.dart';

/// Interactive perspective crop: drag the four corner nodes over the photo to
/// mark the document edges, then the image is warped into a flat rectangle.
class PerspectiveCropScreen extends StatefulWidget {
  const PerspectiveCropScreen({
    super.key,
    required this.sourcePath,
    this.filter = ScanFilter.enhance,
    this.forceHorizontal = false,
    this.title = 'Adjust edges',
  });

  final String sourcePath;
  final ScanFilter filter;
  final bool forceHorizontal;
  final String title;

  @override
  State<PerspectiveCropScreen> createState() => _PerspectiveCropScreenState();
}

class _PerspectiveCropScreenState extends State<PerspectiveCropScreen> {
  /// Normalised corners: TL, TR, BR, BL.
  List<Offset> _corners = const [
    Offset(0.1, 0.14),
    Offset(0.9, 0.14),
    Offset(0.9, 0.86),
    Offset(0.1, 0.86),
  ];

  int _drag = -1;
  bool _busy = false;
  int _quarterTurns = 0;
  late ScanFilter _filter = widget.filter;
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _quarterTurns = widget.forceHorizontal ? 1 : 0;
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.sourcePath).readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      if (mounted) setState(() => _image = decoded);
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Rect _fitRect(Size box) {
    final im = _image;
    if (im == null) return Offset.zero & box;
    final scale = (box.width / im.width) < (box.height / im.height)
        ? box.width / im.width
        : box.height / im.height;
    final w = im.width * scale, h = im.height * scale;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  void _onDown(Offset local, Rect rect) {
    var best = -1;
    var bestDist = 48.0;
    for (var i = 0; i < 4; i++) {
      final p = Offset(
        rect.left + _corners[i].dx * rect.width,
        rect.top + _corners[i].dy * rect.height,
      );
      final d = (p - local).distance;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    setState(() => _drag = best);
  }

  void _onMove(Offset local, Rect rect) {
    if (_drag < 0) return;
    final nx = ((local.dx - rect.left) / rect.width).clamp(0.0, 1.0);
    final ny = ((local.dy - rect.top) / rect.height).clamp(0.0, 1.0);
    setState(() => _corners = [
          for (var i = 0; i < 4; i++)
            i == _drag ? Offset(nx, ny) : _corners[i],
        ]);
  }

  void _reset() => setState(() => _corners = const [
        Offset(0.02, 0.02),
        Offset(0.98, 0.02),
        Offset(0.98, 0.98),
        Offset(0.02, 0.98),
      ]);

  Future<void> _apply() async {
    if (_busy) return;
    setState(() => _busy = true);
    final quad = <double>[
      for (final c in _corners) ...[c.dx, c.dy],
    ];
    final out = await ImageOps.process(
      source: widget.sourcePath,
      quad: quad,
      quarterTurns: _quarterTurns,
      filter: _filter,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title,
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        actions: [
          IconButton(
            tooltip: 'Rotate',
            onPressed: () =>
                setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
            icon: const Icon(Icons.rotate_90_degrees_cw_rounded),
          ),
          IconButton(
            tooltip: 'Select whole photo',
            onPressed: _reset,
            icon: const Icon(Icons.select_all_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _image == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final box =
                          Size(constraints.maxWidth, constraints.maxHeight);
                      final rect = _fitRect(box);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanDown: (d) => _onDown(d.localPosition, rect),
                        onPanUpdate: (d) => _onMove(d.localPosition, rect),
                        onPanEnd: (_) => setState(() => _drag = -1),
                        child: CustomPaint(
                          size: box,
                          painter: _CropPainter(
                            image: _image!,
                            rect: rect,
                            corners: _corners,
                            accent: scheme.primary,
                            active: _drag,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              children: ScanFilter.values.map((f) {
                final selected = f == _filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: selected,
                    onSelected: (_) => setState(() => _filter = f),
                    label: Text(f.label),
                    labelStyle: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: Colors.white24,
                    selectedColor: Colors.white,
                    side: BorderSide.none,
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white30),
                    ),
                    child: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _apply,
                    icon: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_busy ? 'Processing…' : 'Use this crop'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.image,
    required this.rect,
    required this.corners,
    required this.accent,
    required this.active,
  });

  final ui.Image image;
  final Rect rect;
  final List<Offset> corners;
  final Color accent;
  final int active;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    final pts = [
      for (final c in corners)
        Offset(rect.left + c.dx * rect.width, rect.top + c.dy * rect.height)
    ];

    final poly = Path()..addPolygon(pts, true);
    final outer = Path()..addRect(Offset.zero & size);
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, poly),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    canvas.drawPath(
      poly,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = accent,
    );

    for (var i = 0; i < pts.length; i++) {
      final r = active == i ? 16.0 : 12.0;
      canvas.drawCircle(
          pts[i], r, Paint()..color = accent.withValues(alpha: 0.28));
      canvas.drawCircle(pts[i], r * 0.55, Paint()..color = accent);
      canvas.drawCircle(
        pts[i],
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) =>
      old.corners != corners || old.rect != rect || old.active != active;
}
