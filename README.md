# MinecraftGDK-SteamOS-Installer

> USE WITH CAUTION!
> currently, project in wip state.
> installation probably destroy your NonSteam Games Shortcuts.
> basic installation of Minecraft BE (GDK) is okay.
> contribute if you know how to force steam to perform first time install script on non steam games

Install Minecraft Bedrock Edition on SteamOS with ease.

This project provides a user-friendly, all-in-one installer script that automates the entire process of getting Minecraft Bedrock Edition (GDK version) running on a Steam Deck or any SteamOS system. It handles everything from installing dependencies to setting up the correct Proton compatibility layer and adding the game to your Steam library.

## ✨ Features

- **🚀 All-in-One Installation**: Automatically installs Proton-GDK, Minecraft, and all necessary configurations.
- **🎯 Direct Steam Integration**: Uses `SteamTinkerLaunch` to add the game to your library with the correct launch options automatically.
- **📦 Smart Dependency Management**: Checks for required tools (`steamtinkerlaunch`, `curl`, etc.) and offers to install them for you.
- **🔄 Stateful Re-runs**: Detects an existing installation and offers options to update, reinstall, or uninstall.
- **🌐 Robust Downloading**: Supports both `curl` and `aria2c` for downloading files.
- **📁 Flexible Archive Support**: Can install Minecraft from `.zip`, `.exe`, or `.7z` archives.

## 🚀 Quick Start

1.  **Download the Installer**:
    Place the `minecraft-installer.desktop` file on your Steam Deck's desktop.

2.  **Run the Installer**:
    In Desktop Mode, double-click the `Minecraft Bedrock Installer for Steam Deck` icon. A terminal window will open to guide you through the process.

3.  **Follow the Prompts**:
    - If it's your first time running, the script will offer to install any missing dependencies.
    - You will be asked to select the Minecraft Bedrock installer archive you have downloaded.
    - The script will handle the rest, including adding the game to Steam.

4.  **Play!**:
    After installation, find "Minecraft Bedrock (GDK)" in your Steam library. For the first launch, go to its **Properties > Compatibility** and select `GE-Proton...` from the dropdown.

## 📋 Requirements

- A Steam Deck or PC running SteamOS.
- The unencrypted Minecraft Bedrock Edition archive (`.zip`, `.exe`, or `.7z`).
- An internet connection to download dependencies and Proton-GDK.

### Automatic Dependency Installation

The script will automatically check for and offer to install the following tools if they are missing:

- **Required**:
  - `steamtinkerlaunch`: For seamless integration with Steam.
  - `curl`, `unzip`, `jq`, `7z`: For downloading, extracting, and processing files.
- **Optional (but recommended)**:
  - `aria2c`: A more resilient download manager for unstable connections.

## 📖 How It Works

The installer performs the following steps:

1.  **Dependency Check**: Verifies that all necessary command-line tools are installed.
2.  **Proton-GDK Setup**: Downloads and installs the latest version of [GDK-Proton](https://github.com/Weather-OS/GDK-Proton), a custom Proton build optimized for GDK games like Minecraft Bedrock.
3.  **Minecraft Installation**:
    - Extracts the game files from your chosen archive to `~/.steam/steam/steamapps/common/Minecraft/`.
    - Downloads and places the correct `libcurl` library (`XCurl.dll`) to fix online functionality.
    - Sets up the required SSL certificate directory (`etc/ssl/certs/`) in the correct location for the GDK environment.
4.  **Steam Integration**: Uses `steamtinkerlaunch` to add `Minecraft.Windows.exe` to your library with the necessary launch options for optimal performance and input support.

## 🛠️ Manual Installation Steps (For Reference)

If you prefer to perform the installation manually, the script automates these key actions:

1.  **Install Proton-GDK**: Extract the latest release to `~/.steam/steam/compatibilitytools.d/GE-Proton-<version>/`.
2.  **Install Minecraft**: Extract the game to `~/.steam/steam/steamapps/common/Minecraft/`.
3.  **Configure Libraries**:
    - Copy `libcurl-4.dll` (from [mingw-w64-x86_64-curl](https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-curl-8.17.0-1-any.pkg.tar.zst)) to `.../common/Minecraft/XCurl.dll`.
    - Create the directory `.../steamapps/common/etc/ssl/certs/`.
    - Download `ca-bundle.crt` from [curl.se](https://curl.se/ca/cacert.pem) to that directory.
4.  **Add to Steam**: Add `.../common/Minecraft/Minecraft.Windows.exe` as a non-Steam game.
5.  **Set Launch Options**: `RADV_PERFTEST=rt VKD3D_CONFIG=dxr11,dxr DXVK_ENABLE_NVAPI=1 PROTON_NVAPI=1 %command%`
6.  **Set Compatibility**: Force the use of `GE-Proton...`.

This script automates all of the above for you.

## 🤝 Contributing

Contributions are welcome! If you have a suggestion or find a bug, please open an issue or submit a pull request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Weather-OS/GDK-Proton](https://github.com/Weather-OS/GDK-Proton) for the excellent Proton build that makes this possible.
- [SteamTinkerLaunch](https://github.com/sonic2kk/steamtinkerlaunch) for providing the powerful tools to integrate games into Steam seamlessly.
- MaxRM and Stivusik for Stable and Qualified Minecraft Bedrock Edition experience.
- The original guide and community members who figured out the necessary steps for running Minecraft Bedrock on Linux.
