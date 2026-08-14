import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tactile 3D flip between the front and back image of a document.
class FlipCardView extends StatefulWidget {
  const FlipCardView({
    super.key,
    required this.frontPath,
    required this.backPath,
    this.height = 230,
  });

  final String frontPath;
  final String backPath;
  final double height;

  @override
  State<FlipCardView> createState() => FlipCardViewState();
}

class FlipCardViewState extends State<FlipCardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  late final Animation<double> _anim =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);

  bool get isFlipped => _ctrl.value > 0.5;

  void flip() {
    if (_ctrl.isAnimating) return;
    isFlipped ? _ctrl.reverse() : _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: flip,
      child: SizedBox(
        height: widget.height,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            final angle = _anim.value * math.pi;
            final showBack = angle > math.pi / 2;
            final matrix = Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle);
            return Transform(
              alignment: Alignment.center,
              transform: matrix,
              child: showBack
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(math.pi),
                      child: _Face(path: widget.backPath, tag: 'Back'),
                    )
                  : _Face(path: widget.frontPath, tag: 'Front'),
            );
          },
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.path, required this.tag});
  final String path;
  final String tag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final exists = File(path).existsSync();
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (exists)
            Image.file(File(path), fit: BoxFit.contain)
          else
            const Center(child: Text('File missing')),
          Positioned(
            left: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                tag,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
