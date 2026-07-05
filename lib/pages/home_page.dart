import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/jm_domain_manager.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/pages/category_comics_page.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/ranking_page.dart';
import 'package:venera/pages/search_page.dart';
import 'package:venera/pages/search_result_page.dart';
import 'package:venera/utils/translations.dart';

/// JM comic source key
const _jmSourceKey = 'jm';

/// Home page showing hot comics from 禁漫天堂 (jm)
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin<HomePage> {
  List<ExplorePagePart>? _parts;
  bool _loading = true;
  bool _domainRefreshing = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    JmDomainManager().addListener(_onDomainChanged);
    _loadData();
  }

  @override
  void dispose() {
    JmDomainManager().removeListener(_onDomainChanged);
    super.dispose();
  }

  void _onDomainChanged() {
    if (!JmDomainManager().isTesting && _error != null) {
      // Domain was just refreshed while we had an error — retry
      _loadData(tryRefreshDomain: false);
    }
  }

  Future<void> _loadData({bool tryRefreshDomain = true, bool isRetry = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var jmSource = ComicSource.find(_jmSourceKey);
      if (jmSource == null) {
        setState(() {
          _loading = false;
          _error = 'Source not found: 禁漫天堂';
        });
        return;
      }

      if (jmSource.explorePages.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No explore data available';
        });
        return;
      }

      var exploreData = jmSource.explorePages[0];
      if (exploreData.loadMultiPart == null) {
        setState(() {
          _loading = false;
          _error = 'Explore type not supported';
        });
        return;
      }

      var res = await exploreData.loadMultiPart!();
      if (mounted) {
        if (res.error && tryRefreshDomain) {
          // Try refreshing domains first, then retry once
          Log.info('HomePage', 'Load failed, trying domain refresh...');
          await JmDomainManager().testAndSwitchToBestDomain();
          // Retry without domain refresh to avoid infinite loop
          await _loadData(tryRefreshDomain: false);
          return;
        }
        setState(() {
          _loading = false;
          if (res.error) {
            _error = res.errorMessage;
          } else {
            _parts = res.data;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        // Auto-retry once on transient network errors
        if (!isRetry) {
          Log.info('HomePage', 'Load threw, retrying once...');
          await JmDomainManager().testAndSwitchToBestDomain();
          await _loadData(tryRefreshDomain: false, isRetry: true);
          return;
        }
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _refreshDomain() async {
    setState(() => _domainRefreshing = true);
    var domain = await JmDomainManager().testAndSwitchToBestDomain();
    setState(() => _domainRefreshing = false);
    if (domain != null) {
      // Reload data with the new domain
      _loadData(tryRefreshDomain: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return SmoothCustomScrollView(
      slivers: [
        SliverPadding(padding: EdgeInsets.only(top: context.padding.top + 4)),
        // Search bar
        const _SearchBar(),
        // Quick action buttons: Ranking, Weekly
        const _QuickActions(),
        // Hot comics sections from jm
        if (_loading)
          const SliverToBoxAdapter(
            child: SizedBox(
              height: 300,
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (_error != null)
          SliverToBoxAdapter(
            child: _buildError(),
          )
        else if (_parts != null)
          ..._buildSections(),
        SliverPadding(padding: EdgeInsets.only(top: context.padding.bottom)),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_off, size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: _domainRefreshing ? null : _refreshDomain,
                icon: _domainRefreshing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering, size: 18),
                label: Text(_domainRefreshing ? 'Testing Domains...'.tl : 'Refresh Domain'.tl),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => _loadData(tryRefreshDomain: false),
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Iterable<Widget> _buildSections() sync* {
    if (_parts == null) return;

    for (var part in _parts!) {
      yield _SectionHeader(
        title: part.title,
        onViewMore: part.viewMore != null
            ? () => part.viewMore!.jump(App.rootContext)
            : null,
      );
      yield _ComicRow(comics: part.comics, sourceKey: _jmSourceKey);
    }

    // Quick tag access section
    yield _SectionHeader(title: 'Popular Tags');
    yield const _PopularTags();
  }
}

/// Search bar
class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        height: App.isMobile ? 52 : 46,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(32),
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: () => App.rootContext.to(() => const SearchPage()),
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.search),
                const SizedBox(width: 8),
                Text('Search in 禁漫天堂'.tl, style: const TextStyle(fontSize: 16)),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick action buttons row
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            _ActionChip(
              icon: Icons.emoji_events_outlined,
              label: 'Weekly',
              color: Colors.orange,
              onTap: () => App.rootContext.to(
                () => CategoryComicsPage(
                  categoryKey: '禁漫天堂',
                  category: '每週必看',
                ),
              ),
            ),
            const SizedBox(width: 8),
            _ActionChip(
              icon: Icons.trending_up,
              label: 'Ranking',
              color: Colors.blue,
              onTap: () => App.rootContext.to(
                () => RankingPage(categoryKey: '禁漫天堂'),
              ),
            ),
            const SizedBox(width: 8),
            _ActionChip(
              icon: Icons.local_fire_department_outlined,
              label: 'Latest',
              color: Colors.red,
              onTap: () => App.rootContext.to(
                () => CategoryComicsPage(
                  categoryKey: '禁漫天堂',
                  category: '最新A漫',
                ),
              ),
            ),
            const SizedBox(width: 8),
            _ActionChip(
              icon: Icons.shuffle,
              label: 'Search',
              color: scheme.primary,
              onTap: () => App.rootContext.to(
                () => const SearchPage(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 4),
                Text(label.tl, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section header with optional "view more" button
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onViewMore});

  final String title;
  final VoidCallback? onViewMore;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
        child: Row(
          children: [
            Text(
              title.tl,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (onViewMore != null)
              TextButton(
                onPressed: onViewMore,
                child: Text('View more'.tl),
              ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal scrolling row of comic tiles
class _ComicRow extends StatelessWidget {
  const _ComicRow({required this.comics, required this.sourceKey});

  final List<Comic> comics;
  final String sourceKey;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 200,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: comics.length,
          itemBuilder: (context, index) {
            final comic = comics[index];
            final heroID = comic.id.hashCode ^ sourceKey.hashCode;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SimpleComicTile(
                comic: comic,
                heroID: heroID,
                onTap: () => App.rootContext.to(
                  () => ComicPage(
                    id: comic.id,
                    sourceKey: sourceKey,
                    cover: comic.cover,
                    title: comic.title,
                    heroID: heroID,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Popular tags from jm categories
class _PopularTags extends StatelessWidget {
  const _PopularTags();

  static const _popularTags = [
    'NTR',
    '扶他',
    '性轉',
    '姐姐',
    '原神',
    '純愛',
    '人妻',
    '百合',
    '調教',
    '觸手',
    '無修正',
    '御姐',
    '巨乳',
    '女僕',
    '全彩',
    '催眠',
    '熟女',
    '眼鏡',
  ];

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _popularTags.map((tag) {
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                var context = App.mainNavigatorKey!.currentContext!;
                context.to(
                  () => SearchResultPage(
                    text: tag,
                    sourceKey: _jmSourceKey,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withAlpha(120),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
