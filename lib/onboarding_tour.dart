import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ──────────────────────────────────────────────────────────────────
// Bir tur adımını tanımlar.
//   key        : spotlight uygulanacak widget (null → karanlık zemin yeterli)
//   goToTab    : bu adımdan önce geçilecek sekme indeksi
//   spotPadding: spotlight etrafındaki boşluk
// ──────────────────────────────────────────────────────────────────
class TourStep {
  final GlobalKey? key;
  final String title;
  final String description;
  final int? goToTab;
  final double spotPadding;

  const TourStep({
    this.key,
    required this.title,
    required this.description,
    this.goToTab,
    this.spotPadding = 10,
  });
}

// ──────────────────────────────────────────────────────────────────
// İlk açılış kontrolü — SharedPreferences tabanlı.
// ──────────────────────────────────────────────────────────────────
class OnboardingTour {
  static const _prefKey = 'onboarding_v1_done';

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_prefKey) ?? false);
  }

  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }
}

// ──────────────────────────────────────────────────────────────────
// Tüm ekranı kaplayan overlay — spotlight + tooltip kartı.
// ──────────────────────────────────────────────────────────────────
class TourOverlay extends StatefulWidget {
  final List<TourStep> steps;
  final void Function(int tab) onChangeTab;
  final VoidCallback onDone;

  const TourOverlay({
    super.key,
    required this.steps,
    required this.onChangeTab,
    required this.onDone,
  });

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  bool _busy = false;
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
    _startStep();
  }

  Future<void> _startStep() async {
    _applyTab();
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() {});
      _anim.forward();
    }
  }

  void _applyTab() {
    final tab = widget.steps[_step].goToTab;
    if (tab != null) widget.onChangeTab(tab);
  }

  Future<void> _next() async {
    if (_busy) return;
    _busy = true;
    if (_step >= widget.steps.length - 1) {
      await _anim.reverse();
      await OnboardingTour.markDone();
      widget.onDone();
      return;
    }
    await _anim.reverse();
    if (!mounted) return;
    setState(() => _step++);
    _applyTab();
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {});
    _anim.forward();
    _busy = false;
  }

  Future<void> _skip() async {
    if (_busy) return;
    _busy = true;
    await _anim.reverse();
    await OnboardingTour.markDone();
    widget.onDone();
  }

  Rect? _getRect(GlobalKey? key) {
    if (key == null) return null;
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final pos = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(pos.dx, pos.dy, box.size.width, box.size.height);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_step];
    final spotRect = _getRect(step.key);
    final screen = MediaQuery.of(context).size;
    final isLast = _step == widget.steps.length - 1;

    // Tooltip'i spotlight'ın altına ya da üstüne yerleştir
    double tooltipTop;
    if (spotRect != null && spotRect.center.dy > screen.height * 0.55) {
      tooltipTop = (spotRect.top - 200).clamp(48.0, screen.height - 220);
    } else if (spotRect != null) {
      tooltipTop = (spotRect.bottom + 16).clamp(48.0, screen.height - 220);
    } else {
      tooltipTop = screen.height * 0.30;
    }

    return FadeTransition(
      opacity: _fade,
      child: Stack(
        children: [
          // Karanlık zemin + spotlight deliği
          CustomPaint(
            size: screen,
            painter: _SpotlightPainter(
              spotlight: spotRect?.inflate(step.spotPadding),
            ),
          ),

          // Tooltip kartı
          Positioned(
            top: tooltipTop,
            left: 20,
            right: 20,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            step.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ),
                        Text(
                          '${_step + 1} / ${widget.steps.length}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      step.description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: _skip,
                          style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          child: Text(
                            'Geç',
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 14),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _next,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 10),
                          ),
                          child: Text(
                            isLast ? 'Başla! 🎉' : 'Devam →',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// CustomPainter: tüm ekranı karartır, spotlight alanını şeffaf bırakır.
// ──────────────────────────────────────────────────────────────────
class _SpotlightPainter extends CustomPainter {
  final Rect? spotlight;

  const _SpotlightPainter({this.spotlight});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xBB000000),
    );
    if (spotlight != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(spotlight!, const Radius.circular(12)),
        Paint()..blendMode = BlendMode.clear,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.spotlight != spotlight;
}
