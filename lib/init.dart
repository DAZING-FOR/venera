import 'dart:async';
import 'dart:convert';

import 'package:display_mode/display_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_saf/flutter_saf.dart';
import 'package:rhttp/rhttp.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/cache_manager.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/jm_domain_manager.dart';
import 'package:venera/foundation/js_engine.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/network/app_dio.dart';
import 'package:venera/network/cookie_jar.dart';
import 'package:venera/pages/comic_source_page.dart';
import 'package:venera/pages/follow_updates_page.dart';
import 'package:venera/pages/settings/settings_page.dart';
import 'package:venera/utils/app_links.dart';
import 'package:venera/utils/handle_text_share.dart';
import 'package:venera/utils/ext.dart';
import 'package:venera/utils/opencc.dart';
import 'package:venera/utils/tags_translation.dart';
import 'package:venera/utils/translations.dart';
import 'foundation/appdata.dart';

extension _FutureInit<T> on Future<T> {
  /// Prevent unhandled exception
  ///
  /// A unhandled exception occurred in init() will cause the app to crash.
  Future<void> wait() async {
    try {
      await this;
    } catch (e, s) {
      Log.error("init", "$e\n$s");
    }
  }
}

Future<void> init() async {
  await App.init().wait();
  await SingleInstanceCookieJar.createInstance();
  try {
    var futures = [
      Rhttp.init(),
      App.initComponents(),
      SAFTaskWorker().init().wait(),
      AppTranslation.init().wait(),
      TagsTranslation.readData().wait(),
      JsEngine().init().wait(),
      ComicSourceManager().init().wait(),
      OpenCC.init(),
    ];
    await Future.wait(futures);
  } catch (e, s) {
    Log.error("init", "$e\n$s");
  }
  CacheManager().setLimitSize(appdata.settings['cacheSize']);
  _checkOldConfigs();
  // Auto-install jm source if missing (fire-and-forget, don't block startup)
  _ensureJmSourceInstalled();
  // Auto-initialize jm domain manager (test & use best domain)
  JmDomainManager().init();
  // Warm-up temporarily disabled:
  // The root cause was navigation (detail page pushed to inner Navigator),
  // not loading speed. See _onTap fix in comic.dart.
  // _warmUpAlbumEndpoint();
  if (App.isAndroid) {
    handleLinks();
    handleTextShare();
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch(e) {
      Log.error("Display Mode", "Failed to set high refresh rate: $e");
    }
  }
  FlutterError.onError = (details) {
    Log.error("Unhandled Exception", "${details.exception}\n${details.stack}");
  };
  if (App.isWindows) {
    // Report to the monitor thread that the app is running
    // https://github.com/venera-app/venera/issues/343
    Timer.periodic(const Duration(seconds: 1), (_) {
      const methodChannel = MethodChannel('venera/method_channel');
      methodChannel.invokeMethod("heartBeat");
    });
  }
}

/// Auto-install the jm comic source (禁漫天堂) if it's not already installed.
Future<void> _ensureJmSourceInstalled() async {
  if (ComicSource.find('jm') != null) return;

  Log.info('init', 'jm source not found, auto-installing...');

  // Try multiple config URLs in case one is blocked/corrupted
  final configUrls = [
    appdata.settings['comicSourceListUrl'] as String,
    'https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json',
    'https://raw.githubusercontent.com/venera-app/venera-configs/main/index.json',
  ];

  // Aggressive timeouts since this runs at startup — fail fast, don't block
  final dio = AppDio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 5),
    sendTimeout: const Duration(seconds: 5),
  ));

  for (final configUrl in configUrls) {
    try {
      final configRes = await dio.get<String>(configUrl);
      if (configRes.statusCode != 200) continue;

      final List sources = jsonDecode(configRes.data!);
      final jmEntry = sources.firstWhereOrNull(
        (s) => s['key'] == 'jm',
      );
      if (jmEntry == null) continue;

      // Build the JS file URL (same base as config)
      final parts = configUrl.split('/');
      final baseUrl = parts.take(parts.length - 1).join('/');
      final jsUrl = '$baseUrl/${jmEntry['fileName']}';

      final jsRes = await dio.get<String>(jsUrl, options: Options(
        responseType: ResponseType.plain,
        headers: {"cache-time": "no"},
      ));
      if (jsRes.statusCode != 200) continue;

      final comicSource = await ComicSourceParser().createAndParse(
        jsRes.data!,
        jmEntry['fileName'],
      );
      ComicSourceManager().add(comicSource);
      Log.info('init', 'jm source installed from $configUrl');
      // Save the working URL
      appdata.settings['comicSourceListUrl'] = configUrl;
      appdata.saveData();
      return;
    } catch (e) {
      Log.warning('init', 'Failed to install from $configUrl: $e');
    }
  }

  Log.error('init', 'All URLs failed for jm source install');
}

void _checkOldConfigs() {
  if (appdata.settings['searchSources'] == null) {
    appdata.settings['searchSources'] = ComicSource.all()
        .where((e) => e.searchPageData != null)
        .map((e) => e.key)
        .toList();
  }

  if (appdata.implicitData['webdavAutoSync'] == null) {
    var webdavConfig = appdata.settings['webdav'];
    if (webdavConfig is List &&
        webdavConfig.length == 3 &&
        webdavConfig.whereType<String>().length == 3) {
      appdata.implicitData['webdavAutoSync'] = true;
    } else {
      appdata.implicitData['webdavAutoSync'] = false;
    }
    appdata.writeImplicitData();
  }

  if (appdata.settings['comicSourceListUrl'].toString().contains("git.nyne.dev")) {
    // migrate to jsdelivr cdn
    appdata.settings['comicSourceListUrl'] = "https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json";
    appdata.saveData();
  }
}

Future<void> _checkAppUpdates() async {
  var lastCheck = appdata.implicitData['lastCheckUpdate'] ?? 0;
  var now = DateTime.now().millisecondsSinceEpoch;
  if (now - lastCheck < 24 * 60 * 60 * 1000) {
    return;
  }
  appdata.implicitData['lastCheckUpdate'] = now;
  appdata.writeImplicitData();
  ComicSourcePage.checkComicSourceUpdate();
  if (appdata.settings['checkUpdateOnStart']) {
    await checkUpdateUi(false, true);
  }
}

void checkUpdates() {
  _checkAppUpdates();
  FollowUpdatesService.initChecker();
}

// /// Fire a background request to the JM /album endpoint to warm it up.
// /// Temporarily disabled: the root cause was navigation, not loading speed.
// void _warmUpAlbumEndpoint() {
//   Future.delayed(const Duration(seconds: 3), () async {
//     try {
//       var source = ComicSource.find('jm');
//       if (source?.loadComicInfo == null) return;
//       Log.info('init', 'Warming up /album endpoint...');
//       await source!.loadComicInfo!('277238');
//       Log.info('init', '✅ /album endpoint warmed up');
//     } catch (e) {
//       Log.info('init', '/album warm-up skipped: $e');
//     }
//   });
// }
