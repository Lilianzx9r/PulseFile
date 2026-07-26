// lib/widgets/image_viewer_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../utils/open_external.dart';

class ImageViewerScreen extends StatelessWidget {
  final File file;
  const ImageViewerScreen({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(p.basename(file.path), overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Ouvrir avec…',
            onPressed: () => openFileExternally(file.path),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.file(file, errorBuilder: (context, error, stack) =>
              const Center(child: Icon(Icons.broken_image_outlined,
                  color: Colors.white54, size: 64))),
        ),
      ),
    );
  }
}
