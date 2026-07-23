import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../models/device.dart';
import '../../services/crypto_service.dart';
import '../../state/account_session.dart';
import '../../state/providers.dart';

/// Shows a device's decrypted location history on an OpenStreetMap tile map
/// (never Google Maps — that pulls in Play Services). Decryption happens
/// entirely on-device using the in-memory account session's code + the
/// account salt; the server only ever handed over ciphertext.
class DeviceHistoryScreen extends ConsumerStatefulWidget {
  final Device device;

  const DeviceHistoryScreen({super.key, required this.device});

  @override
  ConsumerState<DeviceHistoryScreen> createState() => _DeviceHistoryScreenState();
}

class _DeviceHistoryScreenState extends ConsumerState<DeviceHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<LocationSample> _samples = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(accountSessionProvider);
    if (session == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final crypto = ref.read(cryptoServiceProvider);
      final key = await crypto.deriveKey(code: session.code, saltBase64: session.saltBase64);

      final points = await api.listLocations(sessionToken: session.sessionToken, deviceId: widget.device.id);
      final samples = <LocationSample>[];
      for (final point in points) {
        try {
          final json = await crypto.decrypt(point.ciphertextBlob, key);
          samples.add(LocationSample.fromJson(json));
        } catch (_) {
          // Skip a point that fails to decrypt/authenticate rather than
          // aborting the whole history load.
        }
      }
      setState(() => _samples = samples);
    } catch (e) {
      setState(() => _error = 'Could not load history: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _ringDevice() async {
    final session = ref.read(accountSessionProvider);
    if (session == null) return;
    final api = ref.read(apiClientProvider);
    await api.queueRing(sessionToken: session.sessionToken, deviceId: widget.device.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sound queued — it will play next time this device checks in (within 5 min).')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = _samples.map((s) => LatLng(s.latitude, s.longitude)).toList();
    final latest = _samples.isNotEmpty ? _samples.last : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.label),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ringDevice,
        icon: const Icon(Icons.volume_up),
        label: const Text('Play sound'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : points.isEmpty
                  ? const Center(child: Text('No location samples yet.'))
                  : Column(
                      children: [
                        if (latest != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text('Last seen: ${latest.capturedAt.toLocal()}'),
                          ),
                        Expanded(
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: LatLng(latest!.latitude, latest.longitude),
                              initialZoom: 15,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'nl.hiddebalestra.findmyandroid',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(latest.latitude, latest.longitude),
                                    width: 40,
                                    height: 40,
                                    child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
                                  ),
                                ],
                              ),
                              PolylineLayer(
                                polylines: [
                                  Polyline(points: points, strokeWidth: 3, color: Colors.blueAccent),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }
}
