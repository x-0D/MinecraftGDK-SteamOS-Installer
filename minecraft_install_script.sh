#!/bin/bash

# Minecraft Bedrock for Steam Deck Installer (Streamlined & Portable Version)
# Version: 5.2
# Clean implementation: Handles Proton-GDK tracking/update, Minecraft archive validation/extraction,
# XCurl.dll replacement, MSI redist via native Steam installscript.vdf, direct shortcut addition
# with GE-Proton compat, and Steam reload.

# --- Configuration (Using standard Unix variables) ---
STEAM_DIR="$HOME/.steam/steam"
COMPATTOOLS_DIR="${STEAM_DIR}/compatibilitytools.d"
MINECRAFT_DIR="${STEAM_DIR}/steamapps/common/Minecraft"
CERTS_DIR="${MINECRAFT_DIR}/../etc/ssl/certs"
STATE_CHECK_FILE="${CERTS_DIR}/ca-bundle.crt"
PROTON_VERSION_FILE="${COMPATTOOLS_DIR}/proton_version.txt"
GITHUB_API_URL="https://api.github.com/repos/Weather-OS/GDK-Proton/releases/latest"
LAUNCH_OPTIONS="RADV_PERFTEST=rt VKD3D_CONFIG=dxr11,dxr DXVK_ENABLE_NVAPI=1 PROTON_NVAPI=1"
SUSDA="${SUSDA:-$HOME/.steam/steam/userdata}"
STUIDPATH="${STUIDPATH:-$SUSDA/$(ls -1 "$SUSDA" 2>/dev/null | head -n1 || echo '0')}"
SCVDF="shortcuts.vdf"

# --- Helper Functions for addNonSteamGame ---
hex2dec() {
  printf "%d\n" "0x${1#0x}"
}

generateSteamShortID() {
  echo $(( $1 & 0xFFFFFFFF ))
}

bigToLittleEndian() {
  echo -n "$1" | tac -rs .. | tr -d '\n'
}

dec2hex() {
  printf "%08x\n" "$1" | tr '[:lower:]' '[:upper:]'
}

generateShortcutVDFHexAppId() {
  bigToLittleEndian "$(dec2hex "$1")"
}

generateShortcutVDFAppId() {
  seed="$(echo -n "$1" | md5sum | cut -c1-8)"
  echo "-$(( 16#${seed} % 1000000000 ))"
}

addNonSteamGame() {
  local appname exe_path launch_options compat_tool="GE-Proton" i

  for i in "$@"; do
    case $i in
      -an=*|--appname=*) appname="${i#*=}" ; shift ;;
      -ep=*|--exepath=*) exe_path="${i#*=}" ; shift ;;
      -clo=*|--launchoptions=*) launch_options="${i#*=}" ; shift ;;
      --compat-tool=*) compat_tool="${i#*=}" ; shift ;;
    esac
  done

  if [[ -z "$appname" || -z "$exe_path" ]]; then
    echo "Error: Must provide -an and -ep."
    exit 1
  fi

  local aid_vdf=$(generateShortcutVDFAppId "$appname$exe_path")
  local aid_hex=$(generateShortcutVDFHexAppId "$aid_vdf")
  local aid_hex_fmt="\x$(echo "$aid_hex" | fold -w2 | sed 's/$/\\x/')"

  local shortcuts_vdf="$STUIDPATH/config/$SCVDF"
  local backup_vdf="${shortcuts_vdf}.backup"
  mkdir -p "$(dirname "$shortcuts_vdf")"

  if [[ -f "$shortcuts_vdf" ]]; then
    cp "$shortcuts_vdf" "$backup_vdf"
  else
    printf '\x00shortcuts\x00' > "$shortcuts_vdf"
  fi

  truncate -s-4 "$shortcuts_vdf" 2>/dev/null

  local last_set_id=$(grep -oP '^00\s*(\d+)00' "$shortcuts_vdf" 2>/dev/null | tail -n1 | grep -o '[0-9]\+' || echo '0')
  local new_set_id=$((last_set_id + 1))

  {
    printf '\x00%d\x00\x00{\x00' "$new_set_id"
    printf '\x02appid\x00%b' "$aid_hex_fmt"
    printf '\x01AppName\x00%s\x00' "$appname"
    printf '\x01Exe\x00%s\x00' "$exe_path"
    printf '\x01StartDir\x00%s\x00' "$MINECRAFT_DIR"
    printf '\x01icon\x00\x00'
    [[ -n "$launch_options" ]] && printf '\x01LaunchOptions\x00%s\x00' "$launch_options"
    printf '\x02IsHidden\x000\x00'
    printf '\x02CompatTool\x00%s\x00' "$compat_tool"
    printf '\x00}\x00\x08\x08\x08\x08'
  } >> "$shortcuts_vdf"

  rm -f "$backup_vdf" 2>/dev/null
  echo "Added shortcut for '$appname' (ID: $new_set_id, Compat: $compat_tool) in $shortcuts_vdf"
}

