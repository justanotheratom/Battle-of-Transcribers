# Battle of Transcribers

Battle of Transcribers is an iOS application that allows users to transcribe audio using multiple transcription services. The app supports various transcribers and provides a user-friendly interface to manage and use these services.

## Supported Transcribers

The application currently supports the following transcribers:

1. **iOS Built-in Transcriber**
2. **OpenAI Whisper v2**
3. **Deepgram Streaming**
4. **Groq Whisper v3**

## Adding API Keys

Some transcribers require an API key to function. To add an API key:

1. Open the app and navigate to the Settings screen by tapping the gear icon.
2. Select the transcriber that requires an API key.
3. Tap on the API Key field and paste your API key.
4. The app will save the API key securely using Keychain.

## Building and Running on iPhone

To build and run the application on an iPhone, follow these steps:

1. **Clone the Repository:**
   git clone https://github.com/yourusername/BattleOfTranscribers.git
   cd BattleOfTranscribers

2. **Open the Project in Xcode:**
   Open `BattleOfTranscribers.xcodeproj` in Xcode.

3. **Install Dependencies:**
   Ensure you have all the required dependencies. The project uses Swift Package Manager to manage dependencies. Xcode should automatically resolve and download these packages.

4. **Set Up Signing:**
   - Go to the project settings in Xcode.
   - Under the "Signing & Capabilities" tab, select your development team.

5. **Build and Run:**
   - Connect your iPhone to your computer.
   - Select your iPhone as the target device in Xcode.
   - Click the "Run" button (or press `Cmd + R`) to build and run the app on your iPhone.
