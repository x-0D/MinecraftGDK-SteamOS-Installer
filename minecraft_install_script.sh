#!/bin/bash

# Minecraft Bedrock for Steam Deck Installer (Streamlined & Portable Version)
# Version: 5.2
# This script handles dependencies, Proton-GDK, Minecraft by MaxRM installation, and direct Steam integration.

# --- Configuration (Using standard Unix variables) ---
STEAM_DIR="$HOME/.steam/steam"
COMPATTOOLS_DIR="${STEAM_DIR}/compatibilitytools.d"
MINECRAFT_DIR="${STEAM_DIR}/steamapps/common/Minecraft"
# The certs directory is a sibling to the Minecraft directory, as per GDK-Proton requirements
CERTS_DIR="${MINECRAFT_DIR}/../etc/ssl/certs"
STATE_CHECK_FILE="${CERTS_DIR}/ca-bundle.crt"
GITHUB_API_URL="https://api.github.com/repos/Weather-OS/GDK-Proton/releases/latest"
LAUNCH_OPTIONS="RADV_PERFTEST=rt VKD3D_CONFIG=dxr11,dxr DXVK_ENABLE_NVAPI=1 PROTON_NVAPI=1"

# --- Helper Functions ---
zen_nospam() {
  zenity 2> >(grep -v 'Gtk' >&2) "$@"
}

