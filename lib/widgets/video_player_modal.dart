import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';

class VideoPlayerModal extends StatefulWidget {
  final String filePathOrUrl;
  final String title;

  const VideoPlayerModal({
    super.key,
    required this.filePathOrUrl,
    required this.title,
  });

  @override
  State<VideoPlayerModal> createState() => _VideoPlayerModalState();
}

class _VideoPlayerModalState extends State<VideoPlayerModal> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() async {
    try {
      if (widget.filePathOrUrl.startsWith('http')) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.filePathOrUrl));
      } else {
        _controller = VideoPlayerController.file(File(widget.filePathOrUrl));
      }

      await _controller.initialize();
      _controller.play();
      _controller.setLooping(true);
      setState(() => _isInitialized = true);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textMuted, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Video Player Body
            AspectRatio(
              aspectRatio: _isInitialized ? _controller.value.aspectRatio : 16 / 9,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_isInitialized)
                    VideoPlayer(_controller)
                  else if (_error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'មិនអាចបើកវីដេអូបានទេ:\n$_error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.redDanger, fontSize: 12),
                        ),
                      ),
                    )
                  else
                    const Center(
                      child: CircularProgressIndicator(color: AppTheme.cyanAccent),
                    ),

                  // Play/Pause Overlay Tap
                  if (_isInitialized)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _controller.value.isPlaying ? _controller.pause() : _controller.play();
                        });
                      },
                      child: Container(
                        color: Colors.transparent,
                        child: Center(
                          child: AnimatedOpacity(
                            opacity: _controller.value.isPlaying ? 0.0 : 0.8,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow, size: 36, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Controls & Timeline
            if (_isInitialized)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ValueListenableBuilder(
                  valueListenable: _controller,
                  builder: (context, VideoPlayerValue value, _) {
                    final position = value.position;
                    final duration = value.duration;
                    return Column(
                      children: [
                        VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: AppTheme.cyanAccent,
                            bufferedColor: AppTheme.cardBorder,
                            backgroundColor: Colors.black38,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(position),
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
