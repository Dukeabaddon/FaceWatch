<div align="center">

# 👁️ FaceWatch

### Real-Time Facial Recognition with 3D Mesh Overlay — Built with Flutter

[![Flutter](https://img.shields.io/badge/Flutter-3.41.4-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.11.1-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Android](https://img.shields.io/badge/Android-API%2024+-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![iOS](https://img.shields.io/badge/iOS-15.5+-000000?logo=apple&logoColor=white)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Stars](https://img.shields.io/github/stars/Dukeabaddon/FaceWatch?style=social)](https://github.com/Dukeabaddon/FaceWatch/stargazers)

**A privacy-first, fully on-device facial recognition app.  
No cloud. No servers. No data leaves your phone.**

[Download APK](#-download) · [Features](#-features) · [Tech Stack](#-tech-stack) · [Getting Started](#-getting-started) · [Architecture](#-architecture)

<br/>

![FaceWatch Demo](https://raw.githubusercontent.com/Dukeabaddon/FaceWatch/main/docs/demo.gif)

</div>

---

## ✨ Features

| Feature | Description |
|---|---|
| 🧠 **On-Device AI** | All processing happens locally — zero network calls, zero data leaks |
| 🔬 **3D Face Mesh Overlay** | Animated contour scan with real-time landmark detection |
| 👤 **Face Registration** | Register any face with a name in seconds |
| ⚡ **Real-Time Recognition** | Live camera feed with instant name identification |
| 📊 **Confidence Scores** | Shows match percentage (e.g. `Alice 94%`) |
| 📳 **Haptic Feedback** | Distinct vibration on match vs. unknown face |
| 🗂️ **Local Storage** | All registered faces stored on-device via Hive |
| 🗑️ **Face Management** | View, swipe-to-delete, or clear all registered faces |
| 🌑 **Dark UI** | Minimal, clean dark interface with cyan accent palette |

---

## 📱 Download

> **Latest Release:** `v1.0.0`

| Platform | Download |
|---|---|
| Android (APK) | [FaceWatch-v1.0.0.apk](https://github.com/Dukeabaddon/FaceWatch/releases/latest) |
| iOS | Build from source (requires Xcode + Apple Developer account) |

---

## 🎬 How It Works

```
┌─────────────────────────────────────────────────────┐
│                      FACEWATCH                      │
│                                                     │
│  Camera Frame                                       │
│       ↓                                             │
│  Google ML Kit Face Detection                       │
│       ↓                                             │
│  Face crop → MobileFaceNet (TFLite)                 │
│       ↓                                             │
│  192-dim embedding                                  │
│       ↓                                             │
│  Cosine Similarity vs. Hive stored embeddings       │
│       ↓                                             │
│  "Alice 94%" overlay + haptic feedback              │
└─────────────────────────────────────────────────────┘
```

1. **Register** — Point camera at a face, capture, enter a name. Embedding is stored in Hive.
2. **Recognize** — Real-time camera scan. Every frame runs face detection + embedding + cosine match.
3. **Manage** — Swipe to delete faces, or clear all.

---

## 🛠️ Tech Stack

| Layer | Technology | Version |
|---|---|---|
| Framework | Flutter | 3.41.4 |
| Language | Dart | 3.11.1 |
| Face Detection | Google ML Kit Face Detection | 0.13.2 |
| Face Mesh | Google ML Kit Face Mesh Detection | 0.4.2 |
| Embedding Model | MobileFaceNet (TFLite) | — |
| ML Runtime | TFLite Flutter | 0.12.1 |
| Local Storage | Hive + Hive Flutter | 2.2.3 / 1.1.0 |
| Camera | camera | 0.12.0+1 |
| Image Processing | image | 4.2.0 |
| Feedback | vibration + HapticFeedback | 2.0.0 |

---

## 🏗️ Architecture

```
lib/
├── main.dart                     # App entry, Hive init
├── models/
│   ├── registered_face.dart      # Hive data model
│   └── registered_face.g.dart    # Generated Hive adapter
├── services/
│   ├── face_detector_service.dart  # ML Kit wrapper
│   ├── face_embedder_service.dart  # TFLite + cosine sim
│   └── face_storage_service.dart   # Hive CRUD
├── painters/
│   └── face_mesh_painter.dart    # 3D mesh CustomPainter
└── screens/
    ├── home_screen.dart          # Landing / navigation
    ├── register_screen.dart      # Camera + capture + register
    ├── recognition_screen.dart   # Live recognition
    └── manage_faces_screen.dart  # CRUD face list
```

**Design principles:**
- **No backend** — 100% offline, privacy-by-design
- **Service layer** — clean separation: detection / embedding / storage
- **CustomPainter** — hardware-accelerated mesh overlay, no third-party canvas libs
- **Hive** — zero-config flat-file NoSQL, ~2× faster than SQLite for this use case

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK `3.41.4+`
- Android Studio / Xcode
- Android device/emulator API 24+ or iOS 15.5+

### Installation

```bash
git clone https://github.com/Dukeabaddon/FaceWatch.git
cd FaceWatch/face_recognition_app
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

### Build APK

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Build iOS

```bash
flutter build ios --no-codesign
# Then open ios/Runner.xcworkspace in Xcode and archive
```

---

## 🧪 Tests

```bash
flutter test          # Run all tests
flutter analyze       # Static analysis (0 issues)
```

**Test coverage:**
- `FaceEmbedderService` — cosine similarity, `findBestMatch` with edge cases
- `HomeScreen` widget — navigation cards, layout verification

---

## 📐 Face Recognition Accuracy

> **Note:** The bundled TFLite model is a MobileFaceNet-architecture model trained on 192-dimensional embeddings. For production-grade accuracy, replace `assets/models/mobilefacenet.tflite` with a pretrained model (e.g. trained on MS-Celeb, VGGFace2).

| Metric | Value |
|---|---|
| Embedding dimensions | 192 |
| Input size | 112 × 112 px |
| Default match threshold | 0.65 cosine similarity |
| Inference device | CPU (on-device) |

---

## 🔒 Privacy

- ✅ **Zero network requests** — no telemetry, no analytics, no cloud sync
- ✅ **All biometric data stored locally** on-device in Hive
- ✅ **No third-party SDKs** that phone home
- ✅ Camera permission only used during active camera screens

---

## 🗺️ Roadmap

- [ ] Pretrained MobileFaceNet weights (MS-Celeb-1M)
- [ ] Face liveness detection (anti-spoofing)
- [ ] Export/import registered faces
- [ ] Background recognition service
- [ ] macOS desktop support

---

## 🤝 Contributing

Pull requests welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) or open an issue.

```bash
git checkout -b feature/your-feature
# make changes
git commit -m "feat: your feature"
git push origin feature/your-feature
```

---

## 📄 License

MIT © [Dukeabaddon](https://github.com/Dukeabaddon)

---

<div align="center">

**Built with Flutter · Powered by ML Kit + TFLite · Private by Design**

⭐ Star this repo if you found it useful!

</div>