check_and_install_dependencies() {
  local missing_tools=()
  local tools=("steamtinkerlaunch" "curl" "unzip" "jq" "7z")
  
  # Check for mandatory tools
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
      missing_tools+=("$tool")
    fi
  done

  # Check for optional aria2c
  local aria2c_status="optional"
  if ! command -v aria2c &> /dev/null; then
    aria2c_status="missing_optional"
  fi

  if [ ${#missing_tools[@]} -eq 0 ] && [ "$aria2c_status" != "missing_optional" ]; then
    return 0
  fi

  local message="Required tools are missing:\n\n"
  for tool in "${missing_tools[@]}"; do
    message+="- $tool\n"
  done
  if [ "$aria2c_status" == "missing_optional" ]; then
    message+="- aria2c (optional, but recommended for unstable internet)\n"
  fi
  message+="\nThe installer can install them using sudo.\nDo you want to proceed?"

  if (zen_nospam --title="Missing Tools" --width=450 --height=300 --question --text="$message"); then
    local PASS=$(zen_nospam --title="Authentication Required" --width=300 --height=100 --entry --hide-text --text="Enter your sudo password to install missing tools:")
    if [[ $? -ne 0 ]]; then
      zen_nospam --error --text="Installation cancelled by user."
      exit 1
    fi

    if ! echo "$PASS" | sudo -S -k true; then
      zen_nospam --error --text="Incorrect password. Installation cannot continue."
      exit 1
    fi

    (
      echo "10" ; echo "# Updating package lists..." ;
      echo "$PASS" | sudo -S -k pacman -Sy

      echo "50" ; echo "# Installing required tools..." ;
      if [ ${#missing_tools[@]} -gt 0 ]; then
        echo "$PASS" | sudo -S -k pacman -S --needed "${missing_tools[@]}"
      fi
      
      if [ "$aria2c_status" == "missing_optional" ]; then
        echo "$PASS" | sudo -S -k pacman -S --needed aria2c
      fi

      echo "100" ; echo "# Tools installed successfully" ;
    ) | zen_nospam --progress --title="Installing Tools" --width=300 --height=100 --text="Installing..." --percentage=0 --no-cancel --auto-close
  else
    zen_nospam --error --text="Required tools are missing. Please install them manually and run the installer again.\n\nRequired: steamtinkerlaunch, unzip, curl, jq, 7z (via pacman)\nOptional: aria2c (via pacman)"
    exit 1
  fi
}

# --- Main Installation Logic ---
main() {
  local install_option
  if [[ -f "$STATE_CHECK_FILE" ]]; then
    install_option=$(zen_nospam --title="Minecraft Bedrock Installer" --width=500 --height=350 --list --radiolist --text="Minecraft Bedrock installation detected. Select an option:" --hide-header --column="Select" --column="Action" --column="Description" \
      TRUE "update_proton" "Update Proton-GDK to the latest version" \
      FALSE "reinstall_minecraft" "Reinstall Minecraft Bedrock from an archive" \
      FALSE "add_to_steam" "Add Minecraft Bedrock to the Steam library" \
      FALSE "uninstall" "Remove all Minecraft components")
  else
    install_option="full_install"
  fi

  if [[ "$install_option" == "uninstall" ]]; then
    (rm -rf "${MINECRAFT_DIR}" && rm -rf "${MINECRAFT_DIR}/../etc")
    zen_nospam --info --text="Minecraft Bedrock and its components have been removed."
    exit 0
  fi

  if [[ "$install_option" == "add_to_steam" ]]; then
    local main_exe=$(find "$MINECRAFT_DIR" -name "Minecraft.Windows.exe" | head -n 1)
    if [[ -z "$main_exe" ]]; then
      zen_nospam --error --text="Could not find Minecraft.Windows.exe. Please reinstall the game first."
      exit 1
    fi
    steamtinkerlaunch addnonsteamgame -ep="$main_exe" -an="Minecraft Bedrock (GDK)" -clo="$LAUNCH_OPTIONS"
    zen_nospam --info --width=500 --height=200 --text="Minecraft Bedrock has been added to your Steam library!\n\nFinal Step:\nIn Steam, right-click 'Minecraft Bedrock (GDK)' -> Properties -> Compatibility, and select 'GE-Proton...'."
    exit 0
  fi

  if [[ "$install_option" != "add_to_steam" ]]; then
    check_and_install_dependencies
  fi

  if [[ "$install_option" == "full_install" || "$install_option" == "update_proton" || "$install_option" == "reinstall_minecraft" ]]; then
    (
      echo "10" ; echo "# Fetching latest Proton-GDK release info..." ;
      mkdir -p "$COMPATTOOLS_DIR"
      local release_info=$(curl -s "$GITHUB_API_URL")
      local latest_version=$(echo "$release_info" | jq -r '.tag_name')
      local download_url=$(echo "$release_info" | jq -r '.assets[].browser_download_url | select(endswith("tar.gz"))')
      local proton_dir_name="GE-Proton-${latest_version}"

      echo "30" ; echo "# Downloading Proton-GDK ${latest_version}..." ;
      rm -rf "${COMPATTOOLS_DIR}/${proton_dir_name}"
      if command -v aria2c &> /dev/null; then
        aria2c -d "$COMPATTOOLS_DIR" -o "gdk_proton.tar.gz" "$download_url"
      else
        curl -L -o "${COMPATTOOLS_DIR}/gdk_proton.tar.gz" "$download_url"
      fi

      echo "60" ; echo "# Extracting Proton-GDK..." ;
      tar -xzf "${COMPATTOOLS_DIR}/gdk_proton.tar.gz" -C "$COMPATTOOLS_DIR"
      mv "${COMPATTOOLS_DIR}/GDK-Proton"* "${COMPATTOOLS_DIR}/${proton_dir_name}"
      rm "${COMPATTOOLS_DIR}/gdk_proton.tar.gz"
      ln -sfn "${COMPATTOOLS_DIR}/${proton_dir_name}" "${COMPATTOOLS_DIR}/GE-Proton"

      echo "100" ; echo "# Proton-GDK installation complete!" ;
    ) | zen_nospam --progress --title="Installing Proton-GDK" --width=400 --height=150 --text="Installing Proton-GDK..." --percentage=0 --no-cancel --auto-close
  fi

  if [[ "$install_option" == "full_install" || "$install_option" == "reinstall_minecraft" ]]; then
    local minecraft_archive
    minecraft_archive=$(zen_nospam --title="Select Minecraft Bedrock Archive" --file-selection --file-filter="ZIP Archives | *.zip" --file-filter="All Files | *")
    if [[ $? -ne 0 || -z "$minecraft_archive" ]]; then
      zen_nospam --error --text="No archive selected. Installation cancelled."
      exit 1
    fi

    (
      echo "10" ; echo "# Preparing installation directory..." ;
      rm -rf "$MINECRAFT_DIR"
      mkdir -p "$MINECRAFT_DIR"

      echo "30" ; echo "# Extracting Minecraft Bedrock archive..." ;
      if [[ "$minecraft_archive" == *.zip ]]; then
        unzip -q "$minecraft_archive" -d "$MINECRAFT_DIR"
      else
        7z x "$minecraft_archive" -o"$MINECRAFT_DIR"
      fi
      
      local main_exe=$(find "$MINECRAFT_DIR" -name "Minecraft.Windows.exe" | head -n 1)
      if [[ -z "$main_exe" ]]; then
        zen_nospam --error --text="Could not find Minecraft.Windows.exe in the archive. Please check its contents."
        exit 1
      fi

      echo "60" ; echo "# Configuring SSL and curl..." ;
      mkdir -p "$CERTS_DIR"
      curl -L -o "$STATE_CHECK_FILE" "https://curl.se/ca/cacert.pem"
      
      curl -L -o "/tmp/curl_pkg.pkg.tar.zst" "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-curl-8.17.0-1-any.pkg.tar.zst"
      temp_dir=$(mktemp -d)
      tar -xf "/tmp/curl_pkg.pkg.tar.zst" -C "$temp_dir"
      cp "$temp_dir/mingw64/bin/libcurl-4.dll" "${MINECRAFT_DIR}/XCurl.dll"
      rm -rf "$temp_dir" "/tmp/curl_pkg.pkg.tar.zst"

      echo "100" ; echo "# Minecraft Bedrock installation complete!" ;
    ) | zen_nospam --progress --title="Installing Minecraft Bedrock" --width=400 --height=150 --text="Installing Minecraft Bedrock..." --percentage=0 --no-cancel --auto-close
  fi

  # Add to Steam using SteamTinkerLaunch with custom launch options
  if [[ "$install_option" == "full_install" || "$install_option" == "reinstall_minecraft" || "$install_option" == "add_to_steam" ]]; then
    local main_exe=$(find "$MINECRAFT_DIR" -name "Minecraft.Windows.exe" | head -n 1)
    if [[ -f "$main_exe" ]]; then
      steamtinkerlaunch addnonsteamgame -ep="$main_exe" -an="Minecraft Bedrock (GDK)" -clo="$LAUNCH_OPTIONS"
      zen_nospam --info --width=500 --height=250 --text="Installation complete!\n\n'Minecraft Bedrock (GDK)' has been added to your Steam library.\n\nFinal Step:\nIn Steam, right-click the game -> Properties -> Compatibility, and select 'GE-Proton...'.\n\nFor joystick support, you may need to install runtimes using Protontricks after setting the compatibility tool."
    else
      zen_nospam --error --text="Could not find the game executable. Please try reinstalling."
    fi
  fi
}

main
