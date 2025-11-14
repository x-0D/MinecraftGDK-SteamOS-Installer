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

# Function to find Steam userdata path (assumes primary user; extend if multi-user)
find_steam_userdata() {
    local steam_root="$HOME/.steam/steam"  # Adjust if Steam is in .local/share/Steam
    local userdata_dir="$steam_root/userdata"
    if [ ! -d "$userdata_dir" ]; then
        echo "Error: Steam userdata directory not found at $userdata_dir" >&2
        exit 1
    fi

    # Find the most recent user (first non-empty dir with config/shortcuts.vdf)
    local user_id
    for dir in "$userdata_dir"/*/; do
        if [ -f "$dir/config/shortcuts.vdf" ]; then
            user_id="${dir##*/}"
            break
        fi
    done
    if [ -z "$user_id" ]; then
        echo "Error: No Steam user config found" >&2
        exit 1
    fi
    echo "$userdata_dir/$user_id/config/shortcuts.vdf"
}

# Function to generate signed 32-bit AppID (randomized based on name + exe for uniqueness)
generate_app_id() {
    local seed_input="$1"
    local seed_hex=$(echo -n "$seed_input" | md5sum | cut -c1-8)
    # Generate negative signed 32-bit int (subtract from a large number to ensure range)
    local signed_id="-$(( 0x${seed_hex} % 2147483648 ))"  # Max for signed 32-bit
    echo "$signed_id"
}

# Function to convert signed decimal to 4-byte little-endian hex
dec_to_little_endian_hex() {
    local dec="$1"
    # Convert to unsigned hex (printf %x handles negative as two's complement)
    local hex=$(printf '%08x' "$(( dec & 0xFFFFFFFF ))")
    # Reverse to little-endian (tac reverses pairs)
    echo "$hex" | tac -rs .. | tr -d '\n'
}

# Function to append binary shortcut entry to shortcuts.vdf
add_to_steam() {
    local vdf_path="$1"
    local app_id_dec="$2"
    local app_name="$3"
    local exe_path="$4"
    local launch_options="$5"
    local app_id_hex=$(dec_to_little_endian_hex "$app_id_dec")

    # Backup original
    local backup_vdf="${vdf_path}.backup.$(date +%s)"
    cp "$vdf_path" "$backup_vdf" 2>/dev/null

    # Read existing content as binary
    if [ -f "$vdf_path" ]; then
        # Truncate trailing nulls or braces if needed (script assumes clean file)
        truncate -s -2 "$vdf_path" 2>/dev/null
        local existing_content=$(cat "$vdf_path")
    else
        local existing_content=""
        # Create initial "shortcuts" block if file doesn't exist
        printf '\x00%s\x00' "shortcuts" > "$vdf_path"
    fi

    # Generate new set ID (simple increment; in full script, it's based on last set)
    local new_set_id=0  # Default for new file; extend to parse existing if needed

    # Build binary entry (VDF binary format: key types, null-terminated strings, etc.)
    # Structure from script: appid (int32), AppName (string), Exe (string), StartDir (string, default to exe dir),
    # icon (empty), LaunchOptions (string), IsHidden (int32=0), AllowDesktopConfig (int32=1),
    # AllowOverlay (int32=1), OpenVR (int32=0), tags (empty block), etc.
    local start_dir=$(dirname "$exe_path")
    local binary_entry=$(
        printf '\x00%d\x00' "$new_set_id" &&
        printf '\x02%s\x00%s' "appid" "$app_id_hex" &&
        printf '\x01%s\x00%s\x00' "AppName" "$app_name" &&
        printf '\x01%s\x00%s\x00' "Exe" "$exe_path" &&
        printf '\x01%s\x00%s\x00' "StartDir" "$start_dir" &&
        printf '\x01%s\x00\x00' "icon" &&  # Empty icon
        printf '\x01%s\x00%s\x00' "ShortcutPath" "" &&
        printf '\x01%s\x00%s\x00' "LaunchOptions" "$launch_options" &&
        printf '\x02%s\x00\x00\x00\x00\x00' "IsHidden" &&  # 0
        printf '\x02%s\x00\x01\x00\x00\x00' "AllowDesktopConfig" &&  # 1
        printf '\x02%s\x00\x01\x00\x00\x00' "AllowOverlay" &&  # 1
        printf '\x02%s\x00\x00\x00\x00\x00' "OpenVR" &&  # 0
        printf '\x02%s\x00\x00\x00\x00\x00' "Devkit" &&
        printf '\x01%s\x00\x00' "DevkitGameID" &&
        printf '\x02%s\x00\x00\x00\x00\x00' "DevkitOverrideAppID" &&
        printf '\x02%s\x00\x00\x00\x00\x00' "LastPlayTime" &&
        printf '\x01%s\x00\x00' "FlatpakAppID" &&
        printf '\x00%s\x00' "tags" &&  # Empty tags block
        printf '\x08\x08\x08\x08'  # End block (4 bytes of 08)
    )

    # Append to file
    printf '%s' "$binary_entry" >> "$vdf_path"

    echo "Added non-Steam game: $app_name (AppID: $app_id_dec)"
    echo "Restart Steam to see changes."
    echo "Backup created at $backup_vdf"
    return 0
}

