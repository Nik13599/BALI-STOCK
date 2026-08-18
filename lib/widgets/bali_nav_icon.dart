import 'dart:math' as math;

import 'package:flutter/material.dart';

enum BaliNavIconKind {
  home,
  stock,
  stocktake,
  purchases,
  delivery,
  settings,
  scan,
  history,
  spot,
  prices,
  sync,
}

class BaliNavIcon extends StatelessWidget {
  const BaliNavIcon({
    super.key,
    required this.kind,
    this.active = false,
    this.size = 24,
  });

  final BaliNavIconKind kind;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF39FF6A) : Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _BaliNavPainter(kind: kind, color: color, active: active)),
    );
  }
}

class _BaliNavPainter extends CustomPainter {
  const _BaliNavPainter({required this.kind, required this.color, required this.active});

  final BaliNavIconKind kind;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final scale = s / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (active ? 2.15 : 1.85) * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();
    canvas.scale(scale, scale);

    switch (kind) {
      case BaliNavIconKind.home:
        _home(canvas, paint);
      case BaliNavIconKind.stock:
        _stock(canvas, paint);
      case BaliNavIconKind.stocktake:
        _stocktake(canvas, paint);
      case BaliNavIconKind.purchases:
        _purchases(canvas, paint);
      case BaliNavIconKind.delivery:
        _delivery(canvas, paint);
      case BaliNavIconKind.settings:
        _settings(canvas, paint);
      case BaliNavIconKind.scan:
        _scan(canvas, paint);
      case BaliNavIconKind.history:
        _history(canvas, paint);
      case BaliNavIconKind.spot:
        _spot(canvas, paint);
      case BaliNavIconKind.prices:
        _prices(canvas, paint);
      case BaliNavIconKind.sync:
        _sync(canvas, paint);
    }

    canvas.restore();
  }

  void _home(Canvas c, Paint p) {
    final path = Path()
      ..moveTo(3, 11)
      ..lineTo(12, 3.5)
      ..lineTo(21, 11)
      ..moveTo(5.5, 9.5)
      ..lineTo(5.5, 20)
      ..lineTo(18.5, 20)
      ..lineTo(18.5, 9.5)
      ..moveTo(9.3, 20)
      ..lineTo(9.3, 14)
      ..lineTo(14.7, 14)
      ..lineTo(14.7, 20);
    c.drawPath(path, p);
  }

  void _stock(Canvas c, Paint p) {
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(3.5, 4, 17, 16), const Radius.circular(2)), p);
    c.drawLine(const Offset(4.5, 10), const Offset(19.5, 10), p);
    c.drawLine(const Offset(4.5, 15), const Offset(19.5, 15), p);
    c.drawLine(const Offset(9, 5), const Offset(9, 9), p);
    c.drawLine(const Offset(14.8, 11), const Offset(14.8, 14), p);
  }

  void _stocktake(Canvas c, Paint p) {
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(5, 4.5, 14, 16), const Radius.circular(2)), p);
    c.drawLine(const Offset(9, 3.5), const Offset(15, 3.5), p);
    c.drawLine(const Offset(9, 7.5), const Offset(15, 7.5), p);
    c.drawPath(Path()..moveTo(8, 13)..lineTo(10.5, 15.5)..lineTo(16.5, 10), p);
  }

  void _purchases(Canvas c, Paint p) {
    c.drawPath(Path()..moveTo(3, 5)..lineTo(5.5, 5)..lineTo(7.2, 15.2)..lineTo(17.5, 15.2)..lineTo(20, 8)..lineTo(6, 8), p);
    c.drawCircle(const Offset(9, 19), 1.2, p);
    c.drawCircle(const Offset(17, 19), 1.2, p);
  }

  void _delivery(Canvas c, Paint p) {
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(4, 9, 16, 11), const Radius.circular(2)), p);
    c.drawLine(const Offset(12, 3), const Offset(12, 14), p);
    c.drawPath(Path()..moveTo(8.5, 10.5)..lineTo(12, 14)..lineTo(15.5, 10.5), p);
    c.drawLine(const Offset(4.5, 9), const Offset(8, 6.5), p);
    c.drawLine(const Offset(19.5, 9), const Offset(16, 6.5), p);
  }

  void _settings(Canvas c, Paint p) {
    c.drawCircle(const Offset(12, 12), 3.2, p);
    c.drawCircle(const Offset(12, 12), 7.2, p);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final inner = Offset(12 + math.cos(a) * 7.4, 12 + math.sin(a) * 7.4);
      final outer = Offset(12 + math.cos(a) * 9.5, 12 + math.sin(a) * 9.5);
      c.drawLine(inner, outer, p);
    }
  }

  void _scan(Canvas c, Paint p) {
    final path = Path()
      ..moveTo(8, 4)..lineTo(4, 4)..lineTo(4, 8)
      ..moveTo(16, 4)..lineTo(20, 4)..lineTo(20, 8)
      ..moveTo(4, 16)..lineTo(4, 20)..lineTo(8, 20)
      ..moveTo(20, 16)..lineTo(20, 20)..lineTo(16, 20)
      ..moveTo(8, 9)..lineTo(8, 15)
      ..moveTo(11, 8)..lineTo(11, 16)
      ..moveTo(14, 9)..lineTo(14, 15)
      ..moveTo(17, 8)..lineTo(17, 16);
    c.drawPath(path, p);
  }

  void _history(Canvas c, Paint p) {
    c.drawArc(const Rect.fromLTWH(4, 4, 16, 16), -.55, math.pi * 1.65, false, p);
    c.drawPath(Path()..moveTo(4, 8)..lineTo(4, 4)..lineTo(8, 4), p);
    c.drawLine(const Offset(12, 7.5), const Offset(12, 12.2), p);
    c.drawLine(const Offset(12, 12.2), const Offset(15.5, 14), p);
  }

  void _spot(Canvas c, Paint p) {
    c.drawCircle(const Offset(12, 12), 8, p);
    c.drawCircle(const Offset(12, 12), 3.5, p);
    c.drawLine(const Offset(12, 2), const Offset(12, 6), p);
    c.drawLine(const Offset(12, 18), const Offset(12, 22), p);
    c.drawLine(const Offset(2, 12), const Offset(6, 12), p);
    c.drawLine(const Offset(18, 12), const Offset(22, 12), p);
  }

  void _prices(Canvas c, Paint p) {
    c.drawPath(Path()..moveTo(4, 7)..lineTo(11, 4)..lineTo(20, 13)..lineTo(13, 20)..lineTo(4, 11)..close(), p);
    c.drawCircle(const Offset(8.5, 8.5), 1.2, p);
    c.drawLine(const Offset(11.5, 9.5), const Offset(16, 14), p);
  }

  void _sync(Canvas c, Paint p) {
    c.drawArc(const Rect.fromLTWH(4, 4, 16, 16), -2.6, 2.25, false, p);
    c.drawPath(Path()..moveTo(18, 4.5)..lineTo(20, 8)..lineTo(16, 8), p);
    c.drawArc(const Rect.fromLTWH(4, 4, 16, 16), .55, 2.25, false, p);
    c.drawPath(Path()..moveTo(6, 19.5)..lineTo(4, 16)..lineTo(8, 16), p);
  }

  @override
  bool shouldRepaint(covariant _BaliNavPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color || oldDelegate.active != active;
}
