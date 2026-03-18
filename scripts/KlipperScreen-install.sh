#!/bin/bash

# 기본 설정값 고정 (질문 생략용)
SERVICE="y"
BACKEND="X"
NETWORK="y"
START=1

SCRIPTPATH=$(dirname -- "$(readlink -f -- "$0")")
KSPATH=$(dirname "$SCRIPTPATH")
KSENV="${KLIPPERSCREEN_VENV:-${HOME}/.KlipperScreen-env}"

XSERVER="xinit xinput x11-xserver-utils xserver-xorg-input-evdev xserver-xorg-input-libinput xserver-xorg-legacy xserver-xorg-video-fbdev"
CAGE="cage seatd xwayland"
PYGOBJECT="libgirepository1.0-dev gcc libcairo2-dev pkg-config python3-dev gir1.2-gtk-3.0"
MISC="librsvg2-common libopenjp2-7 libdbus-glib-1-dev autoconf python3-venv"
OPTIONAL="fonts-nanum fonts-ipafont libmpv-dev"

Red='\033[0;31m'
Green='\033[0;32m'
Cyan='\033[0;36m'
Normal='\033[0m'

echo_text () { printf "${Normal}$1${Cyan}\n"; }
echo_error () { printf "${Red}$1${Normal}\n"; }
echo_ok () { printf "${Green}$1${Normal}\n"; }

# 함수 정의 시작
install_graphical_backend() {
    echo_text "Installing Xserver (Default)"
    if sudo apt install -y $XSERVER; then
        echo_ok "Installed X"
        sudo tee /etc/X11/Xwrapper.config > /dev/null << EOF
allowed_users=anybody
needs_root_rights=yes
EOF
    else
        echo_error "Installation of X-server failed"
        exit 1
    fi
}

install_packages() {
    echo_text "Update package data"
    sudo apt update
    sudo apt install -y $OPTIONAL $PYGOBJECT $MISC
}

check_requirements() {
    VERSION="3,8"
    if ! python3 -c 'import sys; exit(1) if sys.version_info <= ('$VERSION') else exit(0)'; then
        echo_error 'Python 3.8+ required'
        exit 1
    fi
}

create_virtualenv() {
    if [ -d "$KSENV" ]; then rm -rf "${KSENV}"; fi
    python3 -m venv "${KSENV}"
    source "${KSENV}/bin/activate"
    pip install --upgrade pip setuptools
    pip install -r ${KSPATH}/scripts/KlipperScreen-requirements.txt --prefer-binary
    deactivate
}

install_systemd_service() {
    SERVICE_CONTENT=$(cat "$SCRIPTPATH"/KlipperScreen.service)
    SERVICE_CONTENT=${SERVICE_CONTENT//KS_USER/$USER}
    SERVICE_CONTENT=${SERVICE_CONTENT//KS_ENV/$KSENV}
    SERVICE_CONTENT=${SERVICE_CONTENT//KS_DIR/$KSPATH}
    SERVICE_CONTENT=${SERVICE_CONTENT//KS_BACKEND/$BACKEND}
    echo "$SERVICE_CONTENT" | sudo tee /etc/systemd/system/KlipperScreen.service > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable KlipperScreen
    sudo adduser "$USER" tty
}

create_policy() {
    sudo groupadd -f klipperscreen
    sudo groupadd -f network
    sudo adduser "$USER" netdev
    sudo adduser "$USER" network
    RULE_FILE="/usr/share/polkit-1/rules.d/KlipperScreen.rules"
    sudo tee ${RULE_FILE} > /dev/null << EOF
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0 && subject.isInGroup("network")) {
        return polkit.Result.YES;
    }
});
EOF
}

# 메인 실행 로직
if [ "$EUID" == 0 ]; then echo_error "Run as normal user, not root"; exit 1; fi

check_requirements
install_graphical_backend
install_systemd_service
install_packages
create_virtualenv
create_policy
mkdir -p "$HOME"/.local/share/applications/
cp "$SCRIPTPATH"/KlipperScreen.desktop "$HOME"/.local/share/applications/KlipperScreen.desktop

# 네트워크 매니저 설치 및 재부팅
echo_ok "Installing NetworkManager and Rebooting..."
sudo apt install -y network-manager
sudo systemctl enable NetworkManager
sync
sudo reboot