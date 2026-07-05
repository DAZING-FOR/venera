import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:venera/foundation/js_engine.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/network/app_dio.dart';

/// Domain manager for 禁漫天堂 (jm) source.
///
/// Tests all known API domains and switches to the fastest one.
/// Domain lists are sourced from JMComic-Crawler-Python and
/// jm.js's built-in remote server URLs.
class JmDomainManager extends ChangeNotifier {
  JmDomainManager._();

  static final JmDomainManager _instance = JmDomainManager._();
  factory JmDomainManager() => _instance;

  /// Known API domains (from JMComic-Crawler-Python's DOMAIN_API_LIST)
  static const _knownApiDomains = [
    'www.cdnaspa.club',
    'www.cdnaspa.vip',
    'www.cdnplaystation6.cc',
    'www.cdnplaystation6.vip',
    'www.cdntwice.org',
    'www.cdnsha.org',
    'www.cdnaspa.cc',
    'www.cdnntr.cc',
  ];

  /// Remote domain server URLs (from Python's API_URL_DOMAIN_SERVER_LIST)
  static const _domainServerUrls = [
    'https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c03.tos-cn-beijing.bytepluses.com.cn/newsvr-2025.txt',
  ];

  /// GitHub mirror URLs for domain lists (from Python's get_html_domain_all_via_github)
  static const _gitDomainUrls = [
    'https://raw.githubusercontent.com/hect0x7/JMComic-Crawler-Python/master/assets/domain_api.txt',
    'https://raw.githubusercontent.com/hect0x7/JMComic-Crawler-Python/master/assets/domain_html.txt',
  ];

  bool _isTesting = false;
  String? _currentDomain;
  Map<String, int> _lastTestResults = {};

  bool get isTesting => _isTesting;
  String? get currentDomain => _currentDomain;
  Map<String, int> get lastTestResults => Map.unmodifiable(_lastTestResults);

  Timer? _periodicTimer;