# Wrapper for add_to_steam to handle path finding and AppID generation
add_to_steam_wrapper() {
    local exe_path="$1"
    local app_name="$2"
    local launch_options="$3"
    
    local vdf_path=$(find_steam_userdata)
    echo "Using shortcuts.vdf at: $vdf_path"

    # Generate unique AppID
    local seed="$app_name$exe_path"
    local app_id=$(generate_app_id "$seed")
    echo "Generated AppID: $app_id"

    # Add the entry
    add_to_steam "$vdf_path" "$app_id" "$app_name" "$exe_path" "$launch_options"
}

check_and_install_dependencies() {
  local missing_tools=()
  local tools=("curl" "unzip" "jq" "7z")
  
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
    zen_nospam --error --text="Required tools are missing. Please install them manually and run the installer again.\n\nRequired: unzip, curl, jq, 7z (via pacman)\nOptional: aria2c (via pacman)"
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
    
    if add_to_steam_wrapper "$main_exe" "Minecraft Bedrock (GDK)" "$LAUNCH_OPTIONS"; then
      zen_nospam --info --width=500 --height=200 --text="Minecraft Bedrock has been added to your Steam library!\n\nFinal Step:\nIn Steam, right-click 'Minecraft Bedrock (GDK)' -> Properties -> Compatibility, and select 'GE-Proton...'."
    else
      zen_nospam --error --text="Failed to add Minecraft to Steam library. Please check the error message and try again."
    fi
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

  # Add to Steam using our custom function
  if [[ "$install_option" == "full_install" || "$install_option" == "reinstall_minecraft" || "$install_option" == "add_to_steam" ]]; then
    local main_exe=$(find "$MINECRAFT_DIR" -name "Minecraft.Windows.exe" | head -n 1)
    if [[ -f "$main_exe" ]]; then
      if add_to_steam_wrapper "$main_exe" "Minecraft Bedrock (GDK)" "$LAUNCH_OPTIONS"; then
        zen_nospam --info --width=500 --height=250 --text="Installation complete!\n\n'Minecraft Bedrock (GDK)' has been added to your Steam library.\n\nFinal Step:\nIn Steam, right-click the game -> Properties -> Compatibility, and select 'GE-Proton...'.\n\nFor joystick support, you may need to install runtimes using Protontricks after setting the compatibility tool."
      else
        zen_nospam --error --text="Could not add Minecraft to Steam library. Please try again."
      fi
    else
      zen_nospam --error --text="Could not find the game executable. Please try reinstalling."
    fi
  fi
}

main
