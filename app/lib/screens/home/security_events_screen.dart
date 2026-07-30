import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/device.dart';
import '../../state/account_session.dart';
import '../../state/providers.dart';

class _DecryptedEvent {
  final Uint8List? photoBytes;
  final double? lat;
  final double? lng;
  final DateTime capturedAt;

  const _DecryptedEvent({required this.capturedAt, this.photoBytes, this.lat, this.lng});
}

/// Shows this device's security-snapshot log (see SecurityCaptureService):
/// a front-camera photo and/or location captured after too many failed
/// account-code/TOTP attempts. Decryption happens entirely on-device, same
/// as location history — the server only ever handed over ciphertext.
class SecurityEventsScreen extends ConsumerStatefulWidget {
  final Device device;

  const SecurityEventsScreen({super.key, required this.device});

  @override
  ConsumerState<SecurityEventsScreen> createState() => _SecurityEventsScreenState();
}

class _SecurityEventsScreenState extends ConsumerState<SecurityEventsScreen> {
  bool _loading = true;
  String? _error;
  List<_DecryptedEvent> _events = [];

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

      final events = await api.listSecurityEvents(sessionToken: session.sessionToken, deviceId: widget.device.id);
      final decrypted = <_DecryptedEvent>[];
      for (final event in events) {
        Uint8List? photoBytes;
        double? lat;
        double? lng;

        if (event.photoCiphertext != null) {
          try {
            final photoBase64 = await crypto.decrypt(event.photoCiphertext!, key);
            photoBytes = base64Decode(photoBase64);
          } catch (_) {
            // Skip a photo that fails to decrypt/authenticate.
          }
        }
        if (event.locationCiphertext != null) {
          try {
            final json = jsonDecode(await crypto.decrypt(event.locationCiphertext!, key)) as Map<String, dynamic>;
            lat = (json['lat'] as num).toDouble();
            lng = (json['lng'] as num).toDouble();
          } catch (_) {
            // Skip a location that fails to decrypt/authenticate.
          }
        }
        if (photoBytes != null || lat != null) {
          decrypted.add(_DecryptedEvent(capturedAt: event.capturedAt, photoBytes: photoBytes, lat: lat, lng: lng));
        }
      }
      setState(() => _events = decrypted);
    } catch (e) {
      setState(() => _error = 'Could not load security events: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.device.label} — Security log'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _events.isEmpty
                  ? const Center(child: Text('No security events logged for this device.'))
                  : ListView.builder(
                      itemCount: _events.length,
                      itemBuilder: (context, index) {
                        final event = _events[index];
                        return Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (event.photoBytes != null)
                                Image.memory(event.photoBytes!, fit: BoxFit.cover),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      event.capturedAt.toLocal().toString(),
                                      style: Theme.of(context).textTheme.titleSmall,
                                    ),
                                    if (event.lat != null)
                                      Text('Location: ${event.lat!.toStringAsFixed(5)}, ${event.lng!.toStringAsFixed(5)}'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
