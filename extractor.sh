#!/bin/bash

# Version of the script
VERSION="1.0.0"

# Function to show usage/help
show_help() {
    echo "Usage: $0 -a <archive> -as <multi-volume archive> -p <passwords file> [-d] [-sd]"
    echo "Options:"
    echo "  -a, --archive       Specify a single archive file or directory of the archive"
    echo "  -as, --archives     Specify a multi-volume archive file (for .7z split archives)"
    echo "  -p, --passwords     Specify the passwords file"
    echo "  -d, --delete        Delete the archive after successful extraction"
    echo "  -sd, --secure-delete Securely delete the archive after successful extraction"
    echo "  -h, --help          Show this help message"
    echo "  -v, --version       Show the version of the script"
    exit 1
}

# Function to install a specific package based on the system package manager
install_package() {
    local package=$1
    local manager=$2

    case $manager in
        apt) sudo apt update && sudo apt install -y "$package" ;;
        dnf) sudo dnf install -y "$package" ;;
        zypper) sudo zypper install -y "$package" ;;
        pacman) sudo pacman -Sy --noconfirm "$package" ;;
        emerge) sudo emerge "$package" ;;
        slackpkg) sudo slackpkg install "$package" ;;
        yum) sudo yum install -y "$package" ;;
        xbps-install) sudo xbps-install -Sy "$package" ;;
        apk) sudo apk add "$package" ;;
        *) echo "Unsupported package manager. Please install $package manually." ; exit 1 ;;
    esac
}

# Function to check and install a missing tool if needed
check_and_install() {
    local tool=$1
    local required=$2

    if ! command -v "$tool" &>/dev/null; then
        if [[ "$required" == true ]]; then
            echo "$tool is not installed."
            read -p "Would you like to install $tool? [y/N]: " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                # Detect package manager
                if command -v apt &>/dev/null; then
                    install_package "$tool" "apt"
                elif command -v dnf &>/dev/null; then
                    install_package "$tool" "dnf"
                elif command -v zypper &>/dev/null; then
                    install_package "$tool" "zypper"
                elif command -v pacman &>/dev/null; then
                    install_package "$tool" "pacman"
                elif command -v emerge &>/dev/null; then
                    install_package "$tool" "emerge"
                elif command -v slackpkg &>/dev/null; then
                    install_package "$tool" "slackpkg"
                elif command -v yum &>/dev/null; then
                    install_package "$tool" "yum"
                elif command -v xbps-install &>/dev/null; then
                    install_package "$tool" "xbps-install"
                elif command -v apk &>/dev/null; then
                    install_package "$tool" "apk"
                else
                    echo "Unsupported package manager. Please install $tool manually."
                    exit 1
                fi
            else
                echo "$tool is required to run this script. Exiting."
                exit 1
            fi
        fi
    fi
}

# Function to display the script version
show_version() {
    echo "Extractor $VERSION"
    exit 0
}

# Parse command-line arguments
delete_after_extract=false
secure_delete_after_extract=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--archive)
            archive="$2"
            shift 2
            ;;
        -as|--archives)
            multi_volume_archive="$2"
            shift 2
            ;;
        -p|--passwords)
            passwords_file="$2"
            shift 2
            ;;
        -d|--delete)
            delete_after_extract=true
            shift
            ;;
        -sd|--secure-delete)
            secure_delete_after_extract=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        -v|--version)
            show_version
            ;;
        *)
            show_help
            ;;
    esac
done

# Check if required arguments are provided
if [[ -z "$archive" && -z "$multi_volume_archive" ]] || [[ -z "$passwords_file" ]]; then
    show_help
fi

# Check if the password file exists
if [[ ! -f "$passwords_file" ]]; then
    echo "Password file not found: $passwords_file"
    exit 1
fi

# Set archive path
if [[ -n "$archive" ]]; then
    if [[ -d "$archive" ]]; then
        archive=$(find "$archive" -type f \( -name "*.7z" -o -name "*.rar" -o -name "*.zip" \) | head -n 1)
    elif [[ ! -f "$archive" ]]; then
        echo "Archive not found: $archive"
        exit 1
    fi
elif [[ -n "$multi_volume_archive" ]]; then
    if [[ -d "$multi_volume_archive" ]]; then
        multi_volume_archive=$(find "$multi_volume_archive" -type f -name "*.7z.001" | head -n 1)
    elif [[ ! -f "$multi_volume_archive" ]]; then
        echo "Multi-volume archive not found: $multi_volume_archive"
        exit 1
    fi
fi

# Function to attempt extraction with a password
attempt_extraction() {
    local archive_path="$1"
    local password="$2"
    local hidden_dir="./.$(date +%s%N)_temp_extract"

    mkdir -p "$hidden_dir"

    if [[ "$archive_path" == *.7z* ]]; then
        7z x -p"$password" "$archive_path" -o"$hidden_dir" -y &>/dev/null
    elif [[ "$archive_path" == *.rar ]]; then
        unrar x -p"$password" "$archive_path" "$hidden_dir" &>/dev/null
    elif [[ "$archive_path" == *.zip ]]; then
        unzip -P "$password" -d "$hidden_dir" "$archive_path" &>/dev/null
    else
        return 1
    fi

    local result=$?
    if [[ $result -ne 0 ]]; then
        rm -rf "$hidden_dir"
        return 1
    fi

    check_for_conflicts "$hidden_dir" "$archive_path"
}

# Function to check for file conflicts
check_for_conflicts() {
    local hidden_dir="$1"
    local archive_path="$2"
    local conflict_found=false

    for file in "$hidden_dir"/*; do
        if [[ -e "$(basename "$file")" ]]; then
            conflict_found=true
            echo "Conflict detected for file: $(basename "$file")"
            read -p "Choose an option: [O]verwrite, [N]ew name, [C]ancel: " choice
            case "$choice" in
                [Oo]) mv "$file" "$(basename "$file").bak" ;;
                [Nn]) read -p "Enter new name: " new_name; mv "$file" "$new_name" ;;
                [Cc]) return 1 ;;
                *) echo "Invalid option"; return 1 ;;
            esac
        fi
    done

    # Move files to the target location after checking for conflicts
    mv "$hidden_dir"/* .

    rm -rf "$hidden_dir"
    return 0
}

# Try to extract using each password in the file
successful=false
while read -r password; do
    if attempt_extraction "$archive" "$password"; then
        echo "Successfully extracted the archive using password: $password"
        successful=true
        break
    fi
done < "$passwords_file"

# If extraction was successful and the delete flag is set, delete the archive
if [[ "$successful" == true ]]; then
    if [[ "$delete_after_extract" == true ]]; then
        rm -f "$archive"
        echo "Archive deleted."
    fi

    if [[ "$secure_delete_after_extract" == true ]]; then
        secure-delete "$archive"
        echo "Archive securely deleted."
    fi
else
    echo "Failed to extract archive with any of the passwords."
fi
