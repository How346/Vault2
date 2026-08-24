import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/image_ops.dart';
import 'perspective_crop_screen.dart';

/// A captured + cropped page.
class ScanPage {
  ScanPage({required this.path, required this.label});
  final String path;
  final String label;
}

/// Smart camera with a live document guide, side prompts, flash, filters and
/// a forced-horizontal (ID card) layout. Returns the captured pages.
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key, this.dualSided = true});

  /// When true the flow asks for a front side, then a back side.
  final bool dualSided;

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  String? _fatal;

  final List<ScanPage> _pages = [];
  ScanFilter _filter = ScanFilter.enhance;
  bool _torch = false;
  bool _horizontal = false;
  bool _busy = false;

  List<double>? _edges;
  bool _detecting = false;
  DateTime _lastDetect = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFuture = _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

  Future<void> _disposeCamera() async {
    final c = _controller;
    _controller = null;
    try {
      if (c != null && c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    try {
      await c?.dispose();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _disposeCamera();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      setState(() => _initFuture = _boot());
    }
  }

  Future<void> _boot() async {
    try {
      var status = await Permission.camera.status;
      if (!status.isGranted && !status.isLimited) {
        status = await Permission.camera.request();
      }
      if (!status.isGranted && !status.isLimited) {
        setState(() => _fatal = 'Camera permission is needed to scan.');
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _fatal = 'No camera found on this device.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      _startDetection();
      setState(() => _fatal = null);
    } catch (e) {
      if (mounted) setState(() => _fatal = 'Camera could not start.');
    }
  }

  void _startDetection() {
    final c = _controller;
    if (c == null) return;
    try {
      c.startImageStream((frame) {
        if (_detecting || _busy) return;
        final now = DateTime.now();
        if (now.difference(_lastDetect).inMilliseconds < 320) return;
        _lastDetect = now;
        _detecting = true;
        final plane = frame.planes.first;
        final bytes = plane.bytes;
        final w = frame.width, h = frame.height, stride = plane.bytesPerRow;
        Future(() => ImageOps.detectEdgesSync(bytes, w, h, stride)).then((r) {
          _detecting = false;
          if (!mounted) return;
          setState(() => _edges = r);
        }).catchError((_) {
          _detecting = false;
        });
      });
    } catch (_) {}
  }

  String get _prompt {
    if (!widget.dualSided) {
      return _pages.isEmpty ? 'Position the document' : 'Ready for next scan';
    }
    if (_pages.isEmpty) return 'Front side';
    if (_pages.length == 1) return 'Flip the card · Back side';
    return 'Ready for next scan';
  }

  String get _hint => _edges != null
      ? 'Document detected — hold steady'
      : 'Fit the document inside the frame';

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null) return;
    try {
      final next = !_torch;
      await c.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _torch = next);
    } catch (_) {}
  }

  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || _busy || !c.value.isInitialized) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } catch (_) {}
      final shot = await c.takePicture();
      if (!mounted) return;

      final label = !widget.dualSided
          ? 'Page ${_pages.length + 1}'
          : _pages.isEmpty
              ? 'Front'
              : _pages.length == 1
                  ? 'Back'
                  : 'Page ${_pages.length + 1}';

      final cropped = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => PerspectiveCropScreen(
            sourcePath: shot.path,
            filter: _filter,
            forceHorizontal: _horizontal,
            title: 'Adjust $label',
          ),
        ),
      );
      if (cropped != null && mounted) {
        setState(() => _pages.add(ScanPage(path: cropped, label: label)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Capture failed. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _startDetection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              torch: _torch,
              horizontal: _horizontal,
              onClose: () => Navigator.pop(context, <ScanPage>[]),
              onTorch: _toggleTorch,
              onHorizontal: () => setState(() => _horizontal = !_horizontal),
            ),
            Expanded(
              child: FutureBuilder(
                future: _initFuture,
                builder: (context, snap) {
                  if (_fatal != null) {
                    return _Fatal(
                      message: _fatal!,
                      onRetry: () => setState(() => _initFuture = _boot()),
                    );
                  }
                  final c = _controller;
                  if (c == null || !c.value.isInitialized) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: c.value.previewSize?.height ?? 1080,
                          height: c.value.previewSize?.width ?? 1920,
                          child: CameraPreview(c),
                        ),
                      ),
                      CustomPaint(
                        painter: _GuidePainter(
                          edges: _edges,
                          horizontal: _horizontal,
                          color: _edges != null
                              ? scheme.primary
                              : Colors.white70,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 18,
                        child: Column(
                          children: [
                            _Pill(text: _prompt, strong: true),
                            const SizedBox(height: 8),
                            _Pill(text: _hint),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            _FilterBar(
              value: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
            if (_pages.isNotEmpty) _Strip(pages: _pages, onRemove: (i) {
              setState(() => _pages.removeAt(i));
            }),
            _BottomBar(
              busy: _busy,
              count: _pages.length,
              onShoot: _shoot,
              onDone: _pages.isEmpty
                  ? null
                  : () => Navigator.pop(context, List<ScanPage>.from(_pages)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.torch,
    required this.horizontal,
    required this.onClose,
    required this.onTorch,
    required this.onHorizontal,
  });

  final bool torch;
  final bool horizontal;
  final VoidCallback onClose;
  final VoidCallback onTorch;
  final VoidCallback onHorizontal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Horizontal card layout',
            onPressed: onHorizontal,
            icon: Icon(
              horizontal
                  ? Icons.stay_current_landscape_rounded
                  : Icons.stay_current_portrait_rounded,
              color: horizontal ? Theme.of(context).colorScheme.primary : Colors.white,
            ),
          ),
          IconButton(
            tooltip: 'Flash',
            onPressed: onTorch,
            icon: Icon(
              torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: torch ? Colors.amberAccent : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.strong = false});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Container(
          key: ValueKey(text),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: strong ? 0.62 : 0.42),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: strong ? 15 : 12.5,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  _GuidePainter({required this.edges, required this.horizontal, required this.color});
  final List<double>? edges;
  final bool horizontal;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect;
    if (edges != null) {
      rect = Rect.fromLTRB(
        edges![0] * size.width,
        edges![1] * size.height,
        edges![2] * size.width,
        edges![3] * size.height,
      );
    } else {
      final ratio = horizontal ? 1.586 : 0.707; // ID card vs A4
      final w = size.width * 0.86;
      final h = (w / ratio).clamp(120.0, size.height * 0.8);
      rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: w,
        height: h,
      );
    }

    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.42);
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(14)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, inner),
      scrim,
    );

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final len = rect.shortestSide * 0.16;
    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, o.translate(dx * len, 0), stroke);
      canvas.drawLine(o, o.translate(0, dy * len), stroke);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomRight, -1, -1);
    corner(rect.bottomLeft, 1, -1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      stroke..strokeWidth = 1.1,
    );
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) =>
      old.edges != edges || old.horizontal != horizontal || old.color != color;
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.value, required this.onChanged});
  final ScanFilter value;
  final ValueChanged<ScanFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: ScanFilter.values.map((f) {
          final selected = f == value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected,
              onSelected: (_) => onChanged(f),
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
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.pages, required this.onRemove});
  final List<ScanPage> pages;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: pages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(pages[i].path),
                width: 68,
                height: 86,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => onRemove(i),
                child: const CircleAvatar(
                  radius: 11,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.close, size: 13, color: Colors.white),
                ),
              ),
            ),
            Positioned(
              left: 4,
              bottom: 4,
              child: Text(
                pages[i].label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.busy,
    required this.count,
    required this.onShoot,
    required this.onDone,
  });

  final bool busy;
  final int count;
  final VoidCallback onShoot;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              count == 0 ? '' : '$count page${count == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: busy ? null : onShoot,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 72,
              width: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: busy ? Colors.white38 : Colors.white,
                border: Border.all(color: Colors.white54, width: 4),
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Icon(Icons.camera_alt_rounded, color: Colors.black87),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 76,
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onDone,
                child: Text(
                  'Done',
                  style: TextStyle(
                    color: onDone == null ? Colors.white30 : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Fatal extends StatelessWidget {
  const _Fatal({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                color: Colors.white70, size: 42),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
            TextButton(
              onPressed: () => openAppSettings(),
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}
