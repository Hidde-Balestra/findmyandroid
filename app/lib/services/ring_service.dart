import 'package:alarm/alarm.dart' as plugin;
import 'package:alarm/utils/alarm_set.dart' as plugin;

/// Plays a sound at forced maximum volume that rings through Do Not Disturb,
/// reusing the same `alarm` plugin engine the sibling "alarm" app uses for
/// exactly this behaviour (`VolumeSettings.fixed(volume: 1, volumeEnforced:
/// true)` forces and locks the volume; alarm-stream audio is exempt from DND
/// on stock Android regardless of the notification-policy permission,
/// which is still requested in Settings as a reliability belt-and-braces).
class RingService {
  static const _ringId = 909090;

  Future<void> init() => plugin.Alarm.init();

  Stream<plugin.AlarmSet> get ringing => plugin.Alarm.ringing;

  Future<void> ringNow({
    required String title,
    required String body,
    required String stopButtonLabel,
  }) async {
    await plugin.Alarm.set(
      alarmSettings: plugin.AlarmSettings(
        id: _ringId,
        dateTime: DateTime.now(),
        assetAudioPath: 'assets/sounds/ring.mp3',
        loopAudio: true,
        vibrate: true,
        androidFullScreenIntent: true,
        warningNotificationOnKill: true,
        volumeSettings: const plugin.VolumeSettings.fixed(
          volume: 1,
          volumeEnforced: true,
        ),
        notificationSettings: plugin.NotificationSettings(
          title: title,
          body: body,
          stopButton: stopButtonLabel,
        ),
      ),
    );
  }

  Future<void> stop() => plugin.Alarm.stop(_ringId);
}
