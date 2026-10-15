import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:kolibri/kolibri.dart' show initKolibri;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:komet/l10n/app_localizations.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backend/api.dart';
import 'core/cache/info_cache.dart';
import 'core/utils/logger.dart';
import 'core/cache/self_presence.dart';
import 'core/storage/app_instance.dart';
import 'core/storage/draft_store.dart';
import 'core/storage/archived_chats_store.dart';
import 'core/storage/chat_encryption_store.dart';
import 'core/config/app_accent.dart';
import 'core/config/app_amoled.dart';
import 'core/config/app_show_extra_info.dart';
import 'core/config/app_spectrum_background.dart';
import 'core/config/app_bubble_behavior.dart';
import 'core/config/komet_settings.dart';
import 'core/config/call_no_mute.dart';
import 'core/config/debug_test.dart';
import 'core/config/app_bubble_shape.dart';
import 'core/config/app_cache_extent.dart';
import 'core/config/app_fonts.dart';
import 'core/config/custom_font_service.dart';
import 'core/config/app_message_actions_style.dart';
import 'core/config/app_microphone.dart';
import 'core/config/app_swipe_back_desktop.dart';
import 'core/config/app_pranks.dart';
import 'core/config/app_stories.dart';
import 'core/config/app_commands.dart';
import 'core/config/app_phonebook_names.dart';
import 'core/contacts/device_contacts_service.dart';
import 'core/config/app_link_preview.dart';
import 'core/config/app_media_cache.dart';
import 'core/config/app_video_note_quality.dart';
import 'core/config/app_pill_gradient.dart';
import 'core/config/app_visual_style.dart';
import 'core/config/app_chat_chrome.dart';
import 'core/config/app_composer_background.dart';
import 'core/config/app_composer_style.dart';
import 'core/config/app_nav_pill_style.dart';
import 'core/config/app_dock_bar.dart';
import 'core/config/app_wallpaper_tint.dart';
import 'core/storage/chat_wallpaper_store.dart';
import 'core/utils/wallpaper_seed.dart';
import 'core/config/app_theme_mode.dart';
import 'core/config/app_theme_schedule.dart';
import 'core/config/app_digital_id_mode.dart';
import 'backend/modules/account.dart';
import 'backend/modules/chats.dart';
import 'backend/modules/comments.dart';
import 'backend/modules/contacts.dart';
import 'backend/modules/file_uploader.dart';
import 'backend/modules/folders.dart';
import 'backend/modules/messages.dart';
import 'backend/modules/outbox.dart';
import 'backend/modules/polls.dart';
import 'backend/modules/stickers.dart';
import 'backend/modules/animoji.dart';
import 'backend/modules/stories.dart';
import 'backend/modules/self_check.dart';
import 'backend/modules/shared_content.dart';
import 'backend/modules/webapp.dart';
import 'backend/modules/digital_id.dart';
import 'core/calls/call_bridge.dart';
import 'core/calls/call_controller.dart';
import 'core/links/deep_link_service.dart';
import 'frontend/screens/calls/call_screen.dart';
import 'core/push/fkm_controller.dart';
import 'core/push/notification_bridge.dart';
import 'core/share/share_intent_bridge.dart';
import 'core/push/push_service.dart';
import 'core/storage/app_database.dart';
import 'core/transport/tls_config.dart';
import 'core/transport/traffic_monitor.dart';
import 'core/transport/vpn_bypass.dart';
import 'core/storage/token_storage.dart';
import 'core/utils/haptics.dart';
import 'core/utils/debug_session_log.dart';
import 'core/protocol/packet.dart';
import 'frontend/debug/fps_overlay_layer.dart';
import 'frontend/screens/auth/login_screen.dart';
import 'frontend/widgets/adaptive_shell.dart';
import 'frontend/widgets/custom_notification.dart';
import 'frontend/widgets/liquid_glass.dart';
import 'frontend/widgets/small_spinner.dart';
import 'frontend/widgets/theme_reveal.dart';
import 'frontend/widgets/floating_call_badge.dart';
import 'frontend/widgets/floating_video_note.dart';