  /// Initialize: test domains and pick fastest.
  Future<void> init() async {
    Log.info('JmDomain', 'Initializing...');

    // Test all known domains immediately — no delay
    await testAndSwitchToBestDomain();

    // Periodic re-check every 30 minutes
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => testAndSwitchToBestDomain(),
    );
  }

  void disposeManager() {
    _periodicTimer?.cancel();
    notifyListeners();
  }

  /// Test all known API domains and switch to the fastest one.
  /// Uses the app's HttpClient (AppDio) with proper proxy/TLS settings.
  Future<String?> testAndSwitchToBestDomain() async {
    if (_isTesting) return _currentDomain;
    _isTesting = true;
    notifyListeners();

    try {
      var allDomains = _knownApiDomains.toList();

      // Also try to fetch extra domains from remote sources
      var extraDomains = await _fetchExtraDomains();
      for (final d in extraDomains) {
        if (!allDomains.contains(d)) allDomains.add(d);
      }

      Log.info('JmDomain', 'Testing ${allDomains.length} domains...');
      var bestDomain = await _findBestDomain(allDomains);

      if (bestDomain != null) {
        // Reorder: best domain first, then the rest (deduped)
        allDomains.remove(bestDomain);
        allDomains.insert(0, bestDomain);

        if (bestDomain != _currentDomain) {
          _currentDomain = bestDomain;
          // Update JS engine's apiDomains so jm source uses the best domain
          _syncDomainsToJsEngine(allDomains);
          Log.info('JmDomain', '✅ Switched to best domain: $bestDomain');
        }
      } else {
        Log.warning("JmDomain", "⚠ All built-in domains unreachable, trying fallback...");

        // Fallback: try to refresh domains via JM source's own mechanism
        var fallbackDomains = await _fetchDomainsViaJsEngine();
        if (fallbackDomains.isNotEmpty) {
          Log.info("JmDomain", "Fallback: (${fallbackDomains.length}) domains from JS engine");
          bestDomain = await _findBestDomain(fallbackDomains);
          if (bestDomain != null) {
            _currentDomain = bestDomain;
            _syncDomainsToJsEngine(fallbackDomains);
            Log.info("JmDomain", "✅ Fallback switched to best domain: $bestDomain");
          }
        }
      }

      return bestDomain;
    } catch (e, s) {
      Log.error('JmDomain', 'Domain test failed', '$e\n$s');
      return _currentDomain;
    } finally {
      _isTesting = false;
      notifyListeners();
    }
  }

  /// Write the domain list back to JS engine so the jm source uses the right domains.
  void _syncDomainsToJsEngine(List<String> domains) {
    try {
      // Set JM.apiDomains directly (simple property assignment, no method calls)
      JsEngine().runCode(
        'ComicSource.sources.jm.constructor.apiDomains = ${_toJsArray(domains)}',
      );
      // Also reset apiDomain index to 1 (first = best)
      JsEngine().runCode(
        'ComicSource.sources.jm.saveSetting("apiDomain", "1")',
      );
      Log.info('JmDomain', 'Synced ${domains.length} domains to JS engine');
    } catch (e) {
      Log.warning('JmDomain', 'Failed to sync domains to JS engine: $e');
    }
  }

  /// Fetch extra domains from remote sources.
  Future<List<String>> _fetchExtraDomains() async {
    var extra = <String>{};

    // Try domain server URLs
    for (final url in _domainServerUrls) {
      try {
        final dio = AppDio(BaseOptions(
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 5),
        ));
        final response = await dio.get<String>(url);
        dio.close();
        if (response.statusCode == 200 && response.data != null) {
          // Raw encrypted text; extract potential domain names
          for (final line in response.data!.split('\n')) {
            final d = line.trim().toLowerCase();
            if (d.contains('.') && !d.contains(' ')) {
              extra.add(d);
            }
          }
        }
      } catch (_) {}
    }

    // Try GitHub mirrors
    for (final url in _gitDomainUrls) {
      try {
        final dio = AppDio(BaseOptions(
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 5),
        ));
        final response = await dio.get<String>(url);
        dio.close();
        if (response.statusCode == 200 && response.data != null) {
          for (final line in response.data!.split('\n')) {
            final d = line.trim().toLowerCase();
            if (d.isNotEmpty && !d.startsWith('#') && !d.startsWith('//')) {
              extra.add(d);
            }
          }
        }
      } catch (_) {}
    }

    return extra.toList();
  }

  /// Fallback: invoke JM source's own refreshApiDomains() through the JS engine.
  /// This fetches, decrypts, and updates the domain list using the JM source's
  /// well-tested internal logic (same code path as refresh on startup).
  /// Returns updated domains from JS engine, or empty list on failure.
  Future<List<String>> _fetchDomainsViaJsEngine() async {
    try {
      Log.info("JmDomain", "Fetching domains via JM source's refreshApiDomains...");

      // Step 1: call JM's own refresh function (handles fetch + decrypt + update internally)
      await JsEngine().runCode(
          "ComicSource.sources.jm.refreshApiDomains(false)");

      // Step 2: read the (possibly updated) apiDomains from JS engine
      var domains = JsEngine().runCode(
          "ComicSource.sources.jm.constructor.apiDomains");
      if (domains is List && domains.isNotEmpty) {
        var result = domains.map((e) => e.toString().trim()).toList();
        Log.info("JmDomain",
            "JM source returned ${result.length} domains: $result");
        return result;
      }
    } catch (e) {
      Log.warning("JmDomain", "JS engine domain fetch failed: $e");
    }
    return [];
  }

  /// Test all domains against the API endpoint and find the fastest.
  /// Tests are run in parallel to minimize the wait time for the user.
  Future<String?> _findBestDomain(List<String> domains) async {
    final results = <String, int>{};
    const testPath = '/promote?page=0';
    const headers = {
      'Accept': '*/*',
      'Accept-Encoding': 'gzip, deflate, br',
      'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K; wv) AppleWebKit/537.36',
    };

    // Test all domains in parallel
    await Future.wait(domains.map((domain) async {
      try {
        final dio = AppDio(BaseOptions(
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 5),
          validateStatus: (_) => true,
        ));
        final sw = Stopwatch()..start();
        final r = await dio.get(
          'https://$domain$testPath',
          options: Options(headers: headers),
        );
        dio.close();
        sw.stop();
        if (r.statusCode == 200) {
          results[domain] = sw.elapsedMilliseconds;
          Log.info('JmDomain', '$domain: ${sw.elapsedMilliseconds}ms ✅');
        }
      } catch (e) {
        Log.info('JmDomain', '$domain: unreachable');
      }
    }));

    _lastTestResults = Map.from(results);
    if (results.isEmpty) return null;

    final sorted = results.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return sorted.first.key;
  }

  static String _toJsArray(List<String> list) {
    return '[${list.map((e) => '"$e"').join(',')}]';
  }
}
