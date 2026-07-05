import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/comic_source_page.dart';
import 'package:venera/pages/downloading_page.dart';
import 'package:venera/pages/favorites/favorites_page.dart';
import 'package:venera/pages/follow_updates_page.dart';
import 'package:venera/pages/history_page.dart';
import 'package:venera/pages/image_favorites_page/image_favorites_page.dart';
import 'package:venera/pages/local_comics_page.dart';
import 'package:venera/pages/settings/settings_page.dart';
import 'package:venera/utils/translations.dart';

class MyPage extends StatelessWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverPadding(padding: EdgeInsets.only(top: context.padding.top + 8)),
        const _SectionHeader(title: 'History'),
        const _HistorySection(),
        const _SectionHeader(title: 'Local'),
        const _LocalSection(),
        const _SectionHeader(title: 'More'),
        const _MoreSection(),
        SliverPadding(padding: EdgeInsets.only(top: context.padding.bottom)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          title.tl,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _HistorySection extends StatefulWidget {
  const _HistorySection();

  @override
  State<_HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends State<_HistorySection> {
  late List<History> _history;
  late int _count;

  void _onChange() {
    if (mounted) {
      setState(() {
        _history = HistoryManager().getRecent();
        _count = HistoryManager().count();
      });
    }
  }

  @override
  void initState() {
    _history = HistoryManager().getRecent();
    _count = HistoryManager().count();
    HistoryManager().addListener(_onChange);
    super.initState();
  }

  @override
  void dispose() {
    HistoryManager().removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_history.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text('No history'.tl, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ),
      );
    }
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.history),
              title: Text('History'.tl),
              subtitle: Text('@c comics'.tlParams({'c': _count.toString()})),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => App.rootContext.to(() => const HistoryPage()),
            ),
            if (_history.isNotEmpty)
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _history.length > 8 ? 8 : _history.length,
                  itemBuilder: (context, index) {
                    final h = _history[index];
                    return SimpleComicTile(
                      comic: h,
                      heroID: h.id.hashCode,
                      onTap: () => App.rootContext.to(
                        () => ComicPage(
                          id: h.id,
                          sourceKey: h.type.sourceKey,
                          cover: h.cover,
                          title: h.title,
                          heroID: h.id.hashCode,
                        ),
                      ),
                    ).paddingHorizontal(4).paddingVertical(4);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LocalSection extends StatefulWidget {
  const _LocalSection();

  @override
  State<_LocalSection> createState() => _LocalSectionState();
}

class _LocalSectionState extends State<_LocalSection> {
  late List<LocalComic> _local;
  late int _count;

  void _onChange() {
    if (mounted) {
      setState(() {
        _local = LocalManager().getRecent();
        _count = LocalManager().count;
      });
    }
  }

  @override
  void initState() {
    _local = LocalManager().getRecent();
    _count = LocalManager().count;
    LocalManager().addListener(_onChange);
    super.initState();
  }

  @override
  void dispose() {
    LocalManager().removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text('Local'.tl),
              subtitle: Text('@c comics'.tlParams({'c': _count.toString()})),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => App.rootContext.to(() => const LocalComicsPage()),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text('Downloading'.tl),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (LocalManager().downloadingTasks.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        LocalManager().downloadingTasks.length.toString(),
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios, size: 16),
                ],
              ),
              onTap: () {
                if (LocalManager().downloadingTasks.isNotEmpty) {
                  showPopUpWidget(App.rootContext, const DownloadingPage());
                }
              },
            ),
            if (_local.isNotEmpty)
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _local.length > 8 ? 8 : _local.length,
                  itemBuilder: (context, index) {
                    final c = _local[index];
                    return SimpleComicTile(
                      comic: c,
                      heroID: c.id.hashCode,
                      onTap: () => App.rootContext.to(
                        () => ComicPage(
                          id: c.id,
                          sourceKey: c.sourceKey,
                          cover: c.cover,
                          title: c.title,
                          heroID: c.id.hashCode,
                        ),
                      ),
                    ).paddingHorizontal(4).paddingVertical(4);
                  },
                ),
              ).paddingBottom(8),
          ],
        ),
      ),
    );
  }
}

class _MoreSection extends StatelessWidget {
  const _MoreSection();

  @override
  Widget build(BuildContext context) {
    final comicSourceCount = ComicSourceManager().all().length;
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.favorite_outline),
              title: Text('Favorites'.tl),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => App.rootContext.to(() => const FavoritesPage()),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text('Image Favorites'.tl),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => App.rootContext.to(() => const ImageFavoritesPage()),
            ),
            ListTile(
              leading: const Icon(Icons.update),
              title: Text('Follow Updates'.tl),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => App.rootContext.to(() => const FollowUpdatesPage()),
            ),
            ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: Text('Comic Source'.tl),
              subtitle: Text('@c sources'.tlParams({'c': comicSourceCount.toString()})),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => App.rootContext.to(() => const ComicSourcePage()),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text('Settings'.tl),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => App.rootContext.to(() => const SettingsPage()),
            ),
          ],
        ),
      ),
    );
  }
}
