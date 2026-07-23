class Device {
  final String id;
  final String label;
  final DateTime? lastSeenAt;

  const Device({required this.id, required this.label, this.lastSeenAt});

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        label: json['label'] as String,
        lastSeenAt: json['lastSeenAt'] != null ? DateTime.parse(json['lastSeenAt'] as String) : null,
      );
}

enum RingStatus { none, pending, delivered }

class LocationPoint {
  final String ciphertextBlob;
  final DateTime capturedAt;

  const LocationPoint({required this.ciphertextBlob, required this.capturedAt});

  factory LocationPoint.fromJson(Map<String, dynamic> json) => LocationPoint(
        ciphertextBlob: json['ciphertext'] as String,
        capturedAt: DateTime.parse(json['capturedAt'] as String),
      );
}
