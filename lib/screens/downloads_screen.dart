import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/drama_models.dart';
import '../services/download_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/video_player_modal.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DownloadManager _dm = DownloadManager.instance;
  String _storagePath = 'កំពុងពិនិត្យ...';
  final Set<String> _expandedActiveFolders = {};
  final Set<String> _expandedCompletedFolders = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStorageDir();
    _dm.scanStorageForCompletedTasks();
  }

  void _loadStorageDir() async {
    final dir = await _dm.getBaseStorageDir();
    if (mounted) {
      setState(() => _storagePath = dir.path);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _playVideo(String filePath, String title) {
    showDialog(
      context: context,
      builder: (_) => VideoPlayerModal(
        filePathOrUrl: filePath,
        title: title,
      ),
    );
  }

  void _shareVideo(String filePath) {
    SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath)],
        text: 'ទាញយកតាមរយៈ Trabekprey-DL Pro',
      ),
    );
  }

  Future<void> _applyFolder(String folderPath) async {
    final isWritable = await _dm.testDirectoryWritable(folderPath);
    if (!isWritable) {
      final granted = await _dm.isManageStorageGranted();
      if (!granted && mounted) {
        _showPermissionDialog();
        return;
      }
    }

    final success = await _dm.setCustomBaseDir(folderPath);
    if (mounted) {
      if (success) {
        setState(() => _storagePath = folderPath);
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.greenSuccess, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'បានប្ដូរទីតាំងរក្សាទុកទៅ:\n$folderPath',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF131E2E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('មិនអាចសរសេរចូល Folder នេះបានទេ (Permission Denied)'),
            backgroundColor: AppTheme.redDanger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131D2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.folder_shared_rounded, color: AppTheme.cyanAccent),
            SizedBox(width: 10),
            Text(
              'ទាមទារសិទ្ធិ Storage',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        content: const Text(
          'ដើម្បីរក្សាទុកវីដេអូទៅកាន់ Folder ខាងក្រៅ (Movies, Download) ក្នុងទូរស័ព្ទ Android 11+ សូមអនុញ្ញាតសិទ្ធិ "All files access" (គ្រប់គ្រងឯកសារទាំងអស់) នៅក្នុង Settings។',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('បោះបង់', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.cyanAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _dm.openStorageSettings();
            },
            child: const Text(
              'បើក Settings',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showFolderSelectionSheet(BuildContext context) async {
    String? appExtPath;
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        appExtPath = '${ext.path}/Trabekprey_DL';
      }
    } catch (_) {}

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1420),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.cyanAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.folder_special_rounded, color: AppTheme.cyanAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ជ្រើសរើសទីតាំងរក្សាទុក (Save Location)',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'ជ្រើសរើស Folder ក្នុងទូរស័ព្ទសម្រាប់ Save វីដេអូ',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Presets list
                _buildFolderOption(
                  icon: Icons.movie_filter_rounded,
                  iconColor: AppTheme.cyanAccent,
                  title: 'ថត Movies (ពេញនិយម - ក្នុង Gallery)',
                  subtitle: 'ងាយស្រួលមើលក្នុង Gallery ឬកម្មវិធីចាក់វីដេអូទូរស័ព្ទ',
                  targetPath: '/storage/emulated/0/Movies/Trabekprey_DL',
                  isSelected: _storagePath == '/storage/emulated/0/Movies/Trabekprey_DL',
                  onTap: () => _applyFolder('/storage/emulated/0/Movies/Trabekprey_DL'),
                ),
                const SizedBox(height: 10),

                _buildFolderOption(
                  icon: Icons.download_for_offline_rounded,
                  iconColor: AppTheme.amberWarning,
                  title: 'ថត Download (ស្តង់ដារទូរស័ព្ទ)',
                  subtitle: 'នៅក្នុងថតទាញយក Download របស់ទូរស័ព្ទ',
                  targetPath: '/storage/emulated/0/Download/Trabekprey_DL',
                  isSelected: _storagePath == '/storage/emulated/0/Download/Trabekprey_DL',
                  onTap: () => _applyFolder('/storage/emulated/0/Download/Trabekprey_DL'),
                ),
                const SizedBox(height: 10),

                _buildFolderOption(
                  icon: Icons.photo_library_rounded,
                  iconColor: const Color(0xFFFF6584),
                  title: 'ថត DCIM (Camera & Videos)',
                  subtitle: 'នៅក្នុង DCIM Albums របស់ទូរស័ព្ទ',
                  targetPath: '/storage/emulated/0/DCIM/Trabekprey_DL',
                  isSelected: _storagePath == '/storage/emulated/0/DCIM/Trabekprey_DL',
                  onTap: () => _applyFolder('/storage/emulated/0/DCIM/Trabekprey_DL'),
                ),
                const SizedBox(height: 10),

                if (appExtPath != null) ...[
                  _buildFolderOption(
                    icon: Icons.phone_android_rounded,
                    iconColor: Colors.blueGrey,
                    title: 'ថតខាងក្នុង App (Internal Storage)',
                    subtitle: 'សុវត្ថិភាព មិនប៉ះពាល់ Folder ផ្សេង',
                    targetPath: appExtPath,
                    isSelected: _storagePath == appExtPath,
                    onTap: () => _applyFolder(appExtPath!),
                  ),
                  const SizedBox(height: 10),
                ],

                // Custom Directory Picker Button
                _buildFolderOption(
                  icon: Icons.create_new_folder_rounded,
                  iconColor: AppTheme.greenSuccess,
                  title: 'រើស Folder ផ្ទាល់ខ្លួន ឬ SD Card...',
                  subtitle: 'ចុចដើម្បីបើក File Manager រើស Folder ណាមួយតាមចិត្ត',
                  targetPath: '',
                  isSelected: false,
                  isCustomPicker: true,
                  onTap: () async {
                    try {
                      final selectedDir = await FilePicker.getDirectoryPath(
                        dialogTitle: 'ជ្រើសរើស Folder សម្រាប់ Save វីដេអូ',
                      );
                      if (selectedDir != null && selectedDir.isNotEmpty) {
                        final customTarget = '$selectedDir/Trabekprey_DL';
                        await _applyFolder(customTarget);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('មិនអាចបើក Folder Picker បានទេ: $e'),
                            backgroundColor: AppTheme.redDanger,
                          ),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFolderOption({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String targetPath,
    required bool isSelected,
    bool isCustomPicker = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.cyanAccent.withOpacity(0.08) : const Color(0xFF131C2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.cyanAccent : AppTheme.cardBorder,
            width: isSelected ? 1.5 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppTheme.cyanAccent : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  if (targetPath.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      targetPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: isSelected ? AppTheme.cyanAccent.withOpacity(0.7) : AppTheme.textMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isSelected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.cyanAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, size: 14, color: AppTheme.cyanAccent),
                    SizedBox(width: 4),
                    Text(
                      'សកម្ម',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
                    ),
                  ],
                ),
              )
            else if (isCustomPicker)
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textMuted)
            else
              const Icon(Icons.radio_button_unchecked, size: 18, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _dm,
      builder: (context, _) {
        // Group all tasks by drama title
        final Map<String, DramaFolderGroup> allGroups = {};
        for (final task in _dm.tasks) {
          final title = task.dramaTitle.trim().isNotEmpty ? task.dramaTitle.trim() : 'Drama_${task.taskId}';
          if (!allGroups.containsKey(title)) {
            allGroups[title] = DramaFolderGroup(
              key: title,
              title: title,
              coverUrl: task.dramaCover,
              platform: task.platform,
              tasks: [],
            );
          }
          allGroups[title]!.tasks.add(task);
        }

        // Active groups have at least 1 task still active (downloading/pending/resolving/paused/failed)
        final activeGroups = allGroups.values.where((g) => g.activeTasks.isNotEmpty).toList();

        // Completed groups have at least 1 completed task
        final completedGroups = allGroups.values.where((g) => g.completedTasks.isNotEmpty).toList();

        final totalActiveEpisodes = activeGroups.fold<int>(0, (sum, g) => sum + g.activeTasks.length);
        final totalCompletedEpisodes = completedGroups.fold<int>(0, (sum, g) => sum + g.completedTasks.length);

        return Scaffold(
          backgroundColor: AppTheme.bgDark,
          appBar: AppBar(
            backgroundColor: AppTheme.bgElevated,
            title: const Text(
              'បញ្ជីទាញយក (Downloads)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            actions: [
              if (completedGroups.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.cleaning_services, size: 20, color: AppTheme.textSecondary),
                  tooltip: 'សម្អាតបញ្ជីដែលបានបញ្ចប់',
                  onPressed: () => _dm.clearCompleted(),
                ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.cyanAccent,
              labelColor: AppTheme.cyanAccent,
              unselectedLabelColor: AppTheme.textMuted,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('កំពុងដំណើរការ'),
                      if (totalActiveEpisodes > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.cyanAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$totalActiveEpisodes',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('បានបញ្ចប់'),
                      if (totalCompletedEpisodes > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.greenSuccess.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$totalCompletedEpisodes',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.greenSuccess),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              // Interactive Storage Folder Banner
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showFolderSelectionSheet(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F1522),
                    border: Border(bottom: BorderSide(color: AppTheme.cardBorder, width: 0.8)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_special, size: 20, color: AppTheme.cyanAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text(
                                  'ទីតាំងរក្សាទុកក្នុង Phone',
                                  style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.touch_app, size: 12, color: AppTheme.cyanAccent),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _storagePath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showFolderSelectionSheet(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.cyanAccent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.cyanAccent.withOpacity(0.4)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_location_alt_rounded, size: 13, color: AppTheme.cyanAccent),
                              SizedBox(width: 4),
                              Text(
                                'ប្ដូរទីតាំង',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Active Tab (Folders)
                    _buildActiveFoldersList(activeGroups),

                    // Completed Tab (Folders)
                    _buildCompletedFoldersList(completedGroups),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCoverImage(String coverUrl, {double width = 44, double height = 58, double radius = 8}) {
    Widget placeholder = Container(
      width: width,
      height: height,
      color: AppTheme.bgElevated,
      child: const Icon(Icons.movie_rounded, size: 20, color: AppTheme.textMuted),
    );

    if (coverUrl.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: placeholder,
      );
    }

    if (coverUrl.startsWith('/') || coverUrl.startsWith('file://')) {
      final filePath = coverUrl.replaceFirst('file://', '');
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(filePath),
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        coverUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }

  Widget _buildActiveFoldersList(List<DramaFolderGroup> groups) {
    if (groups.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done, size: 48, color: AppTheme.textMuted),
            SizedBox(height: 12),
            Text(
              'គ្មានការទាញយកកំពុងដំណើរការទេ',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final group = groups[index];
        return _buildActiveDramaFolderCard(group);
      },
    );
  }

  Widget _buildActiveDramaFolderCard(DramaFolderGroup group) {
    final isExpanded = _expandedActiveFolders.contains(group.key);
    final activeTasks = group.activeTasks;
    final downloadingTask = activeTasks.where((t) => t.status == TaskStatus.downloading).firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpanded ? AppTheme.cyanAccent.withOpacity(0.5) : AppTheme.cardBorder,
          width: isExpanded ? 1.2 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Folder Header Row
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Poster with Folder overlay badge
                Stack(
                  children: [
                    _buildCoverImage(group.coverUrl, width: 44, height: 58, radius: 8),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.folder_rounded, size: 12, color: AppTheme.cyanAccent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),

                // Title and Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: AppTheme.cyanAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              group.platform.name,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.cyanAccent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (downloadingTask != null) ...[
                            Expanded(
                              child: Text(
                                'កំពុងទាញ ${downloadingTask.episodeTitle} • ${downloadingTask.speedStr}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppTheme.cyanAccent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ] else ...[
                            Text(
                              activeTasks.any((t) => t.status == TaskStatus.paused) ? 'បានផ្អាក' : 'រង់ចាំ...',
                              style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Button at the end of Folder to view downloading episodes
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedActiveFolders.remove(group.key);
                      } else {
                        _expandedActiveFolders.add(group.key);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: isExpanded
                          ? AppTheme.cyanAccent.withOpacity(0.2)
                          : AppTheme.cyanAccent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.cyanAccent.withOpacity(isExpanded ? 0.6 : 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.playlist_play_rounded, size: 16, color: AppTheme.cyanAccent),
                        const SizedBox(width: 4),
                        Text(
                          'មើលភាគ (${activeTasks.length})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.cyanAccent,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: AppTheme.cyanAccent,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Processing Download bar under Folder with Episode Count (e.g. 1/200)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                Row(
                  children: [
                    // Progress indicator
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: group.overallProgress,
                          backgroundColor: const Color(0xFF1E2838),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.cyanAccent),
                          minHeight: 5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Progress Count at the end (e.g., 1/200)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.cyanAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '${group.completedCount}/${group.totalCount}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.cyanAccent,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ជោគជ័យ ${group.completedCount} ភាគ • នៅសល់ ${activeTasks.length} ភាគ',
                      style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                    ),
                    Text(
                      '${(group.overallProgress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Expanded Episode List
          if (isExpanded) ...[
            const Divider(height: 1, color: AppTheme.cardBorder),
            // Batch controls header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: const Color(0xFF0F1522),
              child: Row(
                children: [
                  Text(
                    'បញ្ជីភាគកំពុងដំណើរការ (${activeTasks.length})',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.pause, size: 14, color: AppTheme.amberWarning),
                    label: const Text('ផ្អាក', style: TextStyle(fontSize: 11, color: AppTheme.amberWarning)),
                    onPressed: () => _dm.pauseDrama(group.title),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.play_arrow, size: 14, color: AppTheme.cyanAccent),
                    label: const Text('បន្ត', style: TextStyle(fontSize: 11, color: AppTheme.cyanAccent)),
                    onPressed: () => _dm.resumeDrama(group.title),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.close, size: 16, color: AppTheme.redDanger),
                    tooltip: 'បោះបង់ទាំងអស់',
                    onPressed: () => _confirmCancelDrama(group.title),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.cardBorder),

            // List of individual episode tasks
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              itemCount: activeTasks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, epIndex) {
                final task = activeTasks[epIndex];
                return AnimatedBuilder(
                  animation: task,
                  builder: (context, _) => _buildActiveEpisodeTile(task),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveEpisodeTile(DownloadTask task) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1320),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.cardBorder.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.cyanAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  task.episodeTitle,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _getStatusLabel(task.status),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _getStatusColor(task.status),
                  ),
                ),
              ),
              _buildTaskActionButtons(task),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: task.progress / 100.0,
              backgroundColor: const Color(0xFF1E2838),
              valueColor: AlwaysStoppedAnimation<Color>(
                task.status == TaskStatus.failed ? AppTheme.redDanger : AppTheme.cyanAccent,
              ),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${task.progress.toStringAsFixed(1)}% (${(task.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB)',
                style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
              ),
              if (task.status == TaskStatus.downloading)
                Text(
                  '${task.speedStr} • ETA: ${task.etaStr}',
                  style: const TextStyle(fontSize: 10, color: AppTheme.cyanAccent, fontWeight: FontWeight.w500),
                )
              else if (task.status == TaskStatus.failed && task.error != null)
                Expanded(
                  child: Text(
                    task.error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 10, color: AppTheme.redDanger),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedFoldersList(List<DramaFolderGroup> groups) {
    if (groups.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined, size: 48, color: AppTheme.textMuted),
            SizedBox(height: 12),
            Text(
              'មិនទាន់មានវីដេអូដែលបានទាញយករួចរាល់ទេ',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final group = groups[index];
        return _buildCompletedDramaFolderCard(group);
      },
    );
  }

  Widget _buildCompletedDramaFolderCard(DramaFolderGroup group) {
    final isExpanded = _expandedCompletedFolders.contains(group.key);
    final completedTasks = List<DownloadTask>.from(group.completedTasks)
      ..sort((a, b) => a.episodeIndex.compareTo(b.episodeIndex));

    final samplePath = completedTasks.isNotEmpty ? completedTasks.first.outputPath : '';
    final folderName = samplePath.isNotEmpty ? p.basename(p.dirname(samplePath)) : group.title;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpanded ? AppTheme.greenSuccess.withOpacity(0.5) : AppTheme.cardBorder,
          width: isExpanded ? 1.2 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Completed Folder Header Row
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Poster with Green Folder overlay badge
                Stack(
                  children: [
                    _buildCoverImage(group.coverUrl, width: 44, height: 58, radius: 8),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.folder_special, size: 12, color: AppTheme.greenSuccess),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),

                // Title and Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${completedTasks.length} ភាគ • ${group.totalSizeStr}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.folder_open_rounded, size: 11, color: AppTheme.greenSuccess),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              folderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, color: AppTheme.greenSuccess),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Button at the end of Folder to view completed episodes
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedCompletedFolders.remove(group.key);
                      } else {
                        _expandedCompletedFolders.add(group.key);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: isExpanded
                          ? AppTheme.greenSuccess.withOpacity(0.2)
                          : AppTheme.greenSuccess.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.greenSuccess.withOpacity(isExpanded ? 0.6 : 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.video_library_rounded, size: 15, color: AppTheme.greenSuccess),
                        const SizedBox(width: 4),
                        Text(
                          'មើលភាគ (${completedTasks.length})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.greenSuccess,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: AppTheme.greenSuccess,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Expanded Episode List in Completed Tab
          if (isExpanded) ...[
            const Divider(height: 1, color: AppTheme.cardBorder),
            // Batch controls bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: const Color(0xFF0F1522),
              child: Row(
                children: [
                  Text(
                    'ភាគទាំងអស់ (${completedTasks.length})',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                  ),
                  const Spacer(),
                  if (completedTasks.isNotEmpty) ...[
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.play_circle_fill, size: 14, color: AppTheme.cyanAccent),
                      label: const Text('ចាក់ភាគទី ១', style: TextStyle(fontSize: 11, color: AppTheme.cyanAccent)),
                      onPressed: () => _playVideo(
                        completedTasks.first.outputPath,
                        '${group.title} - ${completedTasks.first.episodeTitle}',
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: AppTheme.redDanger),
                    tooltip: 'លុប Folder រឿងនេះ',
                    onPressed: () => _confirmDeleteDrama(group.title, completedTasks.length),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.cardBorder),

            // List of completed episodes
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              itemCount: completedTasks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, epIndex) {
                final task = completedTasks[epIndex];
                final sizeMb = (task.totalBytes / (1024 * 1024)).toStringAsFixed(1);

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C1320),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.cardBorder.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.greenSuccess.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          task.episodeTitle,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.greenSuccess,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$sizeMb MB',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                            Text(
                              p.basename(task.outputPath),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 9.5, color: AppTheme.textMuted, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                      // Play Button
                      IconButton(
                        icon: const Icon(Icons.play_circle_fill, color: AppTheme.cyanAccent, size: 30),
                        tooltip: 'ចាក់វីដេអូ (Play)',
                        onPressed: () => _playVideo(task.outputPath, '${task.dramaTitle} - ${task.episodeTitle}'),
                      ),
                      // Share Button
                      IconButton(
                        icon: const Icon(Icons.share, color: AppTheme.textSecondary, size: 18),
                        tooltip: 'ចែករំលែក (Share)',
                        onPressed: () => _shareVideo(task.outputPath),
                      ),
                      // Delete Button
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppTheme.textMuted, size: 18),
                        tooltip: 'លុបភាគនេះ',
                        onPressed: () => _confirmDeleteEpisode(task),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  void _confirmCancelDrama(String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131D2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppTheme.redDanger, size: 22),
            SizedBox(width: 8),
            Text('បោះបង់ការទាញយក', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        content: Text(
          'តើលោកអ្នកចង់បោះបង់ការទាញយករឿង "$title" មែនទេ?',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ត្រឡប់ក្រោយ', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.redDanger),
            onPressed: () {
              Navigator.pop(ctx);
              _dm.cancelDrama(title);
            },
            child: const Text('បោះបង់', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteDrama(String title, int count) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131D2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppTheme.redDanger, size: 22),
            SizedBox(width: 8),
            Text('លុប Folder រឿង', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        content: Text(
          'តើលោកអ្នកពិតជាចង់លុបរឿង "$title" ទាំងអស់ ($count ភាគ) ចេញពី Phone Storage មែនទេ?',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ទេ', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.redDanger),
            onPressed: () async {
              Navigator.pop(ctx);
              await _dm.deleteCompletedDrama(title, deleteFromDisk: true);
            },
            child: const Text('លុបចោល', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteEpisode(DownloadTask task) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131D2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: AppTheme.redDanger, size: 22),
            SizedBox(width: 8),
            Text('លុបភាគវីដេអូ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        content: Text(
          'តើលោកអ្នកចង់លុបភាគ "${task.episodeTitle}" មែនទេ?',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ទេ', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.redDanger),
            onPressed: () async {
              Navigator.pop(ctx);
              await _dm.deleteTaskAndFile(task.taskId, deleteFromDisk: true);
            },
            child: const Text('លុប', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskActionButtons(DownloadTask task) {
    if (task.status == TaskStatus.downloading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.pause, size: 20, color: AppTheme.amberWarning),
            onPressed: () => _dm.pauseTask(task.taskId),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: AppTheme.textMuted),
            onPressed: () => _dm.cancelTask(task.taskId),
          ),
        ],
      );
    } else if (task.status == TaskStatus.paused) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_arrow, size: 20, color: AppTheme.cyanAccent),
            onPressed: () => _dm.resumeTask(task.taskId),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: AppTheme.textMuted),
            onPressed: () => _dm.cancelTask(task.taskId),
          ),
        ],
      );
    } else if (task.status == TaskStatus.failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: AppTheme.cyanAccent),
            onPressed: () => _dm.retryTask(task.taskId),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.textMuted),
            onPressed: () => _dm.removeTask(task.taskId),
          ),
        ],
      );
    } else {
      return IconButton(
        icon: const Icon(Icons.close, size: 18, color: AppTheme.textMuted),
        onPressed: () => _dm.cancelTask(task.taskId),
      );
    }
  }

  String _getStatusLabel(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return 'រង់ចាំ...';
      case TaskStatus.resolving:
        return 'កំពុងទាញយក Link...';
      case TaskStatus.downloading:
        return 'កំពុងទាញយក';
      case TaskStatus.paused:
        return 'ផ្អាកជាបណ្ដោះអាសន្ន';
      case TaskStatus.completed:
        return 'បានបញ្ចប់';
      case TaskStatus.failed:
        return 'បរាជ័យ';
      case TaskStatus.cancelled:
        return 'បានបោះបង់';
    }
  }

  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return AppTheme.textMuted;
      case TaskStatus.resolving:
      case TaskStatus.downloading:
        return AppTheme.cyanAccent;
      case TaskStatus.paused:
        return AppTheme.amberWarning;
      case TaskStatus.completed:
        return AppTheme.greenSuccess;
      case TaskStatus.failed:
      case TaskStatus.cancelled:
        return AppTheme.redDanger;
    }
  }
}

class DramaFolderGroup {
  final String key;
  final String title;
  final String coverUrl;
  final PlatformType platform;
  final List<DownloadTask> tasks;

  DramaFolderGroup({
    required this.key,
    required this.title,
    required this.coverUrl,
    required this.platform,
    required this.tasks,
  });

  List<DownloadTask> get activeTasks => tasks
      .where((t) =>
          t.status == TaskStatus.downloading ||
          t.status == TaskStatus.pending ||
          t.status == TaskStatus.resolving ||
          t.status == TaskStatus.paused ||
          t.status == TaskStatus.failed)
      .toList();

  List<DownloadTask> get completedTasks =>
      tasks.where((t) => t.status == TaskStatus.completed).toList();

  int get completedCount => completedTasks.length;
  int get totalCount => tasks.length;

  double get overallProgress {
    if (tasks.isEmpty) return 0.0;
    double sum = 0.0;
    for (final t in tasks) {
      if (t.status == TaskStatus.completed) {
        sum += 1.0;
      } else if (t.status == TaskStatus.downloading) {
        sum += (t.progress / 100.0).clamp(0.0, 0.99);
      }
    }
    return (sum / tasks.length).clamp(0.0, 1.0);
  }

  int get totalBytes => tasks.fold(
      0, (sum, t) => sum + (t.status == TaskStatus.completed ? t.totalBytes : t.downloadedBytes));

  String get totalSizeStr {
    final mb = totalBytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }
}
