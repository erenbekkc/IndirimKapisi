import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/announcement_service.dart';

class AnnouncementDialog extends StatelessWidget {
  final AnnouncementData data;

  const AnnouncementDialog({super.key, required this.data});

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
              decoration: BoxDecoration(color: cfg.bg, shape: BoxShape.circle),
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
            ...data.buttons.asMap().entries.map((entry) {
              final i = entry.key;
              final btn = entry.value;
              final isFirst = i == 0;
              final isLast = i == data.buttons.length - 1;

              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                child: SizedBox(
                  width: double.infinity,
                  child: isFirst
                      ? FilledButton(
                          onPressed: () => _handleTap(context, btn),
                          style: FilledButton.styleFrom(
                            backgroundColor: cfg.color,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(btn.text,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        )
                      : i == 1
                          ? OutlinedButton(
                              onPressed: () => _handleTap(context, btn),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(btn.text,
                                  style: const TextStyle(
                                      fontSize: 14, color: Colors.black87)),
                            )
                          : TextButton(
                              onPressed: () => _handleTap(context, btn),
                              child: Text(btn.text,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade500)),
                            ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context, AnnouncementButton btn) async {
    if (btn.action == 'url') {
      final url = btn.resolvedUrl;
      if (url != null && url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    if (context.mounted) Navigator.of(context).pop(btn);
  }
}
