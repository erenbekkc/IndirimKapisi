import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesManager {
  static final ValueNotifier<Set<String>> notifier = ValueNotifier({});

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('favorite_campaign_ids') ?? [];
    notifier.value = Set.from(ids);
  }

  static Future<void> toggle(String campaignId) async {
    final current = Set<String>.from(notifier.value);
    if (current.contains(campaignId)) {
      current.remove(campaignId);
    } else {
      current.add(campaignId);
    }
    notifier.value = current;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorite_campaign_ids', current.toList());
  }
}
