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
changeWebServer() {
    current_webserver=$(grep ^webserver= "$custombuild/options.conf" | cut -d= -f2)
    echo -e "${GREEN}Webserver hiện tại là: ${YELLOW}$current_webserver${NC}"
    echo -e "${RED}Bạn có muốn thay đổi webserver không?${NC} (apache, nginx_apache, openlitespeed)"
    echo -e "${NC}Y : YES"
    echo -e "${NC}N : NO"
    read -p "Lựa chọn của bạn: " opt_web
    
    case $opt_web in
        YES|Y|y|yes)
            echo -e "${YELLOW}Các webserver hỗ trợ:${NC}"
            echo -e "1. apache"
            echo -e "2. nginx_apache" 
            echo -e "3. openlitespeed"
            read -p "Nhập webserver muốn sử dụng: " new_webserver
            
            if [[ "$new_webserver" =~ ^(apache|nginx_apache|openlitespeed)$ ]]; then
                echo -e "${YELLOW}Đang cập nhật webserver thành $new_webserver...${NC}"
                
                # Kiểm tra custombuild directory
                if [[ ! -d "$custombuild" ]]; then
                    echo -e "${RED}Lỗi: Không tìm thấy thư mục $custombuild${NC}"
                    return 1
                fi
                
                cd "$custombuild" || exit 1
                
                # Backup current config
                cp options.conf options.conf.backup.$(date +%Y%m%d_%H%M%S)
                echo -e "${YELLOW}Đã backup file cấu hình hiện tại${NC}"
                
                # Set webserver
                echo -e "${YELLOW}Bước 1: Cập nhật cấu hình webserver...${NC}"
                ./build set webserver "$new_webserver"
				if [[ "$new_webserver" == "nginx_apache" ]]; then
				echo -e "${YELLOW}Đang kiểm tra php1_mode...${NC}"
				php_mode=$(grep ^php1_mode= "$custombuild/options.conf" | cut -d= -f2)

					if [[ "$php_mode" == "lsphp" ]]; then
					echo -e "${RED}Cảnh báo: php1_mode hiện tại là lsphp, không tương thích với nginx_apache nếu không có CloudLinux.${NC}"
					echo -e "${YELLOW}Tự động đổi php1_mode sang php-fpm...${NC}"
					./build set php1_mode php-fpm
					fi
				fi
                if [[ $? -ne 0 ]]; then
                    echo -e "${RED}Lỗi: Không thể cập nhật cấu hình webserver${NC}"
                    return 1
                fi
                
                # Update custombuild
                echo -e "${YELLOW}Bước 2: Cập nhật custombuild...${NC}"
                ./build update
                if [[ $? -ne 0 ]]; then
                    echo -e "${RED}Lỗi: Không thể cập nhật custombuild${NC}"
                    return 1
                fi
                
                # Build webserver với xử lý đặc biệt cho OpenLiteSpeed
                if [[ "$new_webserver" == "openlitespeed" ]]; then
                    echo -e "${YELLOW}Bước 3: Cài đặt OpenLiteSpeed (có thể mất vài phút)...${NC}"
                    # Cài đặt dependencies cho OpenLiteSpeed
                    yum install -y wget curl
                    ./build openlitespeed
                    if [[ $? -ne 0 ]]; then
                        echo -e "${RED}Lỗi: Không thể cài đặt OpenLiteSpeed${NC}"
                        echo -e "${YELLOW}Thử cài đặt thủ công...${NC}"
                        ./build clean
                        ./build openlitespeed
                    fi
                else
                    echo -e "${YELLOW}Bước 3: Cài đặt $new_webserver...${NC}"
                    ./build "$new_webserver"
                    if [[ $? -ne 0 ]]; then
                        echo -e "${RED}Lỗi: Không thể cài đặt $new_webserver${NC}"
                        return 1
                    fi
                fi
                
                # Rewrite configs
                echo -e "${YELLOW}Bước 4: Cập nhật cấu hình...${NC}"
                ./build rewrite_confs
                if [[ $? -ne 0 ]]; then
                    echo -e "${RED}Cảnh báo: Có lỗi khi rewrite configs${NC}"
                fi
                
                # Restart services
                if [[ "$new_webserver" == "openlitespeed" ]]; then
                    echo -e "${YELLOW}Bước 5: Khởi động lại OpenLiteSpeed...${NC}"
                    systemctl restart lsws
                    systemctl enable lsws
                    echo -e "${GREEN}OpenLiteSpeed Admin Panel: https://$(hostname -I | awk '{print $1}'):7080${NC}"
                    echo -e "${GREEN}Default admin user: admin${NC}"
                    echo -e "${GREEN}Default admin pass: 123456${NC}"
                else
                    echo -e "${YELLOW}Bước 5: Khởi động lại services...${NC}"
                    systemctl restart httpd
                    if [[ "$new_webserver" == "nginx_apache" ]]; then
                        systemctl restart nginx
                    fi
                fi
                
                echo -e "${GREEN}✅ Đã đổi webserver thành $new_webserver thành công!${NC}"
                
                # Verify installation
                echo -e "${YELLOW}Kiểm tra trạng thái webserver:${NC}"
                current_webserver_new=$(grep ^webserver= "$custombuild/options.conf" | cut -d= -f2)
                echo -e "${GREEN}Webserver trong config: $current_webserver_new${NC}"
                
            else
                echo -e "${RED}Giá trị không hợp lệ. Các tùy chọn: apache, nginx_apache, openlitespeed${NC}"
                return 1
            fi
            ;;
        NO|N|no|n)
            echo -e "${YELLOW}Không đổi webserver.${NC}"
            ;;
        *)
            echo -e "${RED}Lựa chọn không hợp lệ. Bỏ qua đổi webserver.${NC}"
            return 1
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
