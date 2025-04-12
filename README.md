# VisionAid Companion

## Introduction

VisionAid Companion is a Flutter-based mobile application designed as an assistive technology tool, primarily for users with visual impairments. It leverages real-time computer vision models running on a Python backend, accessed via WebSockets, to provide auditory feedback about the user's surroundings. The app features object detection, hazard detection, scene description, text reading, and barcode scanning capabilities, along with voice control for navigation and Text-to-Speech (TTS) output for results. 

It was entirely made for IEEE competition 2025, and accroding to the requirements of the competition, and based on the competition's theme, requirements and rules.

## Key Features

*   **Multi-Feature Carousel:** Easily swipe between different assistive features.
*   **Object Detection:** Identifies common objects in the camera's view in near real-time and announces them via TTS.
*   **Hazard Detection:** A specialized mode of object detection that specifically identifies potentially hazardous objects (e.g., cars, obstacles, specific items) and provides prominent visual and auditory alerts (sound, vibration, TTS).
*   **Scene Description:** Captures an image and sends it to the backend to generate a brief description of the overall scene (e.g., "kitchen", "street", "office"). Announced via TTS.
*   **Text Reading (OCR):** Captures an image containing text, sends it to the backend for Optical Character Recognition (OCR), and reads the detected text aloud using TTS. Supports multiple languages configured via settings.
*   **Barcode Scanner:** Scans barcodes (like UPC) using the camera and attempts to fetch product information (name, brand) from the Open Food Facts database, announcing the result via TTS.
*   **Text-to-Speech (TTS) Output:** All detection results and alerts are spoken aloud using configurable TTS settings (volume, pitch, speed).
*   **Voice Control:** Navigate between features ("object detection", "barcode scanner", etc.) and access settings using simple voice commands. Triggered by a long-press on the central action button.
*   **Configurable Settings:**
    *   Adjust TTS voice parameters (volume, pitch, speed).
    *   Select the primary language for Text Reading (OCR).
*   **Real-time & Manual Modes:** Object and Hazard detection run continuously when their page is active. Scene, Text, and Barcode detection require user action (tap button or barcode presence).

## Screenshots / Demo ⚒️

### this part is under construction 

*   ### Object Detection: 
    ![Object Detection](/Images/A(2).jpeg)
    
*   ### Hazard Detection: 
    ![Hazard Detection](Images/A(4).jpeg)
    ![Hazard Detection](Images/A(5).jpeg)
    ![Hazard Detection](Images/A(7).jpeg)

*   ### Text Reading: 
    ![Text Reading](Images/A(10).jpeg)

*   ### Barcode Scanning: 
    ![Barcode Scanning](Images/A(6).jpeg)

<!-- *   ### Settings Screen: 
    ![Settings Screen](Images/A(6).jpeg)

*   ### Voice Control: 
    ![Voice Control](Images/A(7).jpeg) -->

## Technology Stack

**Frontend (Flutter App)**

*   **Framework:** Flutter (v3.x recommended)
*   **Language:** Dart
*   **Core Packages:**
    *   `camera`: Accessing device camera stream.
    *   `speech_to_text`: Converting voice commands to text.
    *   `flutter_tts`: Converting text results to speech.
    *   `mobile_scanner`: Dedicated barcode scanning UI and detection.
    *   `socket_io_client`: Real-time WebSocket communication with the backend.
    *   `shared_preferences`: Storing user settings locally.
    *   `http`: Making HTTP requests (for Barcode API).
    *   `audioplayers`: Playing alert sounds.
    *   `vibration`: Providing haptic feedback for alerts.
*   **State Management:** `StatefulWidget` / `setState` (Implicit based on code)

**Backend (Python Server)**

*   **Framework:** Flask, Flask-SocketIO
*   **Language:** Python (v3.8+ recommended)
*   **Core Libraries:**
    *   `socketio`, `python-engineio`, `flask`, `flask-socketio`, `flask-cors`: Web server and WebSocket handling.
    *   `opencv-python` (`cv2`): Image pre-processing.
    *   `torch`, `torchvision`: PyTorch framework for deep learning models.
    *   `ultralytics`: YOLOv5 object detection model.
    *   `easyocr`: Multi-language Optical Character Recognition.
    *   `numpy`: Numerical operations.
    *   `Pillow`: Image manipulation.
    *   `requests`: Downloading model files.
    *   `PyMySQL`, `SQLAlchemy` (Optional, if using the database features).
