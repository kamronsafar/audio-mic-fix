#!/bin/bash
set -euo pipefail

# Ranglar
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Xato boshqaruvi
handle_error() {
    echo -e "\n${RED}XATO: $2 (Qator: $1)${NC}"
    echo -e "${YELLOW}Skript to'xtatilmoqda...${NC}"
    
    # Tozalash
    if [ -d "${temp_dir:-}" ]; then
        rm -rf "$temp_dir"
    fi
    
    exit 1
}

trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR

# Paket mavjudligini tekshirish
check_package() {
    apt-cache show "$1" >/dev/null 2>&1
}

# URL mavjudligini tekshirish
check_url() {
    if ! wget --spider "$1" 2>/dev/null; then
        echo -e "${YELLOW}Diqqat: $2 URL topilmadi (404)${NC}"
        return 1
    fi
    return 0
}

main() {
    echo -e "\n${BLUE}=== Parrot OS Audio To'liq Tuzatish ===${NC}"
    
    # 1. Tizim yangilanishlari
    echo -e "\n${BLUE}[1/8] Tizim yangilanmoqda...${NC}"
    apt update -y
    apt upgrade -y

    # 2. Asosiy paketlar
    echo -e "\n${BLUE}[2/8] Asosiy paketlar o'rnatilmoqda...${NC}"
    required_packages=(
        alsa-base alsa-utils pulseaudio pavucontrol 
        pulseaudio-utils libasound2-plugins
        gstreamer1.0-alsa gstreamer1.0-pulseaudio
        git build-essential autoconf automake libtool
    )
    
    for pkg in "${required_packages[@]}"; do
        if check_package "$pkg"; then
            apt install -y "$pkg"
        else
            echo -e "${YELLOW}$pkg paketi topilmadi - o'tkazib yuborilmoqda${NC}"
        fi
    done

    3. GitHubdan kompilyatsiya
    echo -e "\n${BLUE}[3/8] ALSA manba kodi kompilyatsiya qilinmoqda...${NC}"
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    if check_url "https://github.com/alsa-project/alsa-lib.git" "ALSA manba kodi"; then
        git clone https://github.com/alsa-project/alsa-lib.git
        cd alsa-lib
        make -j$(nproc)
        make install
        ldconfig
    fi

    # 4. .deb paketlar - yangi URL bilan
    echo -e "\n${BLUE}[4/8] PulseAudio qo'shimcha modullari...${NC}"
    pulseaudio_deb_url="http://ftp.debian.org/debian/pool/main/p/pulseaudio/pulseaudio-module-zeroconf_$(pulseaudio --version | awk '{print $2}')_amd64.deb"
    
    if check_url "$pulseaudio_deb_url" "PulseAudio .deb paketi"; then
        wget "$pulseaudio_deb_url" -O pulseaudio.deb
        dpkg -i pulseaudio.deb || apt -f install -y
    fi
    
    # 1. Source kompilyatsiya qilish
    git clone https://gitlab.freedesktop.org/pulseaudio/pulseaudio.git
    cd pulseaudio
    meson build
    ninja -C build
    sudo ninja -C build install

    # 2. Static binary yuklab olish
    wget https://ftp.osuosl.org/pub/blfs/conglomeration/pulseaudio/pulseaudio-15.0.tar.xz
    tar xf pulseaudio-15.0.tar.xz
    cd pulseaudio-15.0
    ./configure && make
    sudo make install
    

    # 6. Snap/Flatpak
    echo -e "\n${BLUE}[6/8] Snap/Flatpak orqali audio dasturlar...${NC}"
    if ! command -v snap &> /dev/null; then
        if check_package "snapd"; then
            apt install -y snapd
            snap install core
        else
            echo -e "${YELLOW}snapd paketi topilmadi - o'tkazib yuborilmoqda${NC}"
        fi
    fi
    
    if command -v snap &> /dev/null; then
        snap install pulseaudio --classic || \
        echo -e "${YELLOW}PulseAudio Snap o'rnatishda muammo - davom etilmoqda${NC}"
    fi

    if ! command -v flatpak &> /dev/null; then
        if check_package "flatpak"; then
            apt install -y flatpak
            flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        else
            echo -e "${YELLOW}flatpak paketi topilmadi - o'tkazib yuborilmoqda${NC}"
        fi
    fi
    
    if command -v flatpak &> /dev/null; then
        flatpak install -y flathub org.pulseaudio.pulseaudio || \
        echo -e "${YELLOW}PulseAudio Flatpak o'rnatishda muammo - davom etilmoqda${NC}"
    fi

    # 7. Sozlamalar
    echo -e "\n${BLUE}[7/8] Audio sozlamalari o'rnatilmoqda...${NC}"
    usermod -aG audio,pulse,pulse-access "$SUDO_USER" || \
    echo -e "${YELLOW}Foydalanuvchi guruhlarini o'zgartirishda muammo${NC}"

    # 8. Test
    echo -e "\n${BLUE}[8/8] Audio tizimi test qilinmoqda...${NC}"
    echo -e "${GREEN}Ovoz balandligi sozlanmoqda...${NC}"
    amixer sset Master unmute && amixer sset Master 70% || \
    echo -e "${YELLOW}Ovoz balandligini sozlashda muammo${NC}"

    echo -e "\n${GREEN}Mikrofon testi (5 soniya)...${NC}"
    if arecord -l | grep -q "card"; then
        arecord -d 5 -f cd -t wav /tmp/test_mic.wav && {
            echo -e "${GREEN}Yozib olingan ovoz ijro etilmoqda...${NC}"
            aplay /tmp/test_mic.wav
            rm -f /tmp/test_mic.wav
        } || echo -e "${YELLOW}Mikrofon yozishda muammo${NC}"
    else
        echo -e "${YELLOW}Mikrofon topilmadi${NC}"
    fi

    # Tozalash
    rm -rf "$temp_dir"

    echo -e "\n${GREEN}=== Skript muvaffaqiyatli yakunlandi ===${NC}"
    echo -e "Agar muammolar davom etsa:"
    echo -e "1. 'pavucontrol' yordamida qo'lda sozlang"
    echo -e "2. Tizimni qayta ishga tushiring"
    echo -e "3. 'journalctl -xe' yoki 'dmesg' buyruqlari bilan xatolarni tekshiring"
}

main