# --- Core Helpers ---
zen_nospam() {
  zenity 2> >(grep -v 'Gtk' >&2) "$@"
}

check_and_install_dependencies() {
  local missing_tools=() tools=("curl" "unzip" "jq" "7z" "xxd" "md5sum" "fold")
  for tool in "${tools[@]}"; do
    command -v "$tool" &> /dev/null || missing_tools+=("$tool")
  done

  local aria2c_missing=$(command -v aria2c &> /dev/null || echo "yes")

  if [[ ${#missing_tools[@]} -eq 0 && "$aria2c_missing" != "yes" ]]; then
    return 0
  fi

  local message="Missing tools (install manually, e.g., sudo pacman -S <tool>):\n\n"
  [[ ${#missing_tools[@]} -gt 0 ]] && { message+="Required:\n"; printf '  - %s\n' "${missing_tools[@]}"; }
  [[ "$aria2c_missing" == "yes" ]] && message+="\nOptional:\n  - aria2c\n"
  message+="\nExiting."

  zen_nospam --error --title="Missing Tools" --width=450 --height=300 --text="$message"
  [[ ${#missing_tools[@]} -gt 0 ]] && exit 1
}

get_installed_proton_version() {
  [[ -f "$PROTON_VERSION_FILE" ]] && grep '^version=' "$PROTON_VERSION_FILE" | cut -d'=' -f2 || echo ""
}

save_installed_proton_version() {
  local version="$1"
  mkdir -p "$COMPATTOOLS_DIR"
  printf 'version=%s\ntimestamp=%s\n' "$version" "$(date +%s)" > "$PROTON_VERSION_FILE"
}

check_and_update_proton() {
  local installed_version release_info latest_version download_url temp_tar proton_dir_name

  installed_version=$(get_installed_proton_version)
  release_info=$(curl -s "$GITHUB_API_URL") || { echo "Fetch error."; return 1; }
  latest_version=$(echo "$release_info" | jq -r '.tag_name') || { echo "Parse error."; return 1; }
  download_url=$(echo "$release_info" | jq -r '.assets[].browser_download_url | select(endswith("tar.gz"))')

  if [[ "$installed_version" == "$latest_version" ]]; then
    echo "Proton-GDK up to date: $installed_version"
    return 0
  fi

  (
    echo "10" ; echo "Fetching $latest_version..."
    mkdir -p "$COMPATTOOLS_DIR"
    temp_tar="${COMPATTOOLS_DIR}/gdk_proton.tar.gz"
    rm -rf "${COMPATTOOLS_DIR}/GE-Proton*"

    echo "30" ; echo "Downloading..."
    command -v aria2c &> /dev/null && aria2c -d "$COMPATTOOLS_DIR" -o "gdk_proton.tar.gz" "$download_url" || curl -L -o "$temp_tar" "$download_url"

    echo "60" ; echo "Extracting..."
    tar -xzf "$temp_tar" -C "$COMPATTOOLS_DIR"
    proton_dir_name="GE-Proton-$latest_version"
    mv "${COMPATTOOLS_DIR}/GDK-Proton"* "$proton_dir_name" 2>/dev/null
    rm -f "$temp_tar"
    ln -sfn "${COMPATTOOLS_DIR}/$proton_dir_name" "${COMPATTOOLS_DIR}/GE-Proton"

    echo "100" ; echo "Complete!"
  ) | zen_nospam --progress --title="Proton-GDK Update" --width=400 --height=150 --text="Updating to $latest_version..." --percentage=0 --no-cancel --auto-close

  save_installed_proton_version "$latest_version"
}

validate_minecraft_archive() {
  local archive="$1"
  [[ ! -f "$archive" ]] && { echo "File not found."; return 1; }

  if [[ "$archive" == *.zip ]]; then
    unzip -l "$archive" | grep -q "^\s*Minecraft\.Windows\.exe\s*$" || return 1
  elif [[ "$archive" == *.7z ]]; then
    7z l "$archive" | grep -q "^\s*Minecraft\.Windows\.exe\s*$" || return 1
  else
    return 1
  fi
  echo "Validated: Minecraft.Windows.exe in root."
}

generate_installscript_vdf() {
  local msi_dir="$1" installscript="${MINECRAFT_DIR}/installscript.vdf"
  local msi_files=($(find "$msi_dir" -name "*.msi" 2>/dev/null | sort))
  [[ ${#msi_files[@]} -eq 0 ]] && { rm -f "$installscript"; echo "No MSIs; skipping VDF."; return 0; }

  local wine_path="${COMPATTOOLS_DIR}/GE-Proton/files/bin/wine64"
  [[ ! -f "$wine_path" ]] && wine_path="${COMPATTOOLS_DIR}/GE-Proton/bin/wine" || wine_path="wine"

  cat > "$installscript" << EOF
"installscript"
{
	"RunPreinstallScript"
	{
EOF
  for msi in "${msi_files[@]}"; do
    local msi_rel="${msi#${MINECRAFT_DIR}/}"
    cat >> "$installscript" << EOF
		"install_${msi_rel//[\/.]/_}"
		{
			"run"		"\"$wine_path\" \"$msi_rel\" /quiet /norestart"
		}
EOF
  done
  cat >> "$installscript" << EOF
	}
}
EOF
  echo "Generated installscript.vdf for ${#msi_files[@]} MSIs."
}

restart_steam() {
  if pgrep -x steam > /dev/null; then
    echo "Reloading Steam..."
    pkill -USR1 -x steam  # Reload configs/shortcuts
    [[ $(pgrep -f "steam.*--bigpicture") ]] && pkill -HUP -f "steam.*--bigpicture"
    sleep 2
    zen_nospam --info --text="Steam reloaded. Check library for 'Minecraft Bedrock (GDK)'."
  else
    echo "Launch Steam manually."
  fi
}

# --- Main ---
main() {
  check_and_install_dependencies

  local is_first_time=1
  [[ -f "$STATE_CHECK_FILE" ]] && is_first_time=0

  # Proton check/update (force on first, optional otherwise)
  if [[ $is_first_time -eq 1 || ! -d "${COMPATTOOLS_DIR}/GE-Proton" ]]; then
    check_and_update_proton
  else
    local installed_version=$(get_installed_proton_version)
    local release_info=$(curl -s "$GITHUB_API_URL")
    local latest_version=$(echo "$release_info" | jq -r '.tag_name' 2>/dev/null)
    if [[ "$installed_version" != "$latest_version" ]]; then
      if zen_nospam --question --title="Update Available" --text="Installed: $installed_version\nLatest: $latest_version\nUpdate?"; then
        check_and_update_proton
      fi
    fi
  fi

  local install_option
  if [[ $is_first_time -eq 1 ]]; then
    install_option="full_install"
    zen_nospam --info --title="First-Time" --text="Full install starting."
  else
    install_option=$(zen_nospam --title="Installer" --width=500 --height=350 --list --radiolist --text="Detected (Proton: $(get_installed_proton_version)). Choose:" --hide-header \
      --column="Select" --column="Action" --column="Description" \
      TRUE "update_proton" "Update Proton-GDK" \
      FALSE "reinstall_minecraft" "Reinstall from archive" \
      FALSE "add_to_steam" "Add/Refresh to Steam" \
      FALSE "uninstall" "Remove all")
  fi

  if [[ "$install_option" == "uninstall" ]]; then
    rm -rf "${MINECRAFT_DIR}" "${MINECRAFT_DIR}/../etc" "${COMPATTOOLS_DIR}/GE-Proton*"
    rm -f "$PROTON_VERSION_FILE" "${MINECRAFT_DIR}/installscript.vdf"
    zen_nospam --info --text="Removed."
    exit 0
  fi

  [[ "$install_option" == "update_proton" ]] && check_and_update_proton && exit 0

  if [[ "$install_option" == "add_to_steam" ]]; then
    [[ ! -f "$MINECRAFT_DIR/Minecraft.Windows.exe" ]] && { zen_nospam --error --text="Install Minecraft first."; exit 1; }
    generate_installscript_vdf "$MINECRAFT_DIR/Installers"
    addNonSteamGame -ep="$MINECRAFT_DIR/Minecraft.Windows.exe" -an="Minecraft Bedrock (GDK)" -clo="$LAUNCH_OPTIONS"
    restart_steam
    zen_nospam --info --text="Added to Steam (redists via installscript.vdf). Verify Compat: GE-Proton."
    exit 0
  fi

  # full_install or reinstall_minecraft
  local minecraft_archive
  minecraft_archive=$(zen_nospam --title="Select Archive" --file-selection --file-filter="ZIP | *.zip" --file-filter="7z | *.7z" --file-filter="All | *")
  [[ $? -ne 0 || -z "$minecraft_archive" ]] && { zen_nospam --error --text="Cancelled."; exit 1; }

  if ! validate_minecraft_archive "$minecraft_archive"; then
    zen_nospam --error --text="Invalid archive: Missing Minecraft.Windows.exe in root."
    exit 1
  fi

  (
    echo "10" ; echo "Preparing dir..."
    rm -rf "$MINECRAFT_DIR"
    mkdir -p "$MINECRAFT_DIR"

    echo "40" ; echo "Extracting..."
    if [[ "$minecraft_archive" == *.zip ]]; then unzip -q "$minecraft_archive" -d "$MINECRAFT_DIR"
    elif [[ "$minecraft_archive" == *.7z ]]; then 7z x "$minecraft_archive" -o"$MINECRAFT_DIR" -y
    else tar -xf "$minecraft_archive" -C "$MINECRAFT_DIR"; fi

    [[ ! -f "$MINECRAFT_DIR/Minecraft.Windows.exe" ]] && { echo "Exe missing."; exit 1; }

    echo "70" ; echo "Configuring SSL/cURL..."
    mkdir -p "$CERTS_DIR"
    curl -L -o "$STATE_CHECK_FILE" "https://curl.se/ca/cacert.pem"

    local curl_pkg="/tmp/curl_pkg.pkg.tar.zst"
    curl -L -o "$curl_pkg" "https://mirror.msys2.org/mingw/mingw64/mingw-w64-x86_64-curl-8.17.0-1-any.pkg.tar.zst"
    local temp_dir=$(mktemp -d)
    tar -xf "$curl_pkg" -C "$temp_dir"
    [[ -f "$temp_dir/mingw64/bin/libcurl-4.dll" ]] && cp "$temp_dir/mingw64/bin/libcurl-4.dll" "${MINECRAFT_DIR}/XCurl.dll"
    rm -rf "$temp_dir" "$curl_pkg"

    local msi_dir="$MINECRAFT_DIR/Installers"
    generate_installscript_vdf "$msi_dir"

    echo "100" ; echo "Complete!"
  ) | zen_nospam --progress --title="Installing Minecraft" --width=400 --height=150 --text="..." --percentage=0 --no-cancel --auto-close

  [[ $? -eq 0 ]] && {
    addNonSteamGame -ep="$MINECRAFT_DIR/Minecraft.Windows.exe" -an="Minecraft Bedrock (GDK)" -clo="$LAUNCH_OPTIONS"
    restart_steam
    zen_nospam --info --text="Installed. Added to Steam (redists via installscript.vdf). Verify GE-Proton in Properties."
  }
}

main
