import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location/location.dart' as device_location;
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

final nearbyMeshServiceProvider = Provider<NearbyMeshService>((ref) {
  return NearbyMeshService();
});

final nearbyMeshStateProvider =
    StateNotifierProvider<NearbyMeshStateController, NearbyMeshState>((ref) {
  return NearbyMeshStateController(ref.watch(nearbyMeshServiceProvider));
});

class NearbyMeshState {
  const NearbyMeshState({
    this.running = false,
    this.connectedEndpoints = const {},
    this.discoveredEndpoints = const {},
    this.lastEvent = '',
  });

  final bool running;
  final Set<String> connectedEndpoints;
  final Map<String, String> discoveredEndpoints;
  final String lastEvent;

  NearbyMeshState copyWith({
    bool? running,
    Set<String>? connectedEndpoints,
    Map<String, String>? discoveredEndpoints,
    String? lastEvent,
  }) {
    return NearbyMeshState(
      running: running ?? this.running,
      connectedEndpoints: connectedEndpoints ?? this.connectedEndpoints,
      discoveredEndpoints: discoveredEndpoints ?? this.discoveredEndpoints,
      lastEvent: lastEvent ?? this.lastEvent,
    );
  }
}

class NearbyMeshStateController extends StateNotifier<NearbyMeshState> {
  NearbyMeshStateController(this._service) : super(const NearbyMeshState()) {
    _service.stateStream.listen((value) => state = value);
  }

  final NearbyMeshService _service;
}

class NearbyMeshService {
  final Nearby _nearby = Nearby();
  final _stateController = StreamController<NearbyMeshState>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  NearbyMeshState _state = const NearbyMeshState();
  bool _initialized = false;
  String _userName = 'Messeya';

  Stream<NearbyMeshState> get stateStream => _stateController.stream;
  Stream<Map<String, dynamic>> get receivedMessages =>
      _messageController.stream;
  NearbyMeshState get currentState => _state;

  Future<void> initialize({required String userName}) async {
    _userName = userName;
    if (_initialized) return;
    
    try {
      final granted = await _ensurePermissions();
      if (!granted) {
        _emit(_state.copyWith(lastEvent: 'Permisos Nearby pendientes.'));
        return;
      }
      _initialized = true;
      await _start();
    } catch (e) {
      debugPrint('Error inicializando Nearby Mesh: $e');
      _emit(_state.copyWith(lastEvent: 'Error al iniciar red local.'));
    }
  }

  Future<void> stop() async {
    try {
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
      await _nearby.stopAllEndpoints();
    } catch (_) {}
    
    _initialized = false;
    _emit(
      _state.copyWith(
        running: false,
        connectedEndpoints: {},
        discoveredEndpoints: {},
        lastEvent: 'Nearby detenido',
      ),
    );
  }

  Future<int> sendJsonBroadcast(Map<String, dynamic> payload) async {
    if (_state.connectedEndpoints.isEmpty) return 0;
    
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    var sentCount = 0;
    
    for (final endpoint in _state.connectedEndpoints) {
      try {
        await _nearby.sendBytesPayload(endpoint, bytes);
        sentCount++;
      } catch (e) {
        debugPrint('Error enviando a $endpoint: $e');
      }
    }
    return sentCount;
  }

  Future<bool> _ensurePermissions() async {
    try {
      final location = device_location.Location();
      var serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
      }

      final permissions = <Permission>[
        Permission.location,
        Permission.bluetooth,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ];

      final results = await permissions.request();
      return serviceEnabled &&
          results.values.every(
            (status) => status.isGranted || status.isLimited,
          );
    } catch (e) {
      debugPrint('Error solicitando permisos: $e');
      return false;
    }
  }

  Future<void> _start() async {
    try {
      // Intentar iniciar publicidad
      await _nearby.startAdvertising(
        _userName,
        Strategy.P2P_CLUSTER,
        serviceId: 'com.messeya.chat.hybrid',
        onConnectionInitiated: (endpointId, info) async {
          await _nearby.acceptConnection(
            endpointId,
            onPayLoadRecieved: _onPayloadReceived,
          );
        },
        onConnectionResult: (endpointId, status) {
          if (status == Status.CONNECTED) {
            final connected = {..._state.connectedEndpoints, endpointId};
            _emit(
              _state.copyWith(
                running: true,
                connectedEndpoints: connected,
                lastEvent: 'Conectado con $endpointId',
              ),
            );
          }
        },
        onDisconnected: (endpointId) {
          final connected = {..._state.connectedEndpoints}..remove(endpointId);
          _emit(
            _state.copyWith(
              connectedEndpoints: connected,
              lastEvent: 'Desconectado de $endpointId',
            ),
          );
        },
      );

      // Intentar iniciar descubrimiento
      await _nearby.startDiscovery(
        _userName,
        Strategy.P2P_CLUSTER,
        serviceId: 'com.messeya.chat.hybrid',
        onEndpointFound: (endpointId, endpointName, serviceId) async {
          final discovered = {
            ..._state.discoveredEndpoints,
            endpointId: endpointName
          };
          _emit(
            _state.copyWith(
              running: true,
              discoveredEndpoints: discovered,
              lastEvent: 'Nodo encontrado: $endpointName',
            ),
          );
          
          try {
            await _nearby.requestConnection(
              _userName,
              endpointId,
              onConnectionInitiated: (id, info) async {
                await _nearby.acceptConnection(
                  id,
                  onPayLoadRecieved: _onPayloadReceived,
                );
              },
              onConnectionResult: (id, status) {
                if (status == Status.CONNECTED) {
                  final connected = {..._state.connectedEndpoints, id};
                  _emit(
                    _state.copyWith(
                      running: true,
                      connectedEndpoints: connected,
                      lastEvent: 'Canal mesh activo con $id',
                    ),
                  );
                }
              },
              onDisconnected: (id) {
                final connected = {..._state.connectedEndpoints}..remove(id);
                _emit(_state.copyWith(connectedEndpoints: connected));
              },
            );
          } catch (e) {
            debugPrint('Error al solicitar conexion: $e');
          }
        },
        onEndpointLost: (endpointId) {
          final discovered = {..._state.discoveredEndpoints}..remove(endpointId);
          _emit(_state.copyWith(discoveredEndpoints: discovered));
        },
      );

      _emit(_state.copyWith(running: true, lastEvent: 'Nearby activo'));
    } catch (e) {
      debugPrint('Error en el motor mesh: $e');
      _emit(_state.copyWith(running: false, lastEvent: 'Error en motor mesh'));
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;
    try {
      final decoded = jsonDecode(utf8.decode(payload.bytes!));
      if (decoded is Map<String, dynamic>) {
        _messageController.add({
          ...decoded,
          'endpointId': endpointId,
        });
      }
    } catch (_) {
      _emit(_state.copyWith(lastEvent: 'Payload invalido recibido.'));
    }
  }

  void _emit(NearbyMeshState state) {
    _state = state;
    _stateController.add(state);
  }
}
