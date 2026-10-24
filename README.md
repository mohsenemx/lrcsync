<div align="center">

# 🎵 LRCSync

**Real-time Android Media Session detector & automated `.lrc` lyrics synchronizer built with Flutter and Material You.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white)](https://www.android.com)
[![Material You](https://img.shields.io/badge/Design-Material%20You%20(M3)-6750A4)](https://m3.material.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

---

## ✨ Overview

**LRCSync** bridges your favorite Android music player (Poweramp, Musicolet, Oto Music, Gramophone, Auxio, etc.) with free, community-driven synced lyrics databases (**LRCLIB** and **LRC.red**). 

It listens to the active Android `MediaSession` in real time, resolves the exact local audio file path on your device storage via `MediaStore`, fetches time-synced `.lrc` lyrics, and writes them directly beside your audio file—zero manual file-picking required.

---

## 📸 Screenshots

| Now Playing | Local Library | Batch Downloader | Live Lyrics | Settings & Material You |
| :---: | :---: | :---: | :---: | :---: |
| ![Now Playing](assets/screenshots/now_playing.jpg) | ![Local Library](assets/screenshots/local_library.jpg) | ![Batch Downloader](assets/screenshots/batch_download.jpg) | ![Live Lyrics](assets/screenshots/lyrics.jpg) | ![Settings](assets/screenshots/settings.jpg) |

---

## 🚀 Features

- **🎧 Real-Time Now Playing Detection**
  - Reads live metadata (`Title`, `Artist`, `Album`, `Duration`, and `Cover Art`) from any active Android music player via `MediaSessionManager` and `NotificationListenerService`.
- **📂 Local Library Browser & LRC Status**
  - Scans and lists all local audio tracks on your device with cover art thumbnails, instant search filtering, and an `LRC` badge indicating which songs already have synced lyrics on disk.
- **⚡ One-Tap & Batch `.lrc` Downloading**
  - **Single Track**: Fetch, preview, and automatically write `.lrc` files directly next to the audio file (`/storage/emulated/0/Music/.../Song.lrc`).
  - **Batch Library Sync**: Download lyrics for your entire music library with configurable request delays (`1.0s` – `5.0s`) to prevent API rate-limiting and a toggle to skip songs that already have `.lrc` files.
- **✏️ Inline Query Editor**
  - Quickly edit the **Title**, **Artist**, or **Album** (optional) before or after searching if a song has messy ID3 tags or remastered suffixes.
- **🌐 Dual Free Lyrics Providers + Fallback**
  - Supports **[LRCLIB](https://lrclib.net)** and **[LRC.red](https://lrc.red)** out of the box with automatic cross-provider fallback.
- **🎨 Material You (Material 3) & AMOLED Dark Mode**
  - Supports Android 12+ dynamic wallpaper colors, custom Material seed palettes, light/dark/system modes, and a pitch-black AMOLED mode.

---

## 🏗️ Architecture

LRCSync uses a feature-first, clean layered architecture paired with a lightweight Kotlin Platform Channel (`MethodChannel` + `EventChannel`) for zero-dependency native Android media integration:

```text
lib/
├── core/
│   ├── settings/       # Theme & Lyrics Provider configuration
│   ├── theme/          # Material 3 Dynamic Color & AMOLED builder
│   └── widgets/        # Shared UI (FloatingNavBar, AlbumArtView)
├── features/
│   ├── now_playing/    # Live MediaSession stream, LyricsService & TrackCard
│   ├── library/        # Local MediaStore browser & rate-limited Batch Downloader
│   └── settings/       # Theme customizer, provider selection & permissions status
└── main_shell.dart     # Root navigation shell
```
## 🔐 Required Android Permissions
Because LRCSync detects active music from other apps and writes .lrc files directly into your music folders without prompting the system file picker each time, it requests three permissions on first launch:

- ### Notification Listener Access (`BIND_NOTIFICATION_LISTENER_SERVICE`)

Required by Android's MediaSessionManager to read metadata from active media notifications.

- ### Read Media Audio (`READ_MEDIA_AUDIO` / `READ_EXTERNAL_STORAGE`)

Required to query MediaStore.Audio and match the playing song to its local file path and cover art.

- ### All Files Access (`MANAGE_EXTERNAL_STORAGE`)

Required on Android 11+ to silently write non-media .lrc files directly into shared music directories alongside your audio files.

## 🛠️ Getting Started
**Prerequisites**

- Flutter SDK >=3.24.0

- Android Studio / Android SDK (API 26+)

**Installation & Build**
1. Clone the repository

```Bash
git clone https://github.com/mohsenemx/lrcsync.git
cd lrcsync
```
2. Install dependencies

```Bash
flutter pub get
```

3. Run in debug mode

```Bash
flutter run
```
4. Configure Android release signing
To build a signed release APK, you need an Android keystore and a key.properties file.

Follow the official [Flutter guide to creating a keystore and configuring Android app signing](https://docs.flutter.dev/deployment/android#sign-the-app).

Create `android/key.properties` with your signing information:
```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=lrcsync
storeFile=/absolute/path/to/lrcsync-release.jks
```

Replace the placeholder values with your own credentials and the path to your keystore. The keyAlias must match the alias you used when creating the keystore.

**Important**: Keep your keystore and `android/key.properties` private. Never commit them to version control. 
This repository's .gitignore excludes both.

5. Build release APK

```Bash
flutter build apk --release
```

or split into different arch types:

```Bash
flutter build apk --release --split-per-abi
```

## 🤝 Acknowledgements
- [LRCLIB](https://lrclib.net/) for providing a free, open-source crowdsourced synced lyrics API.

- [LRC.red](https://lrc.red) for providing ISRC-matched time-synced .lrc files.

- [LRCMux](https://lrcmux.dev/) for providing best available match across multiple sources.

## 📄 License
This project is licensed under the MIT License — see the `LICENSE` file for details.
