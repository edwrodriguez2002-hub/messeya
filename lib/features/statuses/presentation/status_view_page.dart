import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/status_item.dart';
import '../data/statuses_repository.dart';
import 'status_video_player_page.dart';

class StatusViewPage extends ConsumerStatefulWidget {
  final List<StatusItem> statuses;
  final String userName;

  const StatusViewPage({
    super.key,
    required this.statuses,
    required this.userName,
  });

  @override
  ConsumerState<StatusViewPage> createState() => _StatusViewPageState();
}

class _StatusViewPageState extends ConsumerState<StatusViewPage> with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animController;
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _animController = AnimationController(vsync: this);
    
    _loadStatus(index: 0);

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStatus();
      }
    });
  }

  void _loadStatus({required int index, bool animate = false}) {
    _animController.stop();
    _animController.reset();
    
    // Duración: 5 segundos para imagen/texto, los videos se manejan distinto pero aquí simplificamos a 10s
    final duration = widget.statuses[index].mediaType == 'video' 
        ? const Duration(seconds: 15) 
        : const Duration(seconds: 5);
    
    _animController.duration = duration;
    _animController.forward();

    if (animate) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }

    _markAsViewed(index);
  }

  void _nextStatus() {
    if (_currentIndex < widget.statuses.length - 1) {
      setState(() {
        _currentIndex++;
        _loadStatus(index: _currentIndex, animate: true);
      });
    } else {
      Navigator.pop(context);
    }
  }

  void _previousStatus() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _loadStatus(index: _currentIndex, animate: true);
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _markAsViewed(int index) {
    if (index < widget.statuses.length) {
      ref.read(statusesRepositoryProvider).markViewed(widget.statuses[index].id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) => _animController.stop(), // PAUSAR AL MANTENER
        onLongPressEnd: (_) => _animController.forward(), // REANUDAR
        onTapDown: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < screenWidth / 3) {
            _previousStatus(); // TOQUE IZQUIERDA
          } else {
            _nextStatus(); // TOQUE DERECHA
          }
        },
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), // Desactivamos swipe manual para usar los toques laterales
              itemCount: widget.statuses.length,
              itemBuilder: (context, index) {
                return _buildStatusContent(widget.statuses[index]);
              },
            ),

            // BARRA DE PROGRESO TIPO WHATSAPP
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: List.generate(widget.statuses.length, (index) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: AnimatedBuilder(
                              animation: _animController,
                              builder: (context, child) {
                                double val = 0.0;
                                if (index < _currentIndex) val = 1.0;
                                if (index == _currentIndex) val = _animController.value;
                                return LinearProgressIndicator(
                                  value: val,
                                  backgroundColor: Colors.white.withOpacity(0.2),
                                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                                  minHeight: 2.5,
                                );
                              },
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // INFO DEL USUARIO
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundImage: widget.statuses[_currentIndex].userPhoto.isNotEmpty
                              ? NetworkImage(widget.statuses[_currentIndex].userPhoto)
                              : null,
                          child: widget.statuses[_currentIndex].userPhoto.isEmpty
                              ? Text(widget.userName[0])
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          widget.userName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusContent(StatusItem status) {
    if (status.mediaType == 'image') {
      return Center(child: Image.network(status.mediaUrl, fit: BoxFit.contain, width: double.infinity));
    } else if (status.mediaType == 'video') {
      return StatusVideoPlayerPage(videoUrl: status.mediaUrl, title: status.userName);
    } else {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF833AB4), Color(0xFFFD1D1D), Color(0xFFFCB045)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(
            status.text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }
}
