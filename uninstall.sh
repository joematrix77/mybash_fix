#!/bin/sh -e

# Define color codes using tput for better compatibility
RC=$(tput sgr0)
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)
GREEN=$(tput setaf 2)

LINUXTOOLBOXDIR="$HOME/linuxtoolbox"
PACKAGER=""
SUDO_CMD=""

print_colored() {
    color=$1
    message=$2
    printf "${color}%s${RC}\n" "$message"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

determine_package_manager() {
    PACKAGEMANAGER='nala apt dnf yum pacman zypper emerge xbps-install nix-env'
    for pgm in $PACKAGEMANAGER; do
        if command_exists "$pgm"; then
            PACKAGER="$pgm"
            printf "Using %s\n" "$pgm"
            break
        fi
    done

    if [ -z "$PACKAGER" ]; then
        print_colored "$RED" "Can't find a supported package manager"
        exit 1
    fi
}

determine_sudo_command() {
    if command_exists sudo; then
        SUDO_CMD="sudo"
    elif command_exists doas && [ -f "/etc/doas.conf" ]; then
        SUDO_CMD="doas"
    else
        SUDO_CMD="su -c"
    fi

    printf "Using %s as privilege escalation software\n" "$SUDO_CMD"
}

uninstall_dependencies() {
    DEPENDENCIES='bash-completion bat tree multitail fastfetch neovim trash-cli'

    print_colored "$YELLOW" "Uninstalling dependencies..."
    if [ "$PACKAGER" = "pacman" ]; then
        if command_exists yay; then
            yay -Rns --noconfirm ${DEPENDENCIES}
        elif command_exists paru; then
            paru -Rns --noconfirm ${DEPENDENCIES}
        else
            ${SUDO_CMD} pacman -Rns --noconfirm ${DEPENDENCIES}
        fi
    elif [ "$PACKAGER" = "nala" ] || [ "$PACKAGER" = "apt" ]; then
        ${SUDO_CMD} ${PACKAGER} purge -y ${DEPENDENCIES}
    elif [ "$PACKAGER" = "emerge" ]; then
        ${SUDO_CMD} ${PACKAGER} --deselect app-shells/bash-completion sys-apps/bat app-text/tree app-text/multitail app-misc/fastfetch app-editors/neovim app-misc/trash-cli
    elif [ "$PACKAGER" = "xbps-install" ]; then
        ${SUDO_CMD} xbps-remove -Ry ${DEPENDENCIES}
    elif [ "$PACKAGER" = "nix-env" ]; then
        ${SUDO_CMD} ${PACKAGER} -e bash-completion bat tree multitail fastfetch neovim trash-cli
    elif [ "$PACKAGER" = "dnf" ] || [ "$PACKAGER" = "yum" ]; then
        ${SUDO_CMD} ${PACKAGER} remove -y ${DEPENDENCIES}
    else
        ${SUDO_CMD} ${PACKAGER} remove -y ${DEPENDENCIES}
    fi
}

uninstall_font() {
    # Cover the font this fork installs (JetBrainsMono) and the upstream Meslo.
    for FONT_NAME in "JetBrainsMono Nerd Font" "MesloLGS Nerd Font Mono"; do
        FONT_DIR="$HOME/.local/share/fonts/$FONT_NAME"
        if [ -d "$FONT_DIR" ]; then
            print_colored "$YELLOW" "Removing font: $FONT_NAME"
            rm -rf "$FONT_DIR"
        fi
    done
    fc-cache -f >/dev/null 2>&1 || true
    print_colored "$GREEN" "Fonts removed"
}

uninstall_starship_and_fzf() {
    if command_exists starship; then
        print_colored "$YELLOW" "Uninstalling Starship..."
        ${SUDO_CMD} rm -f "$(command -v starship)"
        print_colored "$GREEN" "Starship uninstalled"
    fi

    if [ -d "$HOME/.fzf" ]; then
        print_colored "$YELLOW" "Uninstalling fzf..."
        "$HOME/.fzf/uninstall"
        rm -rf "$HOME/.fzf"
        print_colored "$GREEN" "fzf uninstalled"
    fi
}

uninstall_zoxide() {
    if command_exists zoxide; then
        print_colored "$YELLOW" "Uninstalling Zoxide..."
        ${SUDO_CMD} rm -f "$(command -v zoxide)"
        print_colored "$GREEN" "Zoxide uninstalled"
    fi
}

remove_configs() {
    USER_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
    BRC="$USER_HOME/.bashrc"
    MARKER="# >>> mybash loader (managed by setup.sh) >>>"

    print_colored "$YELLOW" "Removing configuration files..."

    # Restore the original ~/.bashrc. Our setup makes it either a symlink (old
    # behavior) or a real loader file containing $MARKER; handle both, and pull
    # the most recent timestamped backup that setup.sh created.
    if [ -L "$BRC" ] || { [ -f "$BRC" ] && grep -qF "$MARKER" "$BRC" 2>/dev/null; }; then
        BACKUP=$(ls -1t "$USER_HOME"/.bashrc.bak* 2>/dev/null | head -n1)
        rm -f "$BRC"
        if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
            mv "$BACKUP" "$BRC"
            print_colored "$GREEN" "Restored original .bashrc from $(basename "$BACKUP")"
        else
            print_colored "$YELLOW" "No .bashrc backup found; removed the mybash loader."
        fi
    fi

    # Keep ~/.bashrc_personal — it holds the user's own settings, not ours.
    if [ -f "$USER_HOME/.bashrc_personal" ]; then
        print_colored "$YELLOW" "Kept ~/.bashrc_personal (your custom settings)."
    fi

    # Remove linked configs and the theme picker (rm -f handles symlink or file).
    rm -f "$USER_HOME/.config/starship.toml"
    rm -f "$USER_HOME/.config/fastfetch/config.jsonc"
    rm -f "$USER_HOME/.local/bin/starship-theme"

    print_colored "$GREEN" "Configuration files removed"
}

# Undo the terminal font change setup.sh made (Ptyxis / GNOME Terminal).
reset_terminal_font() {
    command_exists gsettings || return 0
    SCHEMAS=$(gsettings list-schemas 2>/dev/null || true)

    if echo "$SCHEMAS" | grep -q '^org.gnome.Ptyxis$'; then
        gsettings set org.gnome.Ptyxis use-system-font true 2>/dev/null || true
        gsettings reset org.gnome.Ptyxis font-name 2>/dev/null || true
        print_colored "$GREEN" "Reset Ptyxis to the system font"
    fi

    if echo "$SCHEMAS" | grep -q '^org.gnome.Terminal.ProfilesList$'; then
        PROFILE=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
        if [ -n "$PROFILE" ]; then
            BASE="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/"
            gsettings set "$BASE" use-system-font true 2>/dev/null || true
            gsettings reset "$BASE" font 2>/dev/null || true
            print_colored "$GREEN" "Reset GNOME Terminal to the system font"
        fi
    fi
}

remove_linuxtoolbox() {
    if [ -d "$LINUXTOOLBOXDIR" ]; then
        print_colored "$YELLOW" "Removing linuxtoolbox directory..."
        rm -rf "$LINUXTOOLBOXDIR"
        print_colored "$GREEN" "linuxtoolbox directory removed"
    fi
}

# Argument parsing
KEEP_DEPS=0
for arg in "$@"; do
    case "$arg" in
        --keep-deps) KEEP_DEPS=1 ;;
        -h|--help)
            echo "Usage: ./uninstall.sh [--keep-deps]"
            echo
            echo "  --keep-deps  Keep installed software (system packages, fonts,"
            echo "               Starship, fzf, zoxide). Only remove the mybash config,"
            echo "               the starship-theme command, reset the terminal font,"
            echo "               and delete the ~/linuxtoolbox clone."
            exit 0
            ;;
        *)
            print_colored "$RED" "Unknown option: $arg (try --help)"
            exit 1
            ;;
    esac
done

# Main execution
if [ "$KEEP_DEPS" -eq 0 ]; then
    determine_package_manager
    determine_sudo_command
    uninstall_dependencies
    uninstall_font
    uninstall_starship_and_fzf
    uninstall_zoxide
else
    print_colored "$YELLOW" "--keep-deps: keeping packages, fonts, Starship, fzf, and zoxide."
fi
remove_configs
reset_terminal_font
remove_linuxtoolbox

print_colored "$GREEN" "Uninstallation complete. Please restart your shell for changes to take effect."