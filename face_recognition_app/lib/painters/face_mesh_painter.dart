import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Paints an animated 3D-scan mesh/contour overlay over detected faces.
class FaceMeshPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final bool isFrontCamera;
  final double animationValue;
  final List<String?> labels;

  FaceMeshPainter({
    required this.faces,
    required this.imageSize,
    required this.isFrontCamera,
    required this.animationValue,
    this.labels = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    final scanLinePaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.6 + 0.4 * sin(animationValue * pi * 2))
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final meshPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.35)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final boundingBoxPaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final cornerPaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < faces.length; i++) {
      final face = faces[i];
      final label = i < labels.length ? labels[i] : null;

      final rect = _scaleRect(face.boundingBox, scaleX, scaleY, size);
      _drawScanBox(canvas, rect, cornerPaint, boundingBoxPaint, scanLinePaint);
      _drawContourMesh(canvas, face, scaleX, scaleY, size, meshPaint);
      _drawLabel(canvas, rect, label, size);
    }
  }

  void _drawScanBox(
    Canvas canvas,
    Rect rect,
    Paint cornerPaint,
    Paint boxPaint,
    Paint scanPaint,
  ) {
    // Main bounding box
    canvas.drawRect(rect, boxPaint);

    // Corner accents
    const cornerLen = 20.0;
    final corners = [
      [rect.topLeft, Offset(rect.left + cornerLen, rect.top), Offset(rect.left, rect.top + cornerLen)],
      [rect.topRight, Offset(rect.right - cornerLen, rect.top), Offset(rect.right, rect.top + cornerLen)],
      [rect.bottomLeft, Offset(rect.left + cornerLen, rect.bottom), Offset(rect.left, rect.bottom - cornerLen)],
      [rect.bottomRight, Offset(rect.right - cornerLen, rect.bottom), Offset(rect.right, rect.bottom - cornerLen)],
    ];

    for (final c in corners) {
      canvas.drawLine(c[0], c[1], cornerPaint);
      canvas.drawLine(c[0], c[2], cornerPaint);
    }

    // Animated scan line
    final scanY = rect.top + rect.height * ((animationValue % 1.0));
    if (scanY >= rect.top && scanY <= rect.bottom) {
      canvas.drawLine(
        Offset(rect.left, scanY),
        Offset(rect.right, scanY),
        scanPaint,
      );
    }
  }

  void _drawContourMesh(
    Canvas canvas,
    Face face,
    double scaleX,
    double scaleY,
    Size canvasSize,
    Paint paint,
  ) {
    final contourTypes = [
      FaceContourType.face,
      FaceContourType.leftEye,
      FaceContourType.rightEye,
      FaceContourType.upperLipTop,
      FaceContourType.upperLipBottom,
      FaceContourType.lowerLipTop,
      FaceContourType.lowerLipBottom,
      FaceContourType.noseBridge,
      FaceContourType.noseBottom,
      FaceContourType.leftEyebrowTop,
      FaceContourType.rightEyebrowTop,
    ];

    for (final type in contourTypes) {
      final contour = face.contours[type];
      if (contour == null || contour.points.isEmpty) continue;

      final path = Path();
      final points = contour.points;

      for (int j = 0; j < points.length; j++) {
        final pt = _scalePoint(points[j], scaleX, scaleY, canvasSize);
        if (j == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }

      if (type == FaceContourType.face ||
          type == FaceContourType.leftEye ||
          type == FaceContourType.rightEye) {
        path.close();
      }

      canvas.drawPath(path, paint);

      // Draw dots at each landmark
      final dotPaint = Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.7)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.fill;

      for (final point in points) {
        final pt = _scalePoint(point, scaleX, scaleY, canvasSize);
        canvas.drawCircle(pt, 1.5, dotPaint);
      }
    }
  }

  void _drawLabel(Canvas canvas, Rect rect, String? label, Size canvasSize) {
    final text = label ?? 'Scanning...';
    final color = label != null ? Colors.cyanAccent : Colors.white54;

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = Rect.fromLTWH(
      rect.left,
      rect.top - 22,
      textPainter.width + 12,
      20,
    );

    canvas.drawRect(
      bgRect,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    textPainter.paint(canvas, Offset(rect.left + 6, rect.top - 21));
  }

  Rect _scaleRect(Rect rect, double scaleX, double scaleY, Size canvasSize) {
    double left = rect.left * scaleX;
    double top = rect.top * scaleY;
    double right = rect.right * scaleX;
    double bottom = rect.bottom * scaleY;

    if (isFrontCamera) {
      final mirroredLeft = canvasSize.width - right;
      final mirroredRight = canvasSize.width - left;
      left = mirroredLeft;
      right = mirroredRight;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  Offset _scalePoint(Point<int> point, double scaleX, double scaleY, Size canvasSize) {
    double x = point.x * scaleX;
    final double y = point.y * scaleY;
    if (isFrontCamera) {
      x = canvasSize.width - x;
    }
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(FaceMeshPainter oldDelegate) =>
      oldDelegate.faces != faces ||
      oldDelegate.animationValue != animationValue ||
      oldDelegate.labels != labels;
}
