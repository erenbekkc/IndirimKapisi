import 'package:flutter/material.dart';

/// Ürün başlıklarında orphan (yalnız kalan) karakter sorununu çözer.
///
/// Son satırda yalnızca 1-2 karakter genişliği kadar içerik kalıyorsa
/// (örn. sadece "g" veya "ml") font büyüklüğünü [minFontSize]'a kadar
/// küçülterek o kısa parçanın üst satıra sığmasını sağlar.
class SmartTitleText extends StatelessWidget {
  final String text;
  final double fontSize;
  final double minFontSize;
  final FontWeight fontWeight;
  final Color? color;

  const SmartTitleText(
    this.text, {
    super.key,
    this.fontSize = 16,
    this.minFontSize = 12,
    this.fontWeight = FontWeight.bold,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      double fs = fontSize;

      while (fs >= minFontSize) {
        final style = TextStyle(fontSize: fs, fontWeight: fontWeight, color: color);
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: width);

        final lines = painter.computeLineMetrics();
        // Tek satır veya son satır ~2 karakterden fazlaysa kabul et
        if (lines.length <= 1 || lines.last.width > fs * 2.0) break;
        fs -= 0.5;
      }

      return Text(
        text,
        style: TextStyle(fontSize: fs, fontWeight: fontWeight, color: color),
      );
    });
  }
}
