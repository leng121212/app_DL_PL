import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/drama_models.dart';
import '../services/app_update_service.dart';
import '../services/download_manager.dart';
import '../services/hongguo_service.dart';
import '../services/license_service.dart';
import '../services/mydrama_service.dart';
import '../services/reelsdizim_service.dart';
import '../services/reelshort_service.dart';
import '../services/beeplaylet_service.dart';
import '../services/iqiyi_creator_service.dart';
import '../services/eightmovie_service.dart';
import '../services/bmp4_service.dart';
import '../theme/app_theme.dart';
import '../utils/url_helper.dart';
import '../widgets/app_update_dialog.dart';
import '../widgets/drama_card.dart';
import '../widgets/drama_detail_sheet.dart';
import 'downloads_screen.dart';
import 'license_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  PlatformType _currentPlatform = PlatformType.hongguo;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _catalogScrollController = ScrollController();

  List<DramaItem> _catalogItems = [];
  bool _isLoadingCatalog = false;
  bool _isResolving = false;
  String _selectedCategory = 'all';
  int _currentPage = 1;
  static const int _pageSize = 18;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCatalog();

    // Auto-check for update on startup (delayed 3s)
    Future.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      try {
        final info = await AppUpdateService().checkForUpdate();
        if (info.hasUpdate && mounted) {
          AppUpdateDialog.show(context, info);
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _catalogScrollController.dispose();
    super.dispose();
  }

  void _switchPlatform(PlatformType platform) {
    if (_currentPlatform == platform) return;
    if (_catalogScrollController.hasClients) {
      _catalogScrollController.jumpTo(0);
    }
    setState(() {
      _currentPlatform = platform;
      _searchController.clear();
      _currentPage = 1;
      _selectedCategory = 'all';
    });
    _loadCatalog();
  }

  Future<void> _loadCatalog({int page = 1}) async {
    setState(() {
      _isLoadingCatalog = true;
      _errorMessage = null;
      _currentPage = page;
    });

    List<DramaItem> items = [];
    try {
      switch (_currentPlatform) {
        case PlatformType.hongguo:
          items = await HongguoService.fetchCatalog(category: _selectedCategory, page: page);
          break;
        case PlatformType.reelshort:
          items = await ReelshortService.fetchCatalogByCategory(category: _selectedCategory, page: page, pageSize: _pageSize);
          break;
        case PlatformType.web20:
          items = await IqiyiCreatorService.fetchCatalogByCategory(category: _selectedCategory, page: page, pageSize: _pageSize);
          break;
        case PlatformType.bmp4:
        case PlatformType.eightmovie:
        case PlatformType.beeplaylet:
        case PlatformType.mydrama:
        case PlatformType.reelsdizim:
          items = await BeeplayletService.fetchCatalog(page: page);
          break;
      }
    } catch (e) {
      _errorMessage = 'មិនអាចទាញយកតារាងរឿងបានទេ: $e';
    }

    if (mounted) {
      setState(() {
        _catalogItems = items;
        _isLoadingCatalog = false;
        if (items.isEmpty && _errorMessage == null) {
          _errorMessage = 'គ្មានទិន្នន័យរឿងក្នុងបញ្ជីនេះទេ';
        }
      });
    }
  }

  void _goToPage(int page) {
    if (page == _currentPage) return;
    if (_catalogScrollController.hasClients) {
      _catalogScrollController.jumpTo(0);
    }
    _loadCatalog(page: page);
  }

  Future<void> _resolveDrama(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('សូមបញ្ចូល Link រឿង ឬ ID ជាមុនសិន'),
          backgroundColor: AppTheme.amberWarning,
        ),
      );
      return;
    }

    // Auto-detect URL patterns and switch to appropriate platform
    if (q.contains('novelquickapp.com') || q.contains('hongguoduanju.com') || q.contains('红果')) {
      if (_currentPlatform != PlatformType.hongguo) {
        setState(() => _currentPlatform = PlatformType.hongguo);
      }
    } else if (q.contains('reelshort.com')) {
      if (_currentPlatform != PlatformType.reelshort) {
        setState(() => _currentPlatform = PlatformType.reelshort);
      }
    } else if (q.contains('bmp4.com') ||
        q.contains('beeplaylet.com') ||
        q.contains('8movie.com') ||
        q.contains('reelsdizim.com') ||
        q.contains('my-drama.com')) {
      if (_currentPlatform != PlatformType.web20) {
        setState(() => _currentPlatform = PlatformType.web20);
      }
    }

    setState(() => _isResolving = true);

    DramaItem? resolved;
    try {
      switch (_currentPlatform) {
        case PlatformType.hongguo:
          resolved = await HongguoService.resolveDrama(q);
          if (resolved == null) {
            final hgMatches = await HongguoService.search(q);
            if (hgMatches.isNotEmpty) {
              setState(() {
                _catalogItems = hgMatches;
                _isResolving = false;
              });
              if (_catalogScrollController.hasClients) {
                _catalogScrollController.jumpTo(0);
              }
              return;
            }
          }
          break;
        case PlatformType.reelshort:
          resolved = await ReelshortService.resolveDrama(q);
          break;
        case PlatformType.web20:
          if (q.contains('iqiyi.com') || q.startsWith('iqiyi_') || RegExp(r'^\d{10,}$').hasMatch(q.trim())) {
            resolved = await IqiyiCreatorService.resolveDrama(q);
          } else if (q.contains('beeplaylet.com')) {
            resolved = await BeeplayletService.resolveDrama(q);
          } else if (q.contains('8movie.com')) {
            resolved = await EightMovieService.resolveDrama(q);
          } else if (q.contains('bmp4.com')) {
            resolved = await Bmp4Service.resolveDrama(q);
          } else if (q.contains('reelsdizim.com')) {
            resolved = await ReelsDizimService.resolveDrama(q);
          } else if (q.contains('my-drama.com')) {
            resolved = await MyDramaService.resolveDrama(q);
          } else {
            final iqMatches = await IqiyiCreatorService.search(q);
            final beeMatches = await BeeplayletService.search(q);
            final eightMatches = await EightMovieService.search(q);
            final searchResults = [...iqMatches, ...beeMatches, ...eightMatches];
            if (searchResults.isNotEmpty) {
              setState(() {
                _catalogItems = searchResults;
                _isResolving = false;
              });
              if (_catalogScrollController.hasClients) {
                _catalogScrollController.jumpTo(0);
              }
              return;
            }
            resolved = await EightMovieService.resolveDrama(q) ??
                await BeeplayletService.resolveDrama(q) ??
                await IqiyiCreatorService.resolveDrama(q);
          }
          break;
        case PlatformType.bmp4:
          resolved = await Bmp4Service.resolveDrama(q);
          break;
        case PlatformType.eightmovie:
          resolved = await EightMovieService.resolveDrama(q);
          break;
        case PlatformType.beeplaylet:
          resolved = await BeeplayletService.resolveDrama(q);
          break;
        case PlatformType.mydrama:
          resolved = await MyDramaService.resolveDrama(q);
          break;
        case PlatformType.reelsdizim:
          resolved = await ReelsDizimService.resolveDrama(q);
          break;
      }
    } catch (e) {
      // Handled below
    }

    setState(() => _isResolving = false);

    if (resolved != null && mounted) {
      _openDramaDetail(resolved);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('មិនអាចស្វែងរកព័ត៌មានរឿងនេះបានទេ សូមពិនិត្យ Link ឬ ID ឡើងវិញ'),
          backgroundColor: AppTheme.redDanger,
        ),
      );
    }
  }

  void _openDramaDetail(DramaItem drama) async {
    // If drama doesn't have episodes resolved yet (e.g. from catalog card)
    if (drama.episodes == null || drama.episodes!.isEmpty) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppTheme.cyanAccent),
        ),
      );

      DramaItem? full;
      try {
        switch (drama.platform) {
          case PlatformType.hongguo:
            full = await HongguoService.resolveDrama(drama.id);
            break;
          case PlatformType.reelshort:
            full = await ReelshortService.resolveDrama(drama.detailUrl);
            break;
          case PlatformType.web20:
            if (drama.id.startsWith('iqiyi_') || drama.detailUrl.contains('iqiyi.com')) {
              full = await IqiyiCreatorService.resolveDrama(drama.id.isNotEmpty ? drama.id : drama.detailUrl);
            } else if (drama.platform == PlatformType.eightmovie || drama.detailUrl.contains('8movie') || drama.id.contains('8movie')) {
              full = await EightMovieService.resolveDrama(drama.id.isNotEmpty ? drama.id : drama.detailUrl);
            } else if (drama.platform == PlatformType.bmp4 || drama.detailUrl.contains('bmp4')) {
              full = await Bmp4Service.resolveDrama(drama.id.isNotEmpty ? drama.id : drama.detailUrl);
            } else if (drama.platform == PlatformType.reelsdizim || drama.detailUrl.contains('reelsdizim')) {
              full = await ReelsDizimService.resolveDrama(drama.detailUrl.isNotEmpty ? drama.detailUrl : drama.id);
            } else if (drama.platform == PlatformType.mydrama || drama.detailUrl.contains('my-drama')) {
              full = await MyDramaService.resolveDrama(drama.detailUrl.isNotEmpty ? drama.detailUrl : drama.id);
            } else {
              full = await BeeplayletService.resolveDrama(drama.id.isNotEmpty ? drama.id : drama.detailUrl);
            }
            break;
          case PlatformType.bmp4:
            full = await Bmp4Service.resolveDrama(drama.id.isNotEmpty ? drama.id : drama.detailUrl);
            break;
          case PlatformType.eightmovie:
            full = await EightMovieService.resolveDrama(drama.id.isNotEmpty ? drama.id : drama.detailUrl);
            break;
          case PlatformType.beeplaylet:
            full = await BeeplayletService.resolveDrama(drama.id.isNotEmpty ? drama.id : drama.detailUrl);
            break;
          case PlatformType.mydrama:
            full = await MyDramaService.resolveDrama(drama.detailUrl.isNotEmpty ? drama.detailUrl : drama.id);
            break;
          case PlatformType.reelsdizim:
            full = await ReelsDizimService.resolveDrama(drama.detailUrl.isNotEmpty ? drama.detailUrl : drama.id);
            break;
        }
      } catch (_) {}

      if (mounted) Navigator.pop(context); // Dismiss loading dialog

      if (full != null) {
        drama = full;
      } else {
        // Fallback: generate episodes up to count
        final count = drama.episodeCount > 0 ? drama.episodeCount : 20;
        drama.episodes = List.generate(
          count,
          (i) => EpisodeItem(
            index: i + 1,
            title: 'EP${(i + 1).toString().padLeft(2, '0')}',
          ),
        );
      }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DramaDetailSheet(
        drama: drama,
        onNavigateToDownloads: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DownloadsScreen()),
          );
        },
      ),
    );
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _searchController.text = data.text!;
      _resolveDrama(data.text!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            _buildTopAppBar(),

            // Platform Switcher
            _buildPlatformTabs(),

            // Search & URL Input Bar (Hidden for 20+ Web)
            if (_currentPlatform != PlatformType.web20) _buildSearchBar(),

            // Category Filter Pills (Shown for all platforms)
            _buildCategoryPills(),

            const SizedBox(height: 6),

            // Main Catalog Grid
            Expanded(
              child: _buildCatalogContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopAppBar() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 18, top: 10, bottom: 8),
      child: Row(
        children: [
          // App Logo & Title
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/Trabekprey_DL_App.png',
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Image.asset(
                'assets/Trabekprey.png',
                width: 38,
                height: 38,
                errorBuilder: (_, __, ___) => const Icon(Icons.download_for_offline, color: AppTheme.cyanAccent, size: 38),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trabekprey-DL Pro',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                'Dev: Tong Chhunleng',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.cyanAccent,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const Spacer(),

          // Downloads Queue Action Button
          AnimatedBuilder(
            animation: DownloadManager.instance,
            builder: (context, _) {
              final activeCount = DownloadManager.instance.runningCount;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                    );
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.cardBorder),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.downloading_rounded,
                          color: AppTheme.cyanAccent,
                          size: 22,
                        ),
                        if (activeCount > 0)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: AppTheme.pinkAccent,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                              child: Text(
                                '$activeCount',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(width: 8),

          // Unified Settings Button (Hongguo Bridge + License)
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _showSettingsSheet(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: const Icon(
                  Icons.settings_outlined,
                  color: Colors.white70,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformTabs() {
    const topPlatforms = [
      PlatformType.hongguo,
      PlatformType.reelshort,
      PlatformType.web20,
    ];

    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: topPlatforms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final platform = topPlatforms[index];
          final isSelected = _currentPlatform == platform;

          return InkWell(
            onTap: () => _switchPlatform(platform),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.cyanAccent.withOpacity(0.18) : AppTheme.cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppTheme.cyanAccent : AppTheme.cardBorder,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  if (platform.assetIcon != null)
                    Image.asset(
                      platform.assetIcon!,
                      width: 18,
                      height: 18,
                      errorBuilder: (_, __, ___) => Text(platform.emojiFallback),
                    )
                  else
                    Text(platform.emojiFallback, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(
                    platform == PlatformType.web20 ? '20+ Web' : platform.displayName.split(' ').first,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? AppTheme.cyanAccent : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.link, size: 18, color: AppTheme.cyanAccent),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: InputDecoration(
                  hintText: _currentPlatform.hintText,
                  hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: _resolveDrama,
              ),
            ),
            if (_searchController.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                tooltip: 'សម្អាត (Clear)',
                onPressed: () {
                  _searchController.clear();
                  _loadCatalog();
                },
              ),
            IconButton(
              icon: const Icon(Icons.content_paste, size: 18, color: AppTheme.textSecondary),
              tooltip: 'Paste Link',
              onPressed: _pasteFromClipboard,
            ),
            Container(
              margin: const EdgeInsets.only(right: 4),
              height: 34,
              child: ElevatedButton(
                onPressed: _isResolving ? null : () => _resolveDrama(_searchController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cyanAccent,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: _isResolving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text(
                        'ស្វែងរក',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryPills() {
    final categories = DramaCategoryHelper.getCategories();

    return Container(
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = _selectedCategory == cat['id'];

          return InkWell(
            onTap: () {
              setState(() {
                _selectedCategory = cat['id']!;
                _currentPage = 1;
              });
              _loadCatalog(page: 1);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.cyanAccent.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? AppTheme.cyanAccent : AppTheme.cardBorder.withOpacity(0.5),
                ),
              ),
              child: Text(
                cat['name']!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppTheme.cyanAccent : AppTheme.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCatalogContent() {
    if (_isLoadingCatalog) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.cyanAccent),
            SizedBox(height: 14),
            Text(
              'កំពុងទាញយកតារាងរឿង...',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  HongguoService.clearCache();
                  _loadCatalog();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('ព្យាយាមម្ដងទៀត'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cardBg,
                  foregroundColor: AppTheme.cyanAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: AppTheme.cyanAccent),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final pageItems = _searchController.text.trim().isNotEmpty
        ? _catalogItems
        : (_catalogItems.length <= _pageSize
            ? _catalogItems
            : _catalogItems.take(_pageSize).toList());

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              HongguoService.clearCache();
              await _loadCatalog(page: _currentPage);
            },
            color: AppTheme.cyanAccent,
            backgroundColor: AppTheme.cardBg,
            child: GridView.builder(
              controller: _catalogScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.58,
              ),
              itemCount: pageItems.length,
              itemBuilder: (context, index) {
                final drama = pageItems[index];
                return DramaCard(
                  drama: drama,
                  onTap: () => _openDramaDetail(drama),
                );
              },
            ),
          ),
        ),
        if (_searchController.text.trim().isEmpty) _buildPaginationBar(),
      ],
    );
  }

  int _getTotalPages() {
    switch (_currentPlatform) {
      case PlatformType.hongguo:
        if (_selectedCategory == 'most_episodes') return 10;
        return _selectedCategory == 'all' ? 80 : 34;
      case PlatformType.reelsdizim:
        return 80;
      case PlatformType.reelshort:
        return 50;
      case PlatformType.eightmovie:
        return 20;
      case PlatformType.mydrama:
        return 20;
      case PlatformType.web20:
        return 100;
      case PlatformType.bmp4:
        return 80;
      case PlatformType.beeplaylet:
        return 100;
    }
  }

  Widget _buildPaginationBar() {
    final totalPages = _getTotalPages();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bgDark.withOpacity(0.95),
        border: Border(
          top: BorderSide(
            color: AppTheme.cardBorder.withOpacity(0.6),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Previous Button
          InkWell(
            onTap: _currentPage > 1 && !_isLoadingCatalog
                ? () => _goToPage(_currentPage - 1)
                : null,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _currentPage > 1 ? AppTheme.cardBg : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _currentPage > 1 ? AppTheme.cardBorder : Colors.transparent,
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 16,
                    color: _currentPage > 1 ? AppTheme.cyanAccent : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'ថយ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _currentPage > 1 ? AppTheme.cyanAccent : AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Numbered page chips centered around Current Page
          ...List.generate(5, (i) {
            int pageNum;
            if (_currentPage <= 3) {
              pageNum = i + 1;
            } else if (_currentPage >= totalPages - 2) {
              pageNum = totalPages - 4 + i;
            } else {
              pageNum = _currentPage - 2 + i;
            }

            if (pageNum < 1 || pageNum > totalPages) {
              return const SizedBox.shrink();
            }

            final isCur = pageNum == _currentPage;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: InkWell(
                onTap: !_isLoadingCatalog ? () => _goToPage(pageNum) : null,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isCur ? AppTheme.cyanAccent : AppTheme.cardBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isCur ? AppTheme.cyanAccent : AppTheme.cardBorder,
                      width: isCur ? 1.2 : 0.8,
                    ),
                    boxShadow: isCur
                        ? [
                            BoxShadow(
                              color: AppTheme.cyanAccent.withOpacity(0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$pageNum',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isCur ? FontWeight.bold : FontWeight.w600,
                      color: isCur ? Colors.black : AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),
            );
          }),

          const SizedBox(width: 6),
          // Next Button
          InkWell(
            onTap: _currentPage < totalPages && !_isLoadingCatalog
                ? () => _goToPage(_currentPage + 1)
                : null,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _currentPage < totalPages ? AppTheme.cardBg : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _currentPage < totalPages ? AppTheme.cardBorder : Colors.transparent,
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'បន្ទាប់',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _currentPage < totalPages ? AppTheme.cyanAccent : AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: _currentPage < totalPages ? AppTheme.cyanAccent : AppTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsSheet(BuildContext context) async {
    bool checkingBridge = false;
    bool isBridgeOnline = HongguoService.isCloudBridgeOnline ?? (HongguoService.isBridgeAvailable ?? false);
    String? statusMessage;

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: bottomPadding + 24,
              ),
              decoration: const BoxDecoration(
                color: AppTheme.bgDark,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: AppTheme.cardBorder, width: 1.2)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle Bar
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sheet Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.cyanAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.settings_suggest_rounded, color: AppTheme.cyanAccent, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ការកំណត់ & ការតភ្ជាប់',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Settings & Server Connections',
                              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => _triggerCheckUpdate(sheetCtx),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppTheme.cyanAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.cyanAccent.withOpacity(0.35)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.system_update_rounded, size: 14, color: AppTheme.cyanAccent),
                                SizedBox(width: 4),
                                Text(
                                  'Update',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.cyanAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Section 1: Trabekprey License
                    AnimatedBuilder(
                      animation: LicenseService.instance,
                      builder: (context, _) {
                        final lic = LicenseService.instance.state;
                        final isLog = lic.isLoggedIn;
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isLog ? AppTheme.greenSuccess.withOpacity(0.4) : AppTheme.amberWarning.withOpacity(0.4),
                              width: 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isLog ? Icons.verified_user_rounded : Icons.lock_outline_rounded,
                                    color: isLog ? AppTheme.greenSuccess : AppTheme.amberWarning,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Trabekprey License',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: isLog ? AppTheme.greenSuccess : AppTheme.amberWarning,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: (isLog ? AppTheme.greenSuccess : AppTheme.amberWarning).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isLog ? 'សកម្ម (Active)' : 'មិនទាន់ភ្ជាប់ (Guest)',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isLog ? AppTheme.greenSuccess : AppTheme.amberWarning,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isLog
                                    ? 'គណនី: ${lic.email ?? "សកម្ម"}\nផុតកំណត់: ${lic.expiresAt != null ? lic.expiresAt!.toLocal().toString().split(" ").first : "គ្មានដែនកំណត់"}'
                                    : 'សូមបញ្ចូល License Key ដើម្បីដោះសោមុខងារទាញយកគ្មានដែនកំណត់។',
                                style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.4),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(sheetCtx);
                                    showDialog(
                                      context: context,
                                      builder: (_) => const LicenseDialog(),
                                    );
                                  },
                                  icon: Icon(
                                    isLog ? Icons.manage_accounts_outlined : Icons.key_rounded,
                                    size: 16,
                                    color: AppTheme.cyanAccent,
                                  ),
                                  label: Text(
                                    isLog ? 'គ្រប់គ្រង License / ប្ដូរ Key' : 'បញ្ចូល License Key (Activate)',
                                    style: const TextStyle(fontSize: 12, color: AppTheme.cyanAccent),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppTheme.cyanAccent),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // Section 2: Hongguo Server PC Bridge (Auto-Sync)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isBridgeOnline ? AppTheme.greenSuccess.withOpacity(0.4) : AppTheme.cardBorder,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.bolt_rounded, color: AppTheme.cyanAccent, size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'Hongguo Pro Bridge (PC Server)',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (isBridgeOnline ? AppTheme.greenSuccess : AppTheme.redDanger).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isBridgeOnline ? 'Online 🟢' : 'Offline 🔴',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isBridgeOnline ? AppTheme.greenSuccess : AppTheme.redDanger,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: isBridgeOnline
                                  ? AppTheme.greenSuccess.withOpacity(0.08)
                                  : AppTheme.redDanger.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isBridgeOnline
                                    ? AppTheme.greenSuccess.withOpacity(0.3)
                                    : AppTheme.redDanger.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isBridgeOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                                  color: isBridgeOnline ? AppTheme.greenSuccess : AppTheme.redDanger,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isBridgeOnline
                                            ? 'ប្រព័ន្ធ Auto-Sync បានភ្ជាប់ជោគជ័យ'
                                            : 'Admin មិនទាន់បើក Server លើ PC',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isBridgeOnline ? AppTheme.greenSuccess : AppTheme.redDanger,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isBridgeOnline
                                            ? 'រាល់ភាគ VIP ទាំងអស់ក្នុង Hongguo អាចដោនឡូតបានដោយសេរី'
                                            : (statusMessage ?? 'សូមចុច Auto-Sync ឡើងវិញ ឬទាក់ទង Telegram Admin'),
                                        style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary, height: 1.3),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'សម្រាប់ដោនរឿង Hongguo ដែលជាប់ VIP គឺត្រូវការ Server ពី Admin៖',
                            style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.4),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () => openSafeUrl('https://t.me/Chhunleng1122'),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFF24A1DE).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF24A1DE).withOpacity(0.5)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Color(0xFF24A1DE),
                                    child: Icon(Icons.send_rounded, size: 11, color: Colors.white),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Admin ៖ Chhunleng (t.me/Chhunleng1122)',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF54C5F8),
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.open_in_new_rounded, size: 13, color: Color(0xFF54C5F8)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'ឬអាច Download រឿងពី Reelshort និង 20+ Web បានដោយមិនត្រូវការ Server',
                            style: TextStyle(fontSize: 11, color: AppTheme.greenSuccess, height: 1.3),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: checkingBridge
                                  ? null
                                  : () async {
                                      setSheetState(() {
                                        checkingBridge = true;
                                        statusMessage = 'កំពុង Sync ភ្ជាប់ទៅកាន់ Server...';
                                      });
                                      final ok = await HongguoService.checkBridgeConnection();
                                      setSheetState(() {
                                        checkingBridge = false;
                                        isBridgeOnline = ok;
                                        statusMessage = ok
                                            ? '✅ ភ្ជាប់ជោគជ័យ! បើកដំណើរការ Full Episodes'
                                            : (HongguoService.cloudBridgeError ?? '❌ Server មិនទាន់បើកដំណើរការលើ PC');
                                      });
                                    },
                              icon: checkingBridge
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                    )
                                  : const Icon(Icons.sync_rounded, size: 16, color: Colors.black),
                              label: Text(
                                checkingBridge ? 'កំពុង Auto-Sync...' : 'ពិនិត្យ & ភ្ជាប់ឡើងវិញ (Auto-Sync)',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.cyanAccent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Section 3: App Auto-Update Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.cyanAccent.withOpacity(0.3),
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppTheme.cyanAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.system_update_rounded, color: AppTheme.cyanAccent, size: 18),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'កំណែអាប់ដេត (App Update)',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      'Version បច្ចុប្បន្ន: v${AppUpdateService.currentVersion}',
                                      style: TextStyle(fontSize: 10.5, color: AppTheme.cyanAccent),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'ពិនិត្យមើលកំណែអាប់ដេតថ្មីៗ និង Update ដោយស្វ័យប្រវត្តិតាមរយៈ Server ដោយមិនបាច់ដំឡើងសារជាថ្មីដោយដៃ។',
                            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _triggerCheckUpdate(sheetCtx),
                              icon: const Icon(Icons.cloud_sync_rounded, size: 16, color: Colors.black),
                              label: const Text(
                                'ពិនិត្យមើលកំណែថ្មី (Check for Updates)',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.cyanAccent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Section 4: App Footer Info
                    Center(
                      child: Column(
                        children: const [
                          Text(
                            'Trabekprey-DL Pro • Dev: Tong Chhunleng',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Version 2.5.0 • High-Speed Drama Downloader',
                            style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _triggerCheckUpdate(BuildContext? closeContext) async {
    if (closeContext != null && Navigator.canPop(closeContext)) {
      Navigator.pop(closeContext);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.cyanAccent),
            ),
            SizedBox(width: 10),
            Text('កំពុងពិនិត្យកំណែអាប់ដេតថ្មី...', style: TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: const Color(0xFF131E2E),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    try {
      final info = await AppUpdateService().checkForUpdate();
      if (!mounted) return;

      if (info.hasUpdate) {
        AppUpdateDialog.show(context, info);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.greenSuccess, size: 18),
                const SizedBox(width: 8),
                Text(
                  'កម្មវិធីរបស់អ្នកគឺជាកំណែចុងក្រោយបំផុតហើយ (v${info.currentVersion})',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF131E2E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('មិនអាចពិនិត្យកំណែអាប់ដេតបានទេ: $e'),
          backgroundColor: AppTheme.redDanger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

