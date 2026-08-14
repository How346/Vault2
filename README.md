# Secure Doc Vault

You are an expert Flutter developer creating a fully offline, privacy-first Document Wallet app like Zoop Wallet.

### Privacy & Offline Architecture:

- 100% Local Storage: No cloud servers, Firebase, or external API dependencies. All documents, images, and user data must be saved locally on the device storage using Hive / Isar / SQLite.

- Fully Functional Offline APK: The generated build must work completely without an internet connection.

### Core Zoop-like Features:

1. Category-based Hub: Pre-built categories for Aadhaar, PAN, DL, RC, Passport, Marksheets, Insurance, and Custom Categories.

2. Smart Document Scanner & Picker: Crop, auto-enhance, and select PDF/Images from phone storage or camera.

3. Metadata Extraction & Storage: Form fields for Document ID, Issue Date, Expiry Date, and Notes stored alongside the file.

4. Privacy Masking: One-tap option to mask sensitive numbers (e.g., first 8 digits of Aadhaar) on preview/share.

5. Quick Share: Generate masked/unmasked document views or share via local apps without uploading anywhere.

6. Smart Expiry Reminders: Local device notifications for expiring documents (DL, Insurance, Passport).

7. Security: Device Biometric (Fingerprint/FaceID) and 4-digit PIN lock before opening the app.

### Technical & UI Guidelines:

- Clean Material 3 design with smooth card animations and dark/light modes.

- Production-ready, error-free Flutter code structure with clean state management.

This project was built with [Lovable](https://lovable.dev).

## Build with Lovable

Continue developing this project in the [Lovable editor](https://lovable.dev/projects/6c4ff810-8696-4e78-bc56-df20b1dea97f).

- **Ship faster**: describe what you want to build and Lovable handles the code.
- **Stay in sync**: every change made in Lovable is committed straight to this repository.
- **Full ownership**: this code is yours. Push to `main` on GitHub and your changes sync back into Lovable, ready for your next prompt.

## Development

Prefer working locally? You need Node.js and npm — [install with nvm](https://github.com/nvm-sh/nvm#installing-and-updating).

```sh
git clone <this-repository-url>
cd <repository-name>
npm i
npm run dev
```
