# ChittiSat Android reconstruction

This project is a reconstructed Android Flutter frontend based on the supplied
ChittiSat Windows Flutter build.

## Included
- Screenshot-inspired dashboard layout
- Weather request using the same Open-Meteo service family found in the original
- Android USB/serial connection using `usb_serial`
- Temperature, humidity, pressure, altitude, movement and gas fields
- Original weather icons and satellite model assets

## Important limitation
The supplied Windows application contains compiled Dart AOT (`app.so`) rather than
the original Dart source. The Windows build also uses a custom serial protocol.
This project therefore uses a JSON-line serial adapter as a safe first port.

Expected serial message example:
{"temperature":24.5,"humidity":62,"pressure":1009,"altitude":125,
 "x":1,"y":2,"z":3,"ax":0.1,"ay":0.2,"az":0.3,
 "smoke":0.4,"methane":0.1,"lpg":0.2,"hydrogen":0.3}

Once the actual device packet format is recovered, replace `_onSerialData`
in `lib/main.dart` with the real parser.

## Build
1. Install Flutter and Android Studio.
2. Create a normal Flutter app or use this directory as the project.
3. Run `flutter pub get`.
4. Run `flutter build apk --release`.

The Android build requires the Flutter/Android SDK toolchain; it is not present
in the current execution environment, so an APK could not be compiled here.


## Build automatically with GitHub Actions

This project includes `.github/workflows/build-apk.yml`.

### Quick setup

1. Create a new GitHub repository, for example `ChittiSat-Android`.
2. Upload the **contents of this project folder** to the repository root.
   The `.github/workflows/build-apk.yml` file must be present at exactly that path.
3. Commit/push to `main` (or `master`).
4. Open the repository's **Actions** tab.
5. Select **Build ChittiSat APK**.
6. If necessary, choose **Run workflow**.
7. Wait for the workflow to finish.
8. Open the completed workflow run and download the artifact named:
   `ChittiSat-Android-APK`
9. Extract the downloaded artifact. It contains:
   `app-release.apk`

No Flutter or Android SDK installation is required on your Windows laptop for this GitHub build.

### Notes

The workflow builds an unsigned release APK suitable for testing. It is not a Play Store-signed release.

The serial protocol is currently represented by the temporary JSON-line adapter described in
`REVERSE_ENGINEERING_NOTES.txt`. The APK can therefore be tested with the Raspberry Pi Pico
once it sends the expected test data, while the original ChittiSat serial protocol is still
being recovered.
