import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_trimmer/video_trimmer.dart';

class MediaComposerResult {
  const MediaComposerResult({
    required this.file,
    required this.caption,
    required this.viewOnce,
  });

  final File file;
  final String caption;
  final bool viewOnce;
}

class MediaComposerPage extends StatefulWidget {
  const MediaComposerPage({
    super.key,
    required this.file,
    required this.type,
    this.initialCaption = '',
  });

  final File file;
  final String type;
  final String initialCaption;

  @override
  State<MediaComposerPage> createState() => _MediaComposerPageState();
}

class _MediaComposerPageState extends State<MediaComposerPage> {
  static const List<Color> _palette = <Color>[
    Color(0xFF60A5FA),
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFF22C55E),
    Color(0xFFFFFFFF),
    Color(0xFF111827),
  ];

  final _imageEditorKey = GlobalKey();
  late final TextEditingController _captionController;
  final List<_DrawStroke> _strokes = <_DrawStroke>[];
  final List<_DrawStroke> _redoStrokes = <_DrawStroke>[];
  _DrawStroke? _activeStroke;

  late File _workingFile;
  Trimmer? _trimmer;
  bool _viewOnce = false;
  bool _drawMode = false;
  bool _saving = false;
  double _videoStart = 0.0;
  double _videoEnd = 0.0;
  double _imageAspectRatio = 1.0;
  double _brushWidth = 4.0;
  Color _brushColor = const Color(0xFF60A5FA);

  bool get _isVideo => widget.type == 'video';
  bool get _isImage => widget.type == 'image';

  @override
  void initState() {
    super.initState();
    _workingFile = widget.file;
    _captionController = TextEditingController(text: widget.initialCaption);
    if (_isImage) {
      _loadImageMetadata();
    } else if (_isVideo) {
      _loadVideo();
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _loadImageMetadata() async {
    final bytes = await _workingFile.readAsBytes();
    final image = await decodeImageFromList(bytes);
    if (!mounted) return;
    setState(() {
      _imageAspectRatio = image.width == 0 ? 1.0 : image.width / image.height;
    });
  }

  Future<void> _loadVideo() async {
    final trimmer = Trimmer();
    await trimmer.loadVideo(videoFile: _workingFile);
    if (!mounted) return;
    setState(() {
      _trimmer = trimmer;
      _videoStart = 0.0;
      _videoEnd = 0.0;
    });
  }

  Future<void> _cropImage() async {
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: _workingFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Recortar foto',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: const Color(0xFF60A5FA),
            dimmedLayerColor: Colors.black54,
            cropFrameColor: const Color(0xFF60A5FA),
            cropGridColor: Colors.white24,
            hideBottomControls: false,
            lockAspectRatio: false,
            initAspectRatio: CropAspectRatioPreset.original,
          ),
        ],
      );
      if (cropped == null || !mounted) return;
      setState(() {
        _workingFile = File(cropped.path);
        _strokes.clear();
        _redoStrokes.clear();
        _activeStroke = null;
      });
      await _loadImageMetadata();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No pudimos recortar la foto. ${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  Future<void> _trimVideo() async {
    final trimmer = _trimmer;
    if (trimmer == null) return;
    setState(() => _saving = true);
    try {
      final completer = Completer<String?>();
      await trimmer.saveTrimmedVideo(
        startValue: _videoStart,
        endValue: _videoEnd,
        onSave: (outputPath) {
          if (!completer.isCompleted) {
            completer.complete(outputPath);
          }
        },
      );
      final outputPath = await completer.future;
      if (outputPath == null || outputPath.isEmpty || !mounted) return;
      setState(() => _workingFile = File(outputPath));
      await _loadVideo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video recortado.')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<File> _exportEditedImageIfNeeded() async {
    if (!_isImage || _strokes.isEmpty) return _workingFile;
    final boundary = _imageEditorKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return _workingFile;

    final image = await boundary.toImage(pixelRatio: 2.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return _workingFile;
    final tempDir = await getTemporaryDirectory();
    final output = File(
      '${tempDir.path}/messeya_edited_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await output.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return output;
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      final file = await _exportEditedImageIfNeeded();
      if (!mounted) return;
      Navigator.of(context).pop(
        MediaComposerResult(
          file: file,
          caption: _captionController.text.trim(),
          viewOnce: _viewOnce,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _startStroke(DragStartDetails details) {
    if (!_drawMode) return;
    final stroke = _DrawStroke(
      color: _brushColor,
      width: _brushWidth,
      points: <Offset>[details.localPosition],
    );
    setState(() {
      _activeStroke = stroke;
      _strokes.add(stroke);
      _redoStrokes.clear();
    });
  }

  void _appendStroke(DragUpdateDetails details) {
    final stroke = _activeStroke;
    if (!_drawMode || stroke == null) return;
    setState(() {
      stroke.points.add(details.localPosition);
    });
  }

  void _endStroke(DragEndDetails details) {
    _activeStroke = null;
  }

  void _undoStroke() {
    if (_strokes.isEmpty) return;
    setState(() {
      final removed = _strokes.removeLast();
      _redoStrokes.add(removed);
    });
  }

  void _redoStroke() {
    if (_redoStrokes.isEmpty) return;
    setState(() {
      final restored = _redoStrokes.removeLast();
      _strokes.add(restored);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          _isVideo ? 'Editar video' : 'Editar foto',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _isVideo ? _buildVideoEditor() : _buildImageEditor(),
              ),
            ),
            _buildToolbar(context),
            _buildBottomComposer(context),
          ],
        ),
      ),
    );
  }

  Widget _buildImageEditor() {
    return Center(
      child: AspectRatio(
        aspectRatio: _imageAspectRatio,
        child: RepaintBoundary(
          key: _imageEditorKey,
          child: GestureDetector(
            onPanStart: _drawMode ? _startStroke : null,
            onPanUpdate: _drawMode ? _appendStroke : null,
            onPanEnd: _drawMode ? _endStroke : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  _workingFile,
                  fit: BoxFit.contain,
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _ImageDrawPainter(_strokes),
                    size: Size.infinite,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoEditor() {
    final trimmer = _trimmer;
    if (trimmer == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: VideoViewer(trimmer: trimmer),
        ),
        const SizedBox(height: 12),
        TrimViewer(
          trimmer: trimmer,
          viewerHeight: 50,
          viewerWidth: MediaQuery.of(context).size.width - 32,
          maxVideoLength: const Duration(minutes: 2),
          onChangeStart: (value) => _videoStart = value,
          onChangeEnd: (value) => _videoEnd = value,
          onChangePlaybackState: (_) {},
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_isImage)
            FilledButton.tonalIcon(
              onPressed: _saving ? null : _cropImage,
              icon: const Icon(Icons.crop_rounded),
              label: const Text('Recortar'),
            ),
          if (_isImage)
            FilledButton.tonalIcon(
              onPressed:
                  _saving ? null : () => setState(() => _drawMode = !_drawMode),
              icon: Icon(
                _drawMode ? Icons.brush_rounded : Icons.draw_outlined,
              ),
              label: Text(_drawMode ? 'Dejar de dibujar' : 'Rayar foto'),
            ),
          if (_isImage)
            FilledButton.tonalIcon(
              onPressed: _saving || _strokes.isEmpty
                  ? null
                  : () => setState(() {
                        _strokes.clear();
                        _redoStrokes.clear();
                      }),
              icon: const Icon(Icons.layers_clear_rounded),
              label: const Text('Borrar trazos'),
            ),
          if (_isImage)
            FilledButton.tonalIcon(
              onPressed: _saving || _strokes.isEmpty ? null : _undoStroke,
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Deshacer'),
            ),
          if (_isImage)
            FilledButton.tonalIcon(
              onPressed: _saving || _redoStrokes.isEmpty ? null : _redoStroke,
              icon: const Icon(Icons.redo_rounded),
              label: const Text('Rehacer'),
            ),
          if (_isVideo)
            FilledButton.tonalIcon(
              onPressed: _saving ? null : _trimVideo,
              icon: const Icon(Icons.content_cut_rounded),
              label: const Text('Recortar video'),
            ),
          if (_isImage) _buildBrushControls(),
        ],
      ),
    );
  }

  Widget _buildBrushControls() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Pincel',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _palette.map((color) {
              final selected = color == _brushColor;
              return InkWell(
                onTap:
                    _saving ? null : () => setState(() => _brushColor = color),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          selected ? const Color(0xFF60A5FA) : Colors.white24,
                      width: selected ? 3 : 1,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Grosor: ${_brushWidth.toStringAsFixed(1)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Slider(
                  value: _brushWidth,
                  min: 2,
                  max: 14,
                  divisions: 12,
                  label: _brushWidth.toStringAsFixed(1),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _brushWidth = value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomComposer(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.88),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: _captionController,
            style: const TextStyle(color: Colors.white),
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              hintText: 'Escribe un mensaje para acompanarlo',
              hintStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _viewOnce,
            onChanged:
                _saving ? null : (value) => setState(() => _viewOnce = value),
            activeThumbColor: const Color(0xFF60A5FA),
            title: const Text(
              'Ver una sola vez',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'La foto o el video se mostrara solo una vez al receptor.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _finish,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_isVideo ? 'Enviar video' : 'Enviar foto'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawStroke {
  _DrawStroke({
    required this.color,
    required this.width,
    required this.points,
  });

  final Color color;
  final double width;
  final List<Offset> points;
}

class _ImageDrawPainter extends CustomPainter {
  const _ImageDrawPainter(this.strokes);

  final List<_DrawStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ImageDrawPainter oldDelegate) {
    return true;
  }
}
