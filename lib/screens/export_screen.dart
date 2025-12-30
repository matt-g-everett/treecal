import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive_io.dart';
import 'package:share_plus/share_plus.dart';
import '../services/capture_service.dart';

class ExportScreen extends StatelessWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final capture = Provider.of<CaptureService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Captured Images'),
      ),
      body: FutureBuilder<List<String>>(
        future: capture.getCapturedPositions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No captures yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Start a capture from the home screen',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final positions = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Summary
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Captured Positions: ${positions.length}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total LEDs: ${capture.totalLEDs}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Export All Button
              ElevatedButton.icon(
                onPressed: () => _exportAll(context, capture),
                icon: const Icon(Icons.archive),
                label: const Text('Export All as ZIP'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
              
              const SizedBox(height: 24),
              
              Text(
                'Camera Positions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),

              // Position Cards
              ...positions.map((position) => _PositionCard(
                    position: position,
                    capture: capture,
                  )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportAll(BuildContext context, CaptureService capture) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Creating archive...')),
      );

      final captureDir = await capture.getCaptureDirectory();
      final positions = await capture.getCapturedPositions();

      // Create zip archive
      final encoder = ZipFileEncoder();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final zipPath = path.join(captureDir, 'led_captures_$timestamp.zip');
      
      encoder.create(zipPath);

      for (final position in positions) {
        final positionDir = Directory(path.join(captureDir, position));
        final files = await positionDir
            .list()
            .where((entity) => entity is File && entity.path.endsWith('.jpg'))
            .toList();

        for (final file in files) {
          encoder.addFile(File(file.path));
        }
      }

      encoder.close();

      // Share the file
      await Share.shareXFiles(
        [XFile(zipPath)],
        subject: 'LED Captures',
        text: 'LED position mapping captures - ${positions.length} camera positions',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Archive created and ready to share')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating archive: $e')),
        );
      }
    }
  }
}

class _PositionCard extends StatelessWidget {
  final String position;
  final CaptureService capture;

  const _PositionCard({
    required this.position,
    required this.capture,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.camera_alt),
        title: Text(position),
        subtitle: FutureBuilder<int>(
          future: capture.getImageCount(position),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Text('${snapshot.data} images');
            }
            return const Text('Loading...');
          },
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FutureBuilder<int>(
                  future: capture.getImageCount(position),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox.shrink();

                    final count = snapshot.data!;
                    final progress = count / capture.totalLEDs;

                    return Column(
                      children: [
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$count / ${capture.totalLEDs} LEDs captured (${(progress * 100).toStringAsFixed(1)}%)',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _viewImages(context),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('View'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _sharePosition(context),
                        icon: const Icon(Icons.share),
                        label: const Text('Share'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deletePosition(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _viewImages(BuildContext context) async {
    final captureDir = await capture.getCaptureDirectory();
    final positionDir = Directory(path.join(captureDir, position));
    
    final files = await positionDir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.jpg'))
        .map((entity) => File(entity.path))
        .toList();

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImageGalleryScreen(
            title: position,
            images: files,
          ),
        ),
      );
    }
  }

  Future<void> _sharePosition(BuildContext context) async {
    try {
      final captureDir = await capture.getCaptureDirectory();
      final positionDir = Directory(path.join(captureDir, position));
      
      final files = await positionDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.jpg'))
          .map((entity) => XFile(entity.path))
          .toList();

      if (files.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No images to share')),
          );
        }
        return;
      }

      await Share.shareXFiles(
        files,
        subject: 'LED Captures - $position',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing: $e')),
        );
      }
    }
  }

  Future<void> _deletePosition(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Position'),
        content: Text('Delete all images from $position?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final captureDir = await capture.getCaptureDirectory();
      final positionDir = Directory(path.join(captureDir, position));
      
      await positionDir.delete(recursive: true);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $position')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting: $e')),
        );
      }
    }
  }
}

class ImageGalleryScreen extends StatelessWidget {
  final String title;
  final List<File> images;

  const ImageGalleryScreen({
    super.key,
    required this.title,
    required this.images,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: images.length,
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FullImageScreen(
                    image: images[index],
                    title: path.basename(images[index].path),
                  ),
                ),
              );
            },
            child: Image.file(
              images[index],
              fit: BoxFit.cover,
            ),
          );
        },
      ),
    );
  }
}

class FullImageScreen extends StatelessWidget {
  final File image;
  final String title;

  const FullImageScreen({
    super.key,
    required this.image,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(image),
        ),
      ),
    );
  }
}
