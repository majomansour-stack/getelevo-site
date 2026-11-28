import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Top-level background message handler — must be annotated with
/// @pragma('vm:entry-point') and be a top-level (non-class) function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialized when this handler is called on Android.
  // No additional initialization needed here.
}

/// Centralized push notification service.
///
/// Responsibilities:
///   1. Request OS permission on first launch after login.
///   2. Retrieve and persist the FCM token to Supabase `push_subscriptions`.
///   3. Handle foreground / background / killed-state notification taps with
///      deep-link data passed back to the caller via [onNotificationTap].
///   4. Send notifications to any ELEVO user by looking up their FCM token
///      from Supabase and calling the FCM HTTP v1 API.
///
/// Usage:
///   await PushNotificationService.initialize(onNotificationTap: (data) { ... });
class PushNotificationService {
  PushNotificationService._();

  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static final _db = Supabase.instance.client;
  static bool _started = false;

  // Android notification channel
  static const _androidChannel = AndroidNotificationChannel(
    'elevo_high_importance',
    'ELEVO Notifications',
    description: 'Rent, maintenance, messages, and lease alerts',
    importance: Importance.high,
  );

  // ── Initialization ──────────────────────────────────────────────────────────

  /// Call once after login. [onNotificationTap] receives the data payload map
  /// whenever a notification tap navigates the user to a specific screen.
  static Future<void> initialize({
    required void Function(Map<String, dynamic> data) onNotificationTap,
  }) async {
    // Web has no FCM token flow. Native login calls this once per session.
    if (kIsWeb || _started) return;
    _started = true;

    // Background handler must be registered before any other Firebase calls.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Request permissions
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    // Persist permission result
    final uid = _db.auth.currentUser?.id;
    if (uid != null) {
      try {
        await _db.from('notification_preferences').upsert({
          'user_id': uid,
          'push_enabled': granted,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id');
      } catch (_) {}
    }

    if (!granted) return;

    // Set up local notifications for foreground display
    await _setupLocalNotifications(onNotificationTap);

    // Store FCM token
    await _storeToken();

    // Refresh token on change
    _messaging.onTokenRefresh.listen((_) => _storeToken());

    // Foreground messages
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    });

    // App opened from background notification tap
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onNotificationTap(message.data);
    });

    // App opened from killed state
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      onNotificationTap(initial.data);
    }
  }

  // ── Token storage ───────────────────────────────────────────────────────────

  /// Drops this device's token. Called while the session is still valid,
  /// before sign-out, so the row delete is allowed by RLS.
  static Future<void> removeToken() async {
    if (kIsWeb) return;
    final uid = _db.auth.currentUser?.id;
    try {
      if (uid != null) {
        await _db.from('push_subscriptions').delete().eq('user_id', uid);
      }
      await _messaging.deleteToken();
    } catch (_) {}
    _started = false;
  }

  static Future<void> _storeToken() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await _db.from('push_subscriptions').upsert({
        'user_id': uid,
        'fcm_token': token,
        'device_platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (_) {}
  }

  // ── Local notification setup ────────────────────────────────────────────────

  static Future<void> _setupLocalNotifications(
    void Function(Map<String, dynamic>) onTap,
  ) async {
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            onTap(data);
          } catch (_) {}
        }
      },
    );

    // Create high-importance channel on Android
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  // ── Send notifications ──────────────────────────────────────────────────────

  /// Send a push notification to a specific ELEVO user by their Supabase user ID.
  /// Looks up the FCM token from `push_subscriptions`, then calls the FCM HTTP v1 API
  /// via a Supabase Edge Function to avoid exposing the server key on the client.
  static Future<void> sendToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, String> data = const {},
  }) async {
    try {
      await _db.functions.invoke(
        'send-push-notification',
        body: {
          'user_id': userId,
          'title': title,
          'body': body,
          'data': data,
        },
      );
    } catch (_) {
      // Push failures are non-fatal — the in-app notification or email covers it.
    }
  }

  // ── Typed event senders ─────────────────────────────────────────────────────

  static Future<void> notifyRentPaid({
    required String landlordId,
    required String tenantName,
    required String unitAddress,
    required String amount,
    required String monthLabel,
    required String unitId,
  }) =>
      sendToUser(
        userId: landlordId,
        title: 'Rent notice',
        body: '$tenantName says they paid $amount for $monthLabel',
        data: {'type': 'rent_paid', 'unit_id': unitId, 'unit_address': unitAddress},
      );

  static Future<void> notifyRentConfirmed({
    required String tenantId,
    required String unitAddress,
    required String amount,
  }) =>
      sendToUser(
        userId: tenantId,
        title: 'Payment Confirmed',
        body: 'Your rent payment of $amount for $unitAddress has been confirmed.',
        data: {'type': 'rent_paid'},
      );

  static Future<void> notifyMaintenanceUpdate({
    required String tenantId,
    required String newStatus,
    required String description,
    required String requestId,
  }) =>
      sendToUser(
        userId: tenantId,
        title: 'Maintenance Update',
        body: 'Your request "$description" is now $newStatus.',
        data: {'type': 'maintenance', 'request_id': requestId},
      );

  static Future<void> notifyNewMessage({
    required String recipientId,
    required String senderName,
    required String preview,
    required String unitId,
  }) =>
      sendToUser(
        userId: recipientId,
        title: 'New Message from $senderName',
        body: preview,
        data: {'type': 'message', 'unit_id': unitId},
      );

  static Future<void> notifyRentIncrease({
    required String tenantId,
    required String unitAddress,
    required String previousAmount,
    required String newAmount,
  }) =>
      sendToUser(
        userId: tenantId,
        title: 'Rent Update for $unitAddress',
        body: 'Your rent has been updated from $previousAmount to $newAmount effective on your next payment date.',
        data: {'type': 'rent_increase'},
      );

  static Future<void> notifyAnnouncement({
    required String tenantId,
    required String subject,
    required String preview,
  }) =>
      sendToUser(
        userId: tenantId,
        title: subject,
        body: preview.length > 60 ? '${preview.substring(0, 60)}\u2026' : preview,
        data: {'type': 'announcement'},
      );

  static Future<void> notifyLeaseExpiring({
    required String tenantId,
    required String unitAddress,
    required int daysRemaining,
  }) =>
      sendToUser(
        userId: tenantId,
        title: 'Lease Expiring Soon',
        body: 'Your lease for $unitAddress expires in $daysRemaining days.',
        data: {'type': 'lease_expiring'},
      );

  static Future<void> notifyVendorApproved({
    required String vendorId,
    required String vendorName,
  }) =>
      sendToUser(
        userId: vendorId,
        title: 'Application Approved',
        body: 'Congratulations $vendorName! Your vendor application has been approved.',
        data: {'type': 'vendor_approved'},
      );

  static Future<void> notifyVendorDeclined({
    required String vendorId,
    required String vendorName,
  }) =>
      sendToUser(
        userId: vendorId,
        title: 'Application Update',
        body: 'Hi $vendorName, your vendor application was not approved at this time.',
        data: {'type': 'vendor_declined'},
      );
}
