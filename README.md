# AutoMount for macOS

AutoMount is a persistent native macOS network drive connection manager. Built entirely in SwiftUI, it gives users an elegant, simple GUI to mount their NAS shares (like TrueNAS, ZimaOS, Synology, etc.) so the connections survive network drops and Wi-Fi/Ethernet switching without crashing the Finder and closing all the folders.

## Features
- **Modern macOS Feel**: Uses native `SwiftUI` architecture and modern `NavigationSplitView`.
- **System-level autofs**: It interacts directly with `/etc/auto_master` and `/etc/auto_nas` over the `autofs` system, ensuring network mounts are handled by the Unix foundation of macOS.
- **Secure Handling**: Connects securely by URL encoding your passwords away from `/etc/` special characters and leaves passwords strictly unseen in logs.
- **Dynamic Connections**: Mounts natively appear directly in your user's `~/NAS` directory automatically. 

## How To Build
1. Clone the repository.
2. Open `AutoMount.xcodeproj` using Xcode 15 or later.
3. Choose your Mac as the destination.
4. Hit **Run** (`Cmd + R`) to compile the app directly onto your machine!

## How To Run without building
1. Go to Release
2. Download the zip file "AutoMount.zip"
3. Unzip it and run the Application.
4. You have face a error where it shows unknown developer for app, then go to settings>Privacy & Security scroll very down where you will see the app name pop up to allow it to run.

*Note: Since this application requires root-level changes to `auto_nas`, it specifically operates outside of the macOS App Sandbox in order to utilize native `NSAppleScript` privilege escalation.*

## License
MIT License. Feel free to use and distribute!