final api = Api();
final accountModule = AccountModule(api);
final messagesModule = MessagesModule(api);
final commentsModule = CommentsModule(api);
final sharedContentModule = SharedContentModule(api);
final pollsModule = PollsModule(api);
final stickersModule = StickersModule(api);
final animojiModule = AnimojiModule(api);
final webAppModule = WebAppModule(api);
final digitalIdModule = DigitalIdModule(webAppModule);
final fileUploader = FileUploader(api: api, messages: messagesModule);
final storiesModule = StoriesModule(api);
final bannersModule = accountModule.banners;
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

bool isOnemeFlavor = false;

const ProgressIndicatorThemeData _expressiveProgressTheme =
    ProgressIndicatorThemeData(year2023: false);

const PageTransitionsTheme _appPageTransitions = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.windows: ZoomPageTransitionsBuilder(),
    TargetPlatform.linux: ZoomPageTransitionsBuilder(),
  },
);

Future<Locale> _loadInitialLocale() async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString('app_locale');
  if (code != null && (code == 'en' || code == 'ru')) {
    return Locale(code);
  }
  final platform = WidgetsBinding.instance.platformDispatcher.locale;
  if (platform.languageCode == 'en' || platform.languageCode == 'ru') {
    return Locale(platform.languageCode);
  }
  return const Locale('ru');
}

