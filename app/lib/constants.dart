/// Fixed 5-minute background check-in interval. Not user-configurable: Android
/// WorkManager's periodic-task floor is 15 minutes, which is why the app uses
/// a foreground service with its own internal timer instead — see
/// lib/background/location_worker.dart.
const reportingInterval = Duration(minutes: 5);

/// Default backend URL. Overridable in Settings (e.g. for self-hosting on a
/// different domain) — stored via SecureStore.setServerBaseUrl.
const defaultServerBaseUrl = 'https://api.hiddebalestra.nl/findmyandroid';

const notificationChannelId = 'findmyandroid_reporting';
const notificationChannelName = 'Location reporting';
