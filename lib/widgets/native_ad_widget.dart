import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_config_service.dart';
import '../services/native_ad_pool.dart';

class NativeAdWidget extends StatefulWidget {
  const NativeAdWidget({super.key});

  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  NativeAd? _ad;
  int _requestToken = -1; // -1 = anında servis edildi veya istek yok

  @override
  void initState() {
    super.initState();
    if (AdConfigService.instance.config.showNative) {
      _requestToken = NativeAdPool.instance.request(_onAdReceived);
    }
  }

  void _onAdReceived(NativeAd ad) {
    if (!mounted) {
      // Widget dispose olmuş — reklamı geri ver, boşa harcama
      NativeAdPool.instance.returnUnused(ad);
      return;
    }
    setState(() => _ad = ad);
  }

  @override
  void dispose() {
    // Henüz servis edilmemiş bekleyen istek varsa iptal et
    if (_requestToken >= 0) {
      NativeAdPool.instance.cancelRequest(_requestToken);
      _requestToken = -1;
    }
    // Reklam alınmış ama AdWidget'a girmiş olabilir — güvenli dispose
    _ad?.dispose();
    _ad = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdConfigService.instance.config.showNative) return const SizedBox.shrink();

    if (_ad == null) {
      return const _NativeAdPlaceholder();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 120, maxHeight: 180),
      child: AdWidget(ad: _ad!),
    );
  }
}

/// Reklam yüklenene kadar gösterilen sabit yükseklikli placeholder.
/// SizedBox.shrink() yerine bu kullanılır — kullanıcı alanın varlığını hisseder.
class _NativeAdPlaceholder extends StatelessWidget {
  const _NativeAdPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.grey.shade300,
          ),
        ),
      ),
    );
  }
}
