import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'favourite_logger.dart';

class FavoritesManager {
  static final ValueNotifier<Set<String>> notifier = ValueNotifier({});

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('favorite_campaign_ids') ?? [];
    notifier.value = Set.from(ids);
  }

  static Future<void> toggle(
    String campaignId, {
    Map<String, dynamic>? campaignData,
  }) async {
    final current = Set<String>.from(notifier.value);
    final isAdding = !current.contains(campaignId);

    if (isAdding) {
      current.add(campaignId);
      if (campaignData != null) {
        unawaited(FavouriteLogger.logAdded(
          campaignId: campaignId,
          data: campaignData,
        ));
      }
    } else {
      current.remove(campaignId);
      unawaited(FavouriteLogger.logRemoved(campaignId));
    }

    notifier.value = current;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorite_campaign_ids', current.toList());
  }
}
