# Setup, testing and release

## Prerequisites

| Tool | Version used | Needed for |
|---|---|---|
| Flutter SDK | 3.44 (Dart 3.12) | Everything |
| Xcode | 26.x | iPhone builds |
| Apple ID in Xcode | Free or paid developer account | Installing on an iPhone |
| Android Studio / SDK | Any recent | Android builds (optional) |
| Supabase CLI | Latest | Only for the optional backend |

Check your setup with:

```bash
flutter doctor
```

## Run in development

```bash
cd app && flutter pub get
```

```bash
cd app && flutter run
```

Add `--dart-define-from-file=secrets.json` to turn on AI (see
[AI providers](AI_PROVIDERS.md)).

## Tests

```bash
cd app && flutter test
```

```bash
cd app && flutter analyze
```

There are 18 tests covering the knowledge base, the diagnosis flows, the
safety rules, pricing, and the Gemini request format and fallback.

---

## Install on an iPhone (Release mode)

Release mode is the one to use for testing and demos. Debug builds on iOS only
open while connected to Xcode, whereas a Release build opens from the home
screen like any other app.

### One-time phone setup

1. Connect the iPhone to the Mac with a cable, unlock it, and tap **Trust**.
2. In Xcode: **Window → Devices and Simulators**. Wait until the phone is
   paired and "prepared for development".
3. On the iPhone: **Settings → Privacy & Security → Developer Mode → On**. The
   phone restarts; confirm when asked.

### Build and install

```bash
cd app && flutter run --release --dart-define-from-file=secrets.json
```

Leave off `--dart-define-from-file=secrets.json` to install the offline version.

**Or from Xcode:** first run
`flutter build ios --release --dart-define-from-file=secrets.json`, then open
`app/ios/Runner.xcworkspace`. Set **Product → Scheme → Edit Scheme → Run →
Build Configuration** to **Release**, choose the iPhone, and press ⌘R.

### First launch

If iOS shows *Untrusted Developer*: **Settings → General → VPN & Device
Management →** your Apple ID **→ Trust**.

### Apple account notes

- **Free Apple ID:** the app stops opening after **7 days** and must be reinstalled.
- **Apple Developer Program (paid):** installs last a year, and **TestFlight**
  lets you send the app to other testers' phones.

---

## Change the app icon

1. Replace `app/assets/icon/app_icon.png` with a **1024×1024 PNG with no
   transparency**.
2. Generate all sizes for iOS, Android and web:
   ```bash
   cd app && dart run flutter_launcher_icons
   ```
3. Rebuild. If the old icon still shows on the iPhone, delete the app and
   install it again.

## App name

- The title shown inside the app is set in `app/lib/ui/home_screen.dart` and
  `app/lib/main.dart`.
- The name under the icon on the iPhone is `CFBundleDisplayName` in
  `app/ios/Runner/Info.plist`. Keep it short (about 12 characters), or iOS
  cuts it off.

## Identifiers

| Setting | Value |
|---|---|
| iOS bundle id / Android application id | `uk.bikeassessor.bikeAssessor` |
| Dart package name | `bike_assessor` |

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `resource fork, Finder information, or similar detritus not allowed` | The project is inside an iCloud-synced folder (for example `~/Documents`), which adds file metadata that code signing rejects | `app/build` is a link to `~/Library/Caches/bike_assessor_build`, outside iCloud. If the link is lost, recreate it, or move the project out of iCloud-synced folders |
| `database or disk is full` | The Mac is out of disk space | Free at least 10 GB. Xcode's `~/Library/Developer/Xcode/DerivedData` and old folders in `iOS DeviceSupport` are safe to clear |
| `… is not available because it is unpaired` | The phone isn't paired with Xcode | Follow *One-time phone setup* above |
| App opens then closes when you tap its icon | It's a Debug build | Install with `--release` |
| Camera or photo button crashes the app | Missing permission text | `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` must be in `Info.plist` (they already are) |
| Chat says "AI not available, using offline matching" | Bad key, rate limit or no internet | Read the error shown in the chat. Check `secrets.json` and your Gemini quota |
| Web build shows a blank page | The build was interrupted (often by low disk space) | Run `flutter build web` again and check that `build/web/main.dart.js` exists |