void _installLogCapture() {
  final previousDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      final t = DateTime.now();
      final stamp =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';
      DebugSessionLog.instance.recordLogLine('  |$stamp P $message');
    }
    previousDebugPrint(message, wrapWidth: wrapWidth);
  };

  final previousFlutterOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    DebugSessionLog.instance.recordLogLine(
      '  |         FlutterError: ${details.exceptionAsString()}',
    );
    if (details.stack != null) {
      DebugSessionLog.instance.recordLogLine(details.stack.toString());
    }
    if (previousFlutterOnError != null) {
      previousFlutterOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  final previousPlatformOnError = ui.PlatformDispatcher.instance.onError;
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    DebugSessionLog.instance.recordLogLine('  |         Uncaught: $error');
    DebugSessionLog.instance.recordLogLine(stack.toString());
    if (previousPlatformOnError != null) {
      return previousPlatformOnError(error, stack);
    }
    return false;
  };
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await initKolibri();
  DebugTest.parse(args);
  CallNoMute.parse(args);
  _installLogCapture();
  VideoPlayerMediaKit.ensureInitialized(
    windows: true,
    linux: true,
    macOS: true,
  );
  if (AppInstance.isNamed) {
    SharedPreferences.setPrefix('flutter.${AppInstance.id}.');
  }
  await TlsConfig.applyMincifryTrust();
  await AppDatabase.init();
  final activeAccountId = await TokenStorage.getActiveAccountId();
  if (activeAccountId != null) {
    await ContactsModule.primeCacheFromDb(activeAccountId);
  }
  attachInfoCacheApi(api);
  chats.attachGlobalPushHandlers(api);
  unawaited(FkmController.instance.init(api));
  FoldersModule.attachGlobalPushHandlers(api);
  TranscriptionPushHandler.attach(api);
  commentsModule.attachPushHandlers(api);
  storiesModule.attach();
  unawaited(storiesModule.loadCache());
  unawaited(DeepLinkService.instance.init());

  final packageInfoFuture = PackageInfo.fromPlatform();
  final localeFuture = _loadInitialLocale();
  final hapticsFuture = Haptics.load();
  final prefsFuture = SharedPreferences.getInstance();
  final accentFuture = AppAccent.load();
  final bubbleShapeFuture = AppBubbleShape.load();
  final bubbleBehaviorFuture = AppBubbleBehavior.load();
  final cacheExtentFuture = AppCacheExtent.load();
  final themeModeFuture = AppThemeModeConfig.load();
  final amoledFuture = AppAmoled.load();
  final pillGradientFuture = AppPillGradient.load();
  final visualStyleFuture = AppVisualStyle.load();
  final liquidGlassFuture = LiquidGlass.load();
  final chatChromeFuture = AppChatChrome.load();
  final composerStyleFuture = AppComposerStyle.load();
  final composerBackgroundFuture = AppComposerBackground.load();
  final navPillStyleFuture = AppNavPillStyle.load();
  final dockBarFuture = AppDockBar.load();
  final wallpaperTintFuture = AppWallpaperTint.load();
  final themeScheduleFuture = AppThemeSchedule.load();
  final messageActionsFuture = AppMessageActionsStyle.load();
  final swipeBackFuture = AppSwipeBackDesktop.load();
  final microphoneFuture = AppMicrophone.load();
  final pranksFuture = AppPranks.load();
  final storiesFuture = AppStories.load();
  final commandsFuture = AppCommands.load();
  final phonebookNamesFuture = AppPhonebookNames.load();
  final linkPreviewFuture = AppLinkPreview.load();
  final cacheLimitFuture = AppMediaCacheLimit.load();
  final videoNoteResolutionFuture = AppVideoNoteResolution.load();
  final videoNoteFpsFuture = AppVideoNoteFps.load();
  final videoNoteRearCameraFuture = AppVideoNoteRearCamera.load();
  final digitalIdNativeFuture = AppDigitalIdNative.load();
  final showExtraInfoFuture = AppShowExtraInfo.load();
  final spectrumBackgroundFuture = AppSpectrumBackground.load();
  final trafficCaptureFuture = TrafficMonitor.instance.load();
  final debugLogFuture = DebugSessionLog.instance.init();

  final packageInfo = await packageInfoFuture;
  isOnemeFlavor = packageInfo.packageName == 'ru.oneme.app';

  final initialLocale = await localeFuture;

  await hapticsFuture;

  final prefs = await prefsFuture;
  await FileHistoryCache.load(prefs);
  await DraftStore.instance.load();
  await ArchivedChatsStore.instance.load();
  await ChatEncryptionStore.instance.load();
  await KometSettings.load();
  if (KometSettings.ghostMode.value) SelfPresence.markOffline();
  await ContactCache.load();
  final initialFpsOverlay = prefs.getBool('dev_fps_overlay') ?? false;
  final initialVpnBypass = prefs.getBool(VpnBypassService.prefKey) ?? false;
  final initialTlsInsecure = prefs.getBool(TlsConfig.prefKey) ?? false;
  final initialFontId =
      prefs.getString(AppFonts.prefKey) ?? AppFonts.fallback.id;
  final initialFontScale = AppFonts.clampScale(
    prefs.getDouble(AppFonts.scalePrefKey) ?? AppFonts.defaultScale,
  );
  if (AppFonts.resolve(initialFontId).isCustom) {
    await CustomFontService.preloadCached();
  } else {
    unawaited(CustomFontService.preloadCached());
  }
  final initialAccentSeed = await accentFuture;
  await Future.wait<dynamic>([
    bubbleShapeFuture,
    bubbleBehaviorFuture,
    cacheExtentFuture,
    themeModeFuture,
    amoledFuture,
    pillGradientFuture,
    visualStyleFuture,
    liquidGlassFuture,
    chatChromeFuture,
    composerStyleFuture,
    composerBackgroundFuture,
    navPillStyleFuture,
    dockBarFuture,
    wallpaperTintFuture,
    themeScheduleFuture,
    messageActionsFuture,
    swipeBackFuture,
    microphoneFuture,
    pranksFuture,
    storiesFuture,
    commandsFuture,
    phonebookNamesFuture,
    linkPreviewFuture,
    cacheLimitFuture,
    videoNoteResolutionFuture,
    videoNoteFpsFuture,
    videoNoteRearCameraFuture,
    digitalIdNativeFuture,
    showExtraInfoFuture,
    spectrumBackgroundFuture,
  ]);
  await DeviceContactsService.loadFromStartup();
  await trafficCaptureFuture;
  await debugLogFuture;
  runApp(
    KometApp(
      initialLocale: initialLocale,
      initialFpsOverlay: initialFpsOverlay,
      initialVpnBypass: initialVpnBypass,
      initialTlsInsecure: initialTlsInsecure,
      initialFontId: initialFontId,
      initialFontScale: initialFontScale,
      initialAccentSeed: initialAccentSeed,
    ),
  );
}

