# Linux Flutter environment check

Checked locally on 2026-09-28. This was a read-only check; nothing was installed.

| Item | Observed result |
|---|---|
| Flutter command | Not found on PATH |
| Dart command | Not found on PATH |
| Flutter SDK | Not found in common paths or bounded search of home, /opt, /usr/local and /snap |
| Android Studio | Launcher /usr/bin/android-studio and installation /opt/android-studio exist; GUI not launched |
| Java | OpenJDK 17.0.20.1 available |
| ANDROID_HOME | /home/aline/Android/Sdk, but this directory is missing |
| adb / sdkmanager | Not found on PATH or in searched locations |
| Android AVD directory | /home/aline/.android/avd is missing |
| Node / npm | v26.9.0 / 12.0.2 available; select supported runtime at implementation |
| Basic download/archive tools | git, curl, unzip, xz, zip available |

Conclusion: there is no usable Flutter/Android build toolchain in the checked environment. An SDK in an unsearched custom path cannot be ruled out. Flutter doctor could not run because flutter is unavailable.

## Setup sequence, once implementation begins

1. Install the stable Flutter SDK in a user-owned tools directory, for example ~/develop/flutter, and add its bin directory to PATH. Flutter includes the corresponding Dart SDK.
2. Use the existing Android Studio installation to install the Android SDK, platform tools, command-line tools, build tools and the platform required by the selected Flutter version. Restore the SDK at ANDROID_HOME or update that setting.
3. Install editor Flutter/Dart support. A Flutter IDE plugin alone does not install the SDK.
4. Run flutter doctor -v. Resolve the Android Java/Gradle compatibility checks using the selected Flutter/Android toolchain, including Android Studio's bundled JDK if appropriate; having Java 17 on PATH alone does not prove compatibility.
5. Review/accept Android SDK licenses via flutter doctor --android-licenses.
6. Prefer a physical Android phone with USB debugging for the first build. Create an emulator only if needed; system images consume additional disk space.
7. Run flutter devices and a development build on the phone. Record exact Flutter, Dart, Android and Java versions after successful validation.

Official guidance: [manual Flutter installation](https://docs.flutter.dev/install/manual), [Android setup](https://docs.flutter.dev/platform-integration/android/setup).
