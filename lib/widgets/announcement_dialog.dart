import 'package:flutter/material.dart';
import '../services/announcement_service.dart';

class AnnouncementDialog extends StatelessWidget {
  final AnnouncementData data;
  final VoidCallback onCtaTap;

  const AnnouncementDialog({
    super.key,
    required this.data,
    required this.onCtaTap,
  });

  static const _typeConfig = {
    'update': (
      icon: Icons.system_update_rounded,
      color: Color(0xFF16A34A),
      bg: Color(0xFFDCFCE7),
    ),
    'promo': (
      icon: Icons.local_offer_rounded,
      color: Color(0xFFEA580C),
      bg: Color(0xFFFFF7ED),
    ),
    'info': (
      icon: Icons.info_rounded,
      color: Color(0xFF2563EB),
      bg: Color(0xFFEFF6FF),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final cfg = _typeConfig[data.type] ?? _typeConfig['info']!;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: cfg.bg,
                shape: BoxShape.circle,
              ),
              child: Icon(cfg.icon, color: cfg.color, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              data.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              data.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onCtaTap,
                style: FilledButton.styleFrom(
                  backgroundColor: cfg.color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  data.ctaText,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