*   **Models:**
    *   YOLOv5n (Object/Hazard Detection)
    *   Places365 (ResNet50) (Scene Description)
    *   EasyOCR Models (Text Reading)

## Prerequisites

*   **Flutter SDK:** Install the latest stable version from the [Flutter website](https://flutter.dev/docs/get-started/install).
*   **Dart SDK:** Included with Flutter.
*   **Python:** Version 3.8 or higher recommended ([Python website](https://www.python.org/downloads/)). Ensure Python and `pip` are added to your system's PATH.
*   **IDE:** Android Studio or Visual Studio Code (with Flutter and Dart plugins).
*   **Physical Device/Emulator:** A physical Android or iOS device is highly recommended for testing camera-based features. Emulators/Simulators might have limitations.
*   **Network Connection:** Both the device running the Flutter app and the machine running the Python backend need to be on the **same local network** for communication via local IP address.
*   **Backend Model Files:**
    *   YOLOv5 weights will be downloaded automatically by `torch.hub`.
    *   Places365 weights (`resnet50_places365.pth.tar`) and labels (`categories_places365.txt`) will be downloaded automatically by the Python script on first run if not present.
    *   EasyOCR language models will be downloaded automatically on first use for each configured language. **This can take a significant amount of time and requires considerable disk space and RAM.**

## Setup Instructions

**1. Backend (Python Server)**

    ```bash
    # 1. Clone the repository (if you haven't already)
    # git clone <your-repo-url>
    cd <your-repo-name>/backend # Navigate to the backend directory

    # 2. Create and activate a virtual environment (Recommended)
    python -m venv venv
    # On Windows:
    .\venv\Scripts\activate
    # On macOS/Linux:
    source venv/bin/activate

    # 3. Install Python dependencies (Make sure requirements.txt is in this directory)
    pip install -r requirements.txt

    # 4. Run the backend server (this will also trigger model downloads if needed)
    python app.py
    ```

    *   **Important:** Note the IP address and port the backend server is listening on (usually `0.0.0.0:5000`). You'll need the specific local IP of the machine running the backend for the Flutter app configuration. Find your local IP address (e.g., using `ipconfig` on Windows or `ifconfig`/`ip addr` on macOS/Linux).
    *   **Model Downloads:** Be patient during the first run, especially for EasyOCR models. Ensure you have a stable internet connection.

**2. Frontend (Flutter App)**

    ```bash
    # 1. Navigate to the frontend project directory (where pubspec.yaml is)
    cd ../Frontend # Adjust path as necessary

    # 2. Get Flutter dependencies
    flutter pub get

    # 3. Configure Backend IP Address *** THIS IS CRUCIAL ***
    #    Open the file: `lib/core/services/websocket_service.dart`
    #    Find the line:
    #    final String _serverUrl = 'http://xyz:5000'; // Replace xyz with your actual backend IP
    #    Replace `xyz` with the actual local IP address of the machine running the Python backend.
    #    Ensure the port (`5000`) matches the port the backend is running on.
    #    Example: final String _serverUrl = 'http://192.168.1.105:5000';

    # 4. Configure Platform Permissions:
    #    *   iOS: Open `ios/Runner/Info.plist` and add/ensure the following keys exist with appropriate descriptions:
    #        *   `NSCameraUsageDescription`: Explain why the app needs camera access.
    #        *   `NSMicrophoneUsageDescription`: Explain why the app needs microphone access (for voice commands).
    #    *   Android: Open `android/app/src/main/AndroidManifest.xml` and ensure the following permissions are present inside the `<manifest>` tag:
    #        *   `<uses-permission android:name="android.permission.INTERNET"/>`
    #        *   `<uses-permission android:name="android.permission.CAMERA"/>`
    #        *   `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`
    #        *   `<uses-permission android:name="android.permission.VIBRATE"/>`
    #        Also, ensure `<uses-feature android:name="android.hardware.camera" android:required="true"/>` is present. Check the `minSdkVersion` in `android/app/build.gradle` is appropriate (e.g., 21 or higher).

    # 5. Run the Flutter app
    flutter run
    ```

    *   Select your connected physical device or a running emulator/simulator when prompted.

## Running the Application

1.  **Start the Backend:** Navigate to the `backend` directory in your terminal and run `python app.py`. Wait for it to indicate it's running and listening (e.g., `* Running on http://0.0.0.0:5000/`). Note any model download progress.
2.  **Start the Frontend:** Navigate to the `frontend` directory in your terminal and run `flutter run`. Ensure the correct backend IP is configured in `websocket_service.dart`.

## Usage Guide

1.  **Navigation:** Swipe left or right on the screen to cycle through the available features (Object Detection, Hazard Detection, Scene Description, Text Reading, Barcode Scanner). The title banner at the top indicates the current feature.
2.  **Action Button (Center Bottom):**
    *   **Tap:** On features like Scene Description and Text Reading, tapping the button captures an image and sends it for processing. On real-time pages (Object, Hazard, Barcode), the tap action is disabled.
    *   **Long Press:** Activates voice command input. Speak clearly after the microphone icon appears. Release the button or wait for the timeout.
3.  **Voice Commands:**
    *   **Feature Navigation:** Say the feature name or page number (e.g., "object detection", "page 2", "barcode scanner").
    *   **Settings:** Say "settings" or "setting".
4.  **Real-time Features (Object/Hazard Detection):** These features run automatically when their page is active. The app continuously captures frames, sends them for processing, and announces results (or alerts for hazards). Results are displayed briefly on screen.
5.  **Barcode Scanner:** Point the camera steadily at a barcode within the viewfinder area. The app will automatically detect and process it, fetching product info if available.
6.  **Settings:** Access via voice command ("settings") or the settings icon (top right). Adjust OCR language and TTS parameters (volume, pitch, speed). Changes are saved automatically.
7.  **TTS Output:** Results and alerts are read aloud. Hazard alerts also include sound and vibration.

## Troubleshooting

*   **Connection Error / Disconnected:**
    *   Verify the backend server is running.
    *   Ensure the IP address and port in `lib/core/services/websocket_service.dart` are correct and match the backend machine's local IP.
    *   Check that both the device and the backend machine are on the *same* Wi-Fi network.
    *   Check firewall settings on the backend machine; ensure incoming connections on the specified port (e.g., 5000) are allowed.
*   **Camera Black Screen / "Camera Initializing..." / "Camera Unavailable":**
    *   Ensure the app has camera permissions granted in the device settings.
    *   Make sure no other application is using the camera simultaneously.
    *   Try restarting the app.
    *   Try restarting the device.
    *   Rapid switching between features (especially involving the barcode scanner) can sometimes cause timing issues. If stuck, try switching pages again or using the manual capture button (if applicable) to reset the state.
*   **Voice Control Not Working / "Speech unavailable":**
    *   Ensure the app has microphone permissions granted.
    *   Check your internet connection (some STT services might require it).
    *   Speak clearly in a relatively quiet environment.
*   **Backend Model Errors (Check Backend Console):**
    *   **Download Issues:** Ensure a stable internet connection during first run.
    *   **Memory Errors:** EasyOCR and other models can be memory-intensive. Ensure the backend machine has sufficient RAM.
    *   **Dependency Issues:** Double-check that all Python requirements were installed correctly in the correct virtual environment using `pip install -r requirements.txt`.
*   **Barcode Scanner Not Detecting:**
    *   Ensure the barcode is well-lit and centered within the scan area.
    *   Try moving the camera slightly closer or further away.
    *   Some barcode types might not be supported by the underlying library.

## Future Enhancements

*   Support for more OCR languages.
*   Integration of different/more advanced computer vision models.
*   Cloud deployment option for the backend (e.g., Google Cloud Run, AWS EC2).
*   User accounts for saving preferences across devices (requires database integration).
*   Improved UI/UX, focusing further on accessibility guidelines.
*   Offline capabilities for certain features (if possible with smaller models).
*   More granular control over hazard detection sensitivity.

## License

This project is licensed under the MIT License - see the LICENSE.md file for details.
