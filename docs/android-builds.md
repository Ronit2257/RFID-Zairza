# Android builds

Application ID: in.zairza.zairza_attendance. Flutter 3.47.5 / Dart 3.13.4; Gradle uses the binary distribution of version 9.3.1 to avoid downloading unnecessary documentation/source bundles.

## Debug and emulator

```sh
cd apps/mobile
flutter pub get
flutter analyze
flutter test
adb reverse tcp:8080 tcp:8080
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

Start the backend separately. Debug builds accept local HTTP only for localhost/127.0.0.1/10.0.2.2. The signed release requires an HTTPS server. API_BASE_URL is optional; users can enter the Render URL in the sign-in screen.

## Release signing

A local release key was generated for this workspace in android/app/zairza-release.jks, with credentials in android/key.properties. Both files are ignored by Git. Back them up privately: future APK updates must use the same key. Do not commit or share them publicly. No signing credentials are embedded in source or documentation.

On a new checkout without that key, restore the original key/properties from the private backup to continue publishing updates. To create an independent new app signing key, run keytool -genkeypair interactively and write a private android/key.properties with storeFile (relative to android/app), storePassword, keyAlias and keyPassword. The build rejects release tasks without signing configuration rather than silently using a debug key.

```sh
flutter build apk --release
```

Output: build/app/outputs/flutter-apk/app-release.apk. This universal APK supports the Android architectures selected by Flutter. Use `--split-per-abi` if smaller per-architecture APKs are desired. An emulator debug installation must be removed before installing the differently signed release with the same app ID; removing it deletes its local test data.

For distribution, install the signed APK, enter the Render HTTPS URL and that leader's personal code. Do not include codes as Dart defines or compile them into the app.
