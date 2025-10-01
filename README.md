# Coalition Mobile App (Flutter)

A Flutter application that extends the Coalition for Montana's Future web experience into a mobile-first platform for Android and iOS. The app highlights candidates, lets supporters follow priorities, and gives admins a lightweight control center.

---

## 1. Prerequisites

The commands below assume Linux or WSL2. macOS users can swap the package-manager steps for Homebrew; Windows users should install Flutter via the official installer. You will need:

- Git, curl, unzip, xz-utils, zip, libglu1 (Ubuntu/Debian)
- Flutter SDK (3.16 or newer)
- Android Studio (for the Android toolchain/emulator)
- Xcode (for iOS builds, macOS only)
- Optionally: Chrome (for web testing) and VS Code/Android Studio plugins

### 1.1 Install base packages (Ubuntu / Debian)

```bash
sudo apt update
sudo apt install git curl unzip xz-utils zip libglu1-mesa
```

### 1.2 Install the Flutter SDK

```bash
cd ~
curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.19.0-stable.tar.xz
sudo tar xf flutter_linux_3.19.0-stable.tar.xz -C /opt
```

Add Flutter to your PATH (append to `~/.bashrc` or `~/.zshrc`):

```bash
echo 'export PATH=/opt/flutter/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

(Replace the version string with the latest stable release if needed.)

### 1.3 Validate the toolchain

```bash
flutter doctor
```

Resolve any issues it reports (missing Android licenses, Xcode CLTs, etc.). To accept Android licenses:

```bash
flutter doctor --android-licenses
```

### 1.4 Android tooling

1. Install [Android Studio](https://developer.android.com/studio) and open it at least once.
2. From the **More Actions ▸ SDK Manager**, install the latest Android SDK Platform + Google APIs, and install an emulator image via the **AVD Manager**.
3. Ensure `adb` is on your PATH (Android Studio does this automatically).

### 1.5 iOS tooling (macOS only)

1. Install Xcode from the App Store.
2. From Xcode, run **Preferences ▸ Locations** and select a Command Line Tools version.
3. Accept the Xcode license via `sudo xcodebuild -license`.
4. Run `sudo gem install cocoapods` if CocoaPods is missing.

### 1.6 VS Code / Android Studio setup (optional)

- Install the Flutter and Dart extensions in VS Code, or enable the Flutter plugin in Android Studio.
- In VS Code, run **Flutter: New Project** to verify the extension works.

---

## 2. Project Structure

```
lib/
├── app.dart                # MaterialApp + router wiring
├── main.dart               # ProviderScope bootstrap
├── core/
│   ├── constants/          # Sample data and shared constants
│   ├── routing/            # go_router configuration
│   ├── services/           # Repository abstractions + in-memory impl
│   └── theme/              # Centralized theme definitions
├── features/
│   ├── admin/              # Admin dashboard UI and forms
│   ├── auth/               # Auth controller, models, and gate UI
│   ├── candidates/         # Candidate models, providers, list/detail screens
│   ├── events/             # Events models, providers, feed/detail screens
│   ├── home/               # Bottom-nav shell
│   └── profile/            # User profile and saved content views
└── assets/sample/          # Placeholder asset directory
```

The project uses Riverpod for state management and GoRouter for navigation. Repositories currently ship with in-memory sample data (`lib/core/constants/sample_data.dart`); swap in real API clients or a data layer when ready.

---

## 3. Local Development Workflow

From the repo root, enter the app directory and fetch dependencies:

```bash
cd ~/Programming/Redneck\ Democrat\ Coalition/coalition_mobile_app
flutter pub get
```

### 3.1 Launching the app

- **Run flutter create (first time only):** because this repo only contains the Dart source, generate the Android/iOS platform folders once via `flutter create .` inside `coalition_mobile_app/`.

- **Android emulator:**
  1. List configured emulators with `flutter emulators`.
  2. Launch one with `flutter emulators --launch emulator-id` (use the id from the list, e.g. `Medium_Phone_API_36.1`).
  3. Wait for the emulator window to finish booting (or launch it via Android Studio ▸ Device Manager).
  4. Confirm Flutter sees it with `flutter devices` — look for an entry such as `emulator-5554`.
  5. Run `flutter run` (or `flutter run -d emulator-5554`).
- **Physical Android:** enable USB debugging, connect the device, then `flutter devices` followed by `flutter run -d <device-id>`.
- **iOS simulator:** `open -a Simulator`, then `flutter run` (macOS only).
- **Web preview (Chrome):** `flutter run -d chrome` (ensure Chrome is installed).

The default entry point starts with the auth gate. Register a supporter (or sign in with the “Sign in as admin” checkbox) to explore the entire app and admin tools.

### 3.2 Hot reload / restart

- Press `r` in the `flutter run` console for hot reload, `R` for hot restart.
- Press `q` to quit.

### 3.3 Running tests

When you add unit or widget tests:

```bash
flutter test
```

Consider adding `integration_test/` suites once APIs are wired up.

---

## 4. Admin Mode

- Accounts created with the **Request admin access** toggle (or signing in with the admin checkbox) unlock the hidden dashboard via the shield icon in the app bar.
- Admins can add or update candidate and event records, which immediately push updates through the in-memory repository streams.
- The RSVP overview card is wired to the auth state; swap in your backend to surface real supporter metrics.

---

## 5. Next Steps & Integration Hooks

- Replace the in-memory repository with Firebase, Supabase, Airtable, or a custom API layer.
- Wire URL launches (e.g., `url_launcher`) for social links and RSVP buttons.
- Add analytics / crash reporting via Firebase Analytics, Sentry, etc.
- Localize strings and run an accessibility audit before launch.
- Harden auth with Firebase Auth, Auth0, or another identity provider in place of the demo controller.

---

## 6. Troubleshooting

| Symptom | Likely Fix |
| --- | --- |
| `flutter: command not found` | Ensure `/opt/flutter/bin` (or your install path) is on `PATH`, then `source ~/.bashrc` or open a new shell. |
| `Command flutter not found but can be installed with ...` | Follow the installation steps in section 1. |
| Android licenses not accepted | `flutter doctor --android-licenses` and accept each prompt. |
| No connected devices | Launch an emulator (`flutter emulators --launch`) or plug in a device with USB debugging enabled. |
| iOS build errors about CocoaPods | Run `sudo gem install cocoapods && pod repo update` (macOS). |

Need more help? Run `flutter doctor -v` and paste the output when asking for assistance.

---

## 7. Quick Reference Commands

```bash
# Fetch dependencies
flutter pub get

# First-time platform scaffolding
flutter create .

# List available devices/emulators
flutter devices
flutter emulators

# Run on a specific target
flutter run -d chrome             # Web preview
flutter run -d linux              # Desktop (if enabled)
flutter run -d emulator-5554      # Example Android emulator id
flutter run -d <actual-device-id> # Mobile device/emulator (replace placeholder)

# Run tests
flutter test
```

Happy building!
