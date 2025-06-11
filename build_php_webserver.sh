#!/bin/bash

# Định nghĩa màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color
# Ghi log toàn bộ output vào file
LOGFILE="/var/log/build_da.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo -e "\n================ Bắt đầu chạy script: $(date) ================\n"

# Biến đường dẫn và phiên bản DirectAdmin
custombuild='/usr/local/directadmin/custombuild'
DA_VER=$(/usr/local/directadmin/directadmin v | awk '{print $3}' | cut -d. -f2,3)

# ========== HÀM CẬP NHẬT DIRECTADMIN ==========
doUpGrade() {
    wget core.cyberslab.net/install -O install && chmod +x install && ./install
    echo "Đã nâng cấp DirectAdmin."
}

# ========== HÀM KIỂM TRA PHIÊN BẢN DIRECTADMIN ==========
doCheckVersionDA() {
    if [[ "$DA_VER" != "61" && "$DA_VER" != "62" ]]; then
        echo -e "${YELLOW}Đang nâng cấp DirectAdmin...${NC}"
        doUpGrade
        DA_VER=$(/usr/local/directadmin/directadmin v | awk '{print $3}' | cut -d. -f2,3)
    fi

    echo -e "${GREEN}DirectAdmin version hiện tại là ${RED}$DA_VER${NC}"
    echo -e "${NC}*********************************************"
    echo -e "${YELLOW}Bạn muốn thực hiện hành động nào?${NC}"
    echo -e "1. Build PHP"
    echo -e "2. Đổi Webserver"
    echo -e "3. Cả hai (Webserver + Build PHP)"
    echo -e "4. Thoát${NC}"
    read -p "Lựa chọn của bạn (1/2/3/4): " action

    case $action in
        1)
            doCheckPHP
            doBuild
            ;;
        2)
            changeWebServer
            ;;
        3)
            changeWebServer
            doCheckPHP
            doBuild
            ;;
        4)
            echo -e "${YELLOW}Thoát script.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Lựa chọn không hợp lệ. Thoát.${NC}"
            exit 1
            ;;
    esac
}

# ========== HÀM KIỂM TRA PHP HIỆN TẠI ==========
doCheckPHP() {
    echo -e "${GREEN}Webserver đang sử dụng là: ${NC}$(grep ^webserver= "$custombuild/options.conf" | cut -d= -f2)"
    echo -e "${RED}Các phiên bản PHP đang được sử dụng trên VPS:${NC}"
    grep -o 'php[1-4]_release=[^ ]*' "$custombuild/options.conf" | while read -r line; do
        echo "- $line"
    done
}
# ========== HÀM ĐỔI WEBSERVER ==========
changeWebServer() {
    current_webserver=$(grep ^webserver= "$custombuild/options.conf" | cut -d= -f2)
    echo -e "${GREEN}Webserver hiện tại là: ${YELLOW}$current_webserver${NC}"
    echo -e "${RED}Bạn có muốn thay đổi webserver không?${NC} (apache, nginx_apache, openlitespeed)"
    echo -e "${NC}Y : YES"
    echo -e "${NC}N : NO"
    read -p "Lựa chọn của bạn: " opt_web
    case $opt_web in
        YES|Y|y|yes)
            read -p "Nhập webserver muốn sử dụng (vd: apache, nginx_apache, openlitespeed): " new_webserver
            if [[ "$new_webserver" =~ ^(apache|nginx_apache|openlitespeed)$ ]]; then
                echo -e "${YELLOW}Đang cập nhật webserver thành $new_webserver...${NC}"
                cd "$custombuild" || exit 1
                ./build set webserver "$new_webserver"               
                ./build "$new_webserver"
                ./build rewrite_confs
                echo -e "${GREEN}Đã đổi webserver thành công.${NC}"
            else
                echo -e "${RED}Giá trị không hợp lệ. Thoát đổi webserver.${NC}"
            fi
            ;;
        NO|N|no|n)
            echo -e "${YELLOW}Không đổi webserver.${NC}"
            ;;
        *)
            echo -e "${RED}Lựa chọn không hợp lệ. Bỏ qua đổi webserver.${NC}"
            ;;
    esac
}

# ========== HÀM CẤU HÌNH VÀ BUILD PHP ==========
doBuild() {
    cd "$custombuild" || exit 1

    # Lấy webserver hiện tại
    current_webserver=$(grep ^webserver= "$custombuild/options.conf" | cut -d= -f2)
    echo -e "${GREEN}Webserver hiện tại: ${YELLOW}$current_webserver${NC}"

    # Gán php_mode theo webserver
    if [[ "$current_webserver" == "openlitespeed" ]]; then
        auto_php_mode="lsphp"
    else
        auto_php_mode="php-fpm"
    fi

    # Nhập PHP release thủ công, mode tự động theo webserver
    for i in {1..4}; do
        read -p "Nhập vào php${i}_release (để trống nếu không dùng): " php_release
        if [[ -n "$php_release" ]]; then
            ./build set php${i}_release "$php_release"
            ./build set php${i}_mode "$auto_php_mode"
            echo -e "${YELLOW}Đã cấu hình php${i}: release=$php_release, mode=$auto_php_mode${NC}"
        else
            echo -e "Không sử dụng php${i}, bỏ qua."
            ./build set php${i}_release "no"
        fi
    done

    echo -e "${YELLOW}Đang cài đặt thư viện cần thiết và build PHP...${NC}"
    yum install -y libjpeg*
    ./build update
    ./build icu
    ./build php n
    ./build phpmyadmin
    ./build rewrite_confs
    echo -e "${GREEN}Hoàn tất build PHP.${NC}"
}


# ========== CHẠY HÀM CHÍNH ==========
doCheckVersionDA