class KometApp extends StatefulWidget {
  const KometApp({
    super.key,
    required this.initialLocale,
    this.initialFpsOverlay = false,
    this.initialVpnBypass = false,
    this.initialTlsInsecure = false,
    required this.initialFontId,
    required this.initialFontScale,
    this.initialAccentSeed,
  });

  final Locale initialLocale;
  final bool initialFpsOverlay;
  final bool initialVpnBypass;
  final bool initialTlsInsecure;
  final String initialFontId;
  final double initialFontScale;
  final Color? initialAccentSeed;
  static final navigatorKey = GlobalKey<NavigatorState>();

  static KometAppState? stateOf(BuildContext context) {
    return context.findAncestorStateOfType<KometAppState>();
  }

  @override
  State<KometApp> createState() => KometAppState();
}

class KometAppState extends State<KometApp>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _fallbackSeed = Color(0xFFC1C4FF);

  final GlobalKey _captureBoundaryKey = GlobalKey();
  OverlayEntry? _revealEntry;
  AnimationController? _revealController;
  ui.Image? _revealImage;

  late Locale _locale;
  late String _fontId;
  bool _isLoggingOut = false;
  bool _shellReady = false;
  bool _incomingRouteActive = false;
  IncomingCall? _pendingIncoming;
  late final ValueNotifier<Color?> accentSeed = ValueNotifier(
    widget.initialAccentSeed,
  );
  final ValueNotifier<Color?> wallpaperSeed = ValueNotifier(null);
  StreamSubscription<SessionExpiredException>? _sessionExpiredSub;
  StreamSubscription<LoginStatus>? _loginStatusSub;
  StreamSubscription<VpnBypassResult>? _vpnBypassSub;
  StreamSubscription<IncomingCall>? _callIncomingSub;
  StreamSubscription<String>? _serverErrorSub;
  StreamSubscription<AccountNotice>? _accountNoticeSub;
  Timer? _scheduleTimer;
  String? _lastVpnNotice;
  DateTime _lastVpnNoticeAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastServerError;
  DateTime _lastServerErrorAt = DateTime.fromMillisecondsSinceEpoch(0);
  late final ValueNotifier<bool> fpsOverlayEnabled = ValueNotifier(
    widget.initialFpsOverlay,
  );
  late final ValueNotifier<bool> vpnBypassEnabled = ValueNotifier(
    widget.initialVpnBypass,
  );
  late final ValueNotifier<bool> tlsInsecureEnabled = ValueNotifier(
    widget.initialTlsInsecure,
  );
  late final ValueNotifier<double> fontScale = ValueNotifier(
    widget.initialFontScale,
  );
  final _profileUpdateController = StreamController<void>.broadcast();
  Stream<void> get profileUpdateStream => _profileUpdateController.stream;

  @override
  void initState() {
    super.initState();
    _locale = widget.initialLocale;
    _fontId = widget.initialFontId;

    WidgetsBinding.instance.addObserver(this);
    AppThemeModeConfig.current.addListener(_onThemeModeChanged);
    AppAmoled.current.addListener(_onAmoledChanged);
    AppThemeSchedule.current.addListener(_onScheduleChanged);
    AppWallpaperTint.current.addListener(_onWallpaperTintChanged);
    ChatWallpaperStore.instance.revision.addListener(_onWallpaperTintChanged);
    _lastAppliedThemeMode = _effectiveThemeMode;
    _rescheduleSwitch();
    unawaited(_refreshWallpaperSeed());

    api.setReconnectCallback(() async {
      try {
        final accountId = await TokenStorage.getActiveAccountId();
        if (accountId != null) {
          final token = await TokenStorage.readToken(accountId);
          if (token != null) {
            await accountModule.login(accountId: accountId, token: token);
          }
        }
      } catch (e) {
        logger.w('reconnect login failed: $e');
      }
    });

    _loginStatusSub = accountModule.loginStatusStream.listen((status) async {
      if (status == LoginStatus.success) {
        DeepLinkService.instance.markReady();
        NotificationBridge.instance.markReady();
        ShareIntentBridge.instance.markReady();
        unawaited(_refreshWallpaperSeed());
        CallController.instance.init(api);
        OutboxService.instance.init(api, messagesModule);
        SelfCheckService.instance.init(api);
        SelfCheckService.instance.checkNow();
        if (isOnemeFlavor) {
          await PushService.instance.init(api: api, account: accountModule);
          await PushService.instance.onLoginSuccess();
          await _ensureFullScreenIntentPermission();
        }
      }
    });

    _callIncomingSub = CallController.instance.incomingCalls.listen(
      _onIncomingCall,
    );
    CallController.instance.appResumed = true;
    CallBridge.instance.init();
    NotificationBridge.instance.init();
    ShareIntentBridge.instance.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CallBridge.instance.checkInitialCall();
      unawaited(NotificationBridge.instance.checkInitialChat());
      unawaited(ShareIntentBridge.instance.checkInitialShare());
    });

    _sessionExpiredSub = api.sessionExpiredStream.listen((
      SessionExpiredException e,
    ) async {
      if (_isLoggingOut) return;
      _isLoggingOut = true;

      await PushService.instance.unregister();

      final accountId = await TokenStorage.getActiveAccountId();
      if (accountId != null) {
        await accountModule.removeAccount(accountId);
      }

      final navState = KometApp.navigatorKey.currentState;
      if (navState != null) {
        final overlay = navState.overlay;
        if (overlay != null) {
          showCustomNotificationOnOverlay(overlay, e.message);
        }

        await navState.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
      _isLoggingOut = false;
    });

    _vpnBypassSub = VpnBypassService.instance.events.listen((r) {
      final msg = r.bound
          ? 'Обход VPN включён — прямое подключение через '
                '${r.boundInterface ?? r.transport ?? 'сеть без VPN'}'
          : 'Обход VPN не удался, подключение через туннель'
                '${r.reason != null ? ' (${r.reason})' : ''}';
      final now = DateTime.now();
      if (msg == _lastVpnNotice &&
          now.difference(_lastVpnNoticeAt) < const Duration(seconds: 4)) {
        return;
      }
      _lastVpnNotice = msg;
      _lastVpnNoticeAt = now;
      final nav = KometApp.navigatorKey.currentState;
      final overlay = nav?.overlay;
      if (overlay != null) {
        showCustomNotificationOnOverlay(overlay, msg);
      }
    });

    _serverErrorSub = api.serverErrorStream.listen((msg) {
      final now = DateTime.now();
      if (msg == _lastServerError &&
          now.difference(_lastServerErrorAt) < const Duration(seconds: 3)) {
        return;
      }
      _lastServerError = msg;
      _lastServerErrorAt = now;
      final nav = KometApp.navigatorKey.currentState;
      final overlay = nav?.overlay;
      if (overlay != null) {
        showCustomNotificationOnOverlay(overlay, msg);
      }
    });

    _accountNoticeSub = accountModule.notices.listen((n) {
      final nav = KometApp.navigatorKey.currentState;
      final overlay = nav?.overlay;
      if (overlay != null) {
        showCustomNotificationOnOverlay(overlay, n.message);
      }
    });

    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      await accountModule.bootstrap();
    } catch (e) {
      logger.w('bootstrap failed: $e');
    }
    if (mounted) setState(() => _shellReady = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppThemeModeConfig.current.removeListener(_onThemeModeChanged);
    AppAmoled.current.removeListener(_onAmoledChanged);
    AppThemeSchedule.current.removeListener(_onScheduleChanged);
    AppWallpaperTint.current.removeListener(_onWallpaperTintChanged);
    ChatWallpaperStore.instance.revision.removeListener(_onWallpaperTintChanged);
    _scheduleTimer?.cancel();
    _sessionExpiredSub?.cancel();
    _loginStatusSub?.cancel();
    _vpnBypassSub?.cancel();
    _callIncomingSub?.cancel();
    _serverErrorSub?.cancel();
    _accountNoticeSub?.cancel();
    _revealController?.dispose();
    _revealImage?.dispose();
    _revealEntry?.remove();
    accentSeed.dispose();
    wallpaperSeed.dispose();
    fpsOverlayEnabled.dispose();
    vpnBypassEnabled.dispose();
    tlsInsecureEnabled.dispose();
    fontScale.dispose();
    _profileUpdateController.close();
    super.dispose();
  }

  ThemeMode? _lastAppliedThemeMode;

  ThemeMode get _effectiveThemeMode {
    final scheduled = AppThemeSchedule.current.value;
    if (scheduled != null) return scheduled;
    return AppThemeModeConfig.current.value;
  }

  void _onThemeModeChanged() {
    final next = _effectiveThemeMode;
    if (next == _lastAppliedThemeMode) return;
    _lastAppliedThemeMode = next;
    setState(() {});
  }

  void _onAmoledChanged() => setState(() {});

  void _onScheduleChanged() {
    _rescheduleSwitch();
    _onThemeModeChanged();
  }

  void _rescheduleSwitch() {
    _scheduleTimer?.cancel();
    final next = AppThemeSchedule.nextSwitch;
    if (next == null) return;
    final delay = next.difference(DateTime.now());
    if (delay.isNegative) return;
    _scheduleTimer = Timer(delay + const Duration(seconds: 1), () {
      if (mounted) _onThemeModeChanged();
    });
  }

  Future<void> _refreshWallpaperSeed() async {
    final seed = await WallpaperSeed.compute();
    if (mounted) wallpaperSeed.value = seed;
  }

  void _onWallpaperTintChanged() {
    unawaited(_refreshWallpaperSeed());
  }

  Future<void> _ensureFullScreenIntentPermission() async {
    // placeholder
  }

  void _onIncomingCall(IncomingCall call) {
    // placeholder for brevity
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final seed = accentSeed.value ?? _fallbackSeed;
        final light = lightDynamic ?? ColorScheme.fromSeed(seedColor: seed);
        final dark = darkDynamic ??
            ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.dark,
            );
        return ValueListenableBuilder<double>(
          valueListenable: fontScale,
          builder: (context, scale, _) {
            return MaterialApp(
              navigatorKey: KometApp.navigatorKey,
              locale: _locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData(
                colorScheme: light,
                useMaterial3: true,
                pageTransitionsTheme: _appPageTransitions,
                progressIndicatorTheme: _expressiveProgressTheme,
              ),
              darkTheme: ThemeData(
                colorScheme: dark,
                useMaterial3: true,
                pageTransitionsTheme: _appPageTransitions,
                progressIndicatorTheme: _expressiveProgressTheme,
              ),
              themeMode: _effectiveThemeMode,
              home: _shellReady
                  ? const AdaptiveShell()
                  : const Scaffold(
                      body: Center(child: SmallSpinner()),
                    ),
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
            );
          },
        );
      },
    );
  }
}
