import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../app/theme.dart';
import '../core/classify.dart';
import '../core/models.dart';
import '../native.dart';
import 'soft.dart';

/// Shows the preview for any file: image, video thumbnail, or an extension tile.
class MediaThumb extends StatelessWidget {
  final FileEntry entry;
  final int cacheWidth;
  final bool showPlay;
  final BoxFit fit;

  const MediaThumb({
    super.key,
    required this.entry,
    this.cacheWidth = 300,
    this.showPlay = false,
    this.fit = BoxFit.cover,
  });

  Widget _placeholder(BuildContext context, IconData icon) {
    final p = context.soft;
    return Container(
      color: p.pressed,
      alignment: Alignment.center,
      child: Icon(icon, color: p.muted, size: 32),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    switch (entry.kind) {
      case Kind.image:
        return ColoredBox(
          color: p.pressed,
          child: Image.file(
          File(entry.path),
          fit: fit,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              _placeholder(context, Icons.broken_image_outlined),
        ));
      case Kind.video:
        return FutureBuilder<Uint8List?>(
          future: ThumbCache.get(entry.path),
          builder: (context, snap) {
            final bytes = snap.data;
            final base = bytes != null
                ? Image.memory(bytes, fit: fit, gaplessPlayback: true)
                : _placeholder(context, Icons.videocam_outlined);
            if (!showPlay) return base;
            return Stack(
              fit: StackFit.expand,
              children: [
                base,
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: raisedDeco(p, circle: true),
                    child: Icon(Icons.play_arrow_rounded, color: p.text, size: 32),
                  ),
                ),
              ],
            );
          },
        );
      case Kind.other:
        return Container(
          color: p.pressed,
          alignment: Alignment.center,
          child: Text(
            extLabel(entry.ext),
            style: ts(context, 13, weight: FontWeight.w500, color: p.muted),
          ),
        );
    }
  }
}

class VideoPage extends StatefulWidget {
  final String path;

  const VideoPage({super.key, required this.path});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _failed
                  ? const Text('Cannot play this video',
                      style: TextStyle(color: Colors.white70))
                  : !_ready
                      ? const CircularProgressIndicator(color: Colors.white70)
                      : GestureDetector(
                          onTap: () => setState(() {
                            _controller.value.isPlaying
                                ? _controller.pause()
                                : _controller.play();
                          }),
                          child: AspectRatio(
                            aspectRatio: _controller.value.aspectRatio,
                            child: VideoPlayer(_controller),
                          ),
                        ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (_ready)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
