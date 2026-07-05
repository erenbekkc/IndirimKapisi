import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'settings_screen.dart' show getOrCreateUserId;

class HakkindaScreen extends StatelessWidget {
  const HakkindaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0FDF4),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 16),

              // Logo / İkon
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF16A34A).withOpacity(0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/logo.jpeg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.storefront,
                      size: 48,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'İndirim Kapısı',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF16A34A),
                ),
              ),
              const SizedBox(height: 4),
              const SizedBox(
                width: double.infinity,
                child: Text(
                  'İndirim ve Fırsat Takip Asistanınız',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Instagram takip butonu
              GestureDetector(
                onTap: () async {
                  final uid = await getOrCreateUserId();
                  FirebaseFirestore.instance.collection('instagram_clicks').add({
                    'uid': uid,
                    'clickedAt': FieldValue.serverTimestamp(),
                  });
                  launchUrl(
                    Uri.parse('https://www.instagram.com/indirimkapisiapp?igsh=aHFpbWI2NHpzd3o0'),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFf09433), Color(0xFFe6683c), Color(0xFFdc2743), Color(0xFFcc2366), Color(0xFFbc1888)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFdc2743).withOpacity(0.30),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Bizi Instagram\'da Takip Edin',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '@indirimkapisiapp',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              _buildCard(
                icon: Icons.storefront_rounded,
                iconColor: const Color(0xFF16A34A),
                title: 'Uygulama Hakkında',
                content:
                    'İndirim Kapısı; zincir marketlerin indirim ve kampanya fırsatlarını tek çatı altında takip etmeye yarayan bağımsız, yapay zeka destekli bir platform uygulamasıdır.\n\n'
                    'Hangi üründe ne kadar indirim olduğunu, hangi marketin hangi kampanyayı sunduğunu artık tek tek takip etmenize gerek yok. Tüm fırsatlar sizin için düzenlenmiş hâlde, bir dokunuşta önünüzde.',
              ),

              const SizedBox(height: 14),

              _buildAiCard(),

              const SizedBox(height: 14),

              _buildCard(
                icon: Icons.savings_rounded,
                iconColor: const Color(0xFFD97706),
                title: 'Fırsat & Tasarruf Hesabı',
                content:
                    'Uygulama yalnızca kampanyaları listelemekle kalmaz; ne kadar tasarruf edebileceğinizi de gösterir.\n\n'
                    'Fiyat indirimleri, 1 alana 1 bedava kampanyaları ve 2. üründe indirim fırsatları için anlık tasarruf hesabı yaparak alışveriş kararlarınızı kolaylaştırır.',
              ),

              const SizedBox(height: 14),

              _buildCard(
                icon: Icons.notifications_active_rounded,
                iconColor: const Color(0xFF2563EB),
                title: 'Kişiselleştirilmiş Bildirimler',
                content:
                    'Takip ettiğiniz market ve kategorilerdeki kampanyalar hakkında düzenli olarak bildirim alırsınız.\n\n'
                    'Bildirim ayarlarından hangi marketleri ve kategorileri takip etmek istediğinizi belirleyebilirsiniz. Yalnızca sizinle ilgili fırsatlar, doğru zamanda karşınıza çıkar.',
              ),

              const SizedBox(height: 14),

              _buildCard(
                icon: Icons.info_outline_rounded,
                iconColor: const Color(0xFF6B7280),
                title: 'Önemli Bilgi',
                content:
                    'İndirim Kapısı yalnızca bilgi amaçlıdır. Kampanya bilgileri güncel tutulmaya çalışılmakla birlikte, kampanya koşulları ve geçerliliği için ilgili marketi veya market web sitesini takip etmenizi öneririz.\n\n'
                    'Fiyatlar ve kampanya detayları marketten markete ve zamana göre değişiklik gösterebilir.',
              ),

              const SizedBox(height: 14),

              // Yasal Uyarı
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.gavel_rounded, size: 18, color: Color(0xFFD97706)),
                        SizedBox(width: 8),
                        Text(
                          'YASAL UYARI',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'İndirim Kapısı uygulaması, bağımsız olarak geliştirilmiş bir kampanya takip platformudur. Herhangi bir market zinciriyle resmi ortaklık, sponsorluk veya iş birliği bulunmamakta; bu markaları temsil etmemektedir.\n\n'
                      'Kampanya ve indirim bilgileri kamuya açık kaynaklardan derlenmekte olup doğruluk garantisi verilmemektedir. Güncel fiyat ve kampanya bilgileri için ilgili marketin resmi kanallarını ziyaret ediniz.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF92400E),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Alt ayak — versiyon
              Text(
                'İndirim Kapısı • v1.0',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '© 2025 İndirim Kapısı. Tüm hakları saklıdır.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('assets/agent_gri.jpeg', width: 36, height: 36, fit: BoxFit.cover),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Yapay Zeka Desteği',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'YENİ',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF16A34A)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'İndirim Kapısı, yerleşik yapay zeka asistanıyla fırsat takibini bir üst seviyeye taşıyor.\n\n'
            'Asistana doğal dilde sorular sorabilir, anlık kampanya önerileri alabilirsiniz:',
            style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700, height: 1.6),
          ),
          const SizedBox(height: 10),
          ...[
            '💬  "Bu hafta deterjan kampanyası var mı?"',
            '💬  "500 TL bütçem var, ne alayım?"',
            '💬  "En iyi fırsatlar hangi marketlerde?"',
            '💬  "Bugün biten fırsatlar neler?"',
          ].map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(s, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.5)),
          )),
          const SizedBox(height: 8),
          Text(
            'Beğendiğin kampanyaları tek tıkla favorilerine ekleyebilir, yapay zeka yardımıyla en avantajlı fırsatları keşfedebilirsin.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              fontSize: 13.5,
              color: Colors.grey.shade700,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
