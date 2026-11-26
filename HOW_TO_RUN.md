# How to Run Cravera in a Simulator

A step-by-step guide to start the app on a Mac or a Windows PC.

- **Mac** can run the **iPhone simulator** (iOS) and the **Android emulator**.
- **Windows** can run the **Android emulator** only. Apple does not allow iOS simulators on Windows.

The app lives in **`mobile/Cravera`**. Ignore the old `mobile/cravio` folder; it is a leftover from the rename.

---

## Part 1: One-time setup (skip if this computer has run the app before)

### On a Mac

1. **Install Flutter**: follow https://docs.flutter.dev/get-started/install/macos
   (or with Homebrew: `brew install --cask flutter`).
2. **Install Xcode** from the Mac App Store, open it once, and accept the license.
   Then run in Terminal:
   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   xcodebuild -downloadPlatform iOS
   ```
3. **Install CocoaPods** (needed for iOS builds):
   ```bash
   brew install cocoapods
   ```
4. *(Optional, for Android)* Install **Android Studio** from https://developer.android.com/studio,
   then follow the Android steps in the Windows section below (steps 2–4); they are the same on Mac.
5. **Check everything**:
   ```bash
   flutter doctor
   ```
   Fix anything with a red ✗ next to **Flutter**, **Xcode**, or **Android toolchain**. The rest is optional.

### On a Windows PC

1. **Install Git**: https://git-scm.com/download/win
2. **Install Flutter**: follow https://docs.flutter.dev/get-started/install/windows
   (unzip it somewhere like `C:\src\flutter` and add `C:\src\flutter\bin` to your PATH).
3. **Install Android Studio**: https://developer.android.com/studio
   - Open it → **More Actions → SDK Manager** → under **SDK Tools**, tick
     **Android SDK Command-line Tools** → Apply.
4. **Create a virtual phone**: in Android Studio → **More Actions → Virtual Device Manager**
   → **Create Device** → pick a phone (e.g. Pixel 8) → pick a recent system image → Finish.
5. **Accept the Android licenses** (in PowerShell or Command Prompt):
   ```powershell
   flutter doctor --android-licenses
   ```
   Press `y` for every prompt.
6. **Check everything**:
   ```powershell
   flutter doctor
   ```
7. **Get the code** (first time only):
   ```powershell
   git clone https://github.com/aaronnzhang1/Cravera.git Cravera
   ```

> ⚠️ **The `.env` file is not in git.** The app will not build without it.
> Make one from the template: `copy .env.example .env` (Windows) or `cp .env.example .env` (Mac), then fill in the values.
> `.env` is bundled **into the app**, so anyone with a build can read it. Put only public settings in it (the Supabase URL and anon key).
> Private keys such as Gemini or Google Places go in Supabase Edge Function secrets, never in `.env` (see `docs/adr/0003-api-key-handling.md`).
> **Never** commit `.env` or paste it anywhere public.

---

## Part 2: Every time you want to run the app

### On a Mac (iPhone simulator)

Open **Terminal** and run these one at a time:

```bash
# 1. Go to the app folder
cd ~/Developer/Workspaces/Cravera/mobile/Cravera

# 2. Get the latest code
git pull

# 3. Make sure the .env file exists (should print ".env")
ls .env

# 4. Download packages
flutter pub get

# 5. Open the iPhone simulator
open -a Simulator

# 6. Run the app (wait for the simulator phone to finish booting first)
flutter run
```

If Flutter asks which device to use, type the number next to the **iPhone**.
The first iOS build can take a few minutes; later ones are much faster.

**Mac with the Android emulator instead:** replace step 5 with
```bash
flutter emulators                      # lists your virtual phones
flutter emulators --launch <name>      # e.g. flutter emulators --launch Pixel_8_API_35
```

### On Windows (Android emulator)

Open **PowerShell** (or the terminal inside VS Code) and run these one at a time:

```powershell
# 1. Go to the app folder (adjust the path to where you cloned it)
cd C:\path\to\Cravera\mobile\Cravera

# 2. Get the latest code
git pull

# 3. Make sure the .env file exists (should list .env)
dir .env

# 4. Download packages
flutter pub get

# 5. List your virtual phones, then start one
flutter emulators
flutter emulators --launch <name>      # e.g. flutter emulators --launch Pixel_8_API_35

# 6. Run the app (wait for the emulator to show the home screen first)
flutter run
```

If Flutter asks which device to use, pick the one that says **emulator**/**android**.
The first Android build can take 5+ minutes. That's normal.

---

## Part 3: While the app is running

Keep the terminal open. Type these keys in it:

| Key | What it does |
|-----|--------------|
| `r` | **Hot reload**: shows your code changes instantly, keeps your place in the app |
| `R` | **Hot restart**: restarts the app from the sign-in screen |
| `q` | **Quit**: stops the app |

**Testing location** (the app finds nearby restaurants):
- **iPhone simulator:** menu bar → **Features → Location** → pick a preset or **Custom Location…**
- **Android emulator:** click the **⋯** (Extended controls) on the emulator's side bar → **Location** → set a point → **Set Location**

**Run the automated tests / code check** (from `mobile/Cravera`):
```bash
flutter test
flutter analyze
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `No supported devices connected` | The simulator/emulator isn't open yet. Start it (step 5), wait for it to boot, then run `flutter devices` to confirm it shows up. |
| Error about `.env` / `No file or variants found for asset: .env` | The `.env` file is missing from `mobile/Cravera`. See the ⚠️ note in Part 1. |
| You're in the wrong folder (`pubspec.yaml not found`) | Make sure you're in `mobile/Cravera` (capital C), **not** `mobile/cravio`. |
| iOS error mentioning **CocoaPods** or **Pods** | Run `cd ios && pod install && cd ..` then `flutter run` again. |
| Weird build errors after pulling new code | Run `flutter clean` then `flutter pub get` then `flutter run`. |
| `Android license status unknown` | Run `flutter doctor --android-licenses` and press `y` to everything. |
| Still stuck | Run `flutter doctor -v` and read the lines with ✗. They usually say exactly what to install. |
