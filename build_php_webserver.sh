#!/bin/bash

# Định nghĩa màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ghi log toàn bộ output vào file
LOGFILE="/var/log/build_da.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo -e "\n================ Bắt đầu chạy script: $(date) ================\n"

# Biến đường dẫn và phiên bản DirectAdmin
custombuild='/usr/local/directadmin/custombuild'

# Hàm kiểm tra root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Script này cần chạy với quyền root!${NC}"
        exit 1
    fi
}

# Hàm lấy phiên bản DirectAdmin
get_da_version() {
    if [[ -f "/usr/local/directadmin/directadmin" ]]; then
        /usr/local/directadmin/directadmin v | awk '{print $3}' | cut -d. -f2,3
    else
        echo "0"
    fi
}

# Hàm kiểm tra service có chạy không
check_service() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✓ $service đang chạy${NC}"
        return 0
    else
        echo -e "${RED}✗ $service không chạy${NC}"
        return 1
    fi
}

# Hàm backup cấu hình
backup_config() {
    local config_file="$1"
    local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "$backup_file"
        echo -e "${GREEN}✓ Đã backup: $backup_file${NC}"
        return 0
    else
        echo -e "${RED}✗ Không tìm thấy file cấu hình: $config_file${NC}"
        return 1
    fi
}

# ========== HÀM CẬP NHẬT DIRECTADMIN ==========
doUpGrade() {
    echo -e "${YELLOW}Đang tải và cài đặt DirectAdmin...${NC}"
    
    # Kiểm tra kết nối internet
    if ! ping -c 1 google.com &> /dev/null; then
        echo -e "${RED}Không có kết nối internet!${NC}"
        return 1
    fi
    
    # Tải và cài đặt
    if wget -q core.cyberslab.net/install -O install; then
        chmod +x install
        ./install
        echo -e "${GREEN}✓ Đã nâng cấp DirectAdmin thành công${NC}"
        rm -f install
    else
        echo -e "${RED}✗ Không thể tải file cài đặt DirectAdmin${NC}"
        return 1
    fi
}

# ========== HÀM KIỂM TRA PHIÊN BẢN DIRECTADMIN ==========
doCheckVersionDA() {
    DA_VER=$(get_da_version)
    
    echo -e "${BLUE}Kiểm tra phiên bản DirectAdmin...${NC}"
    
    if [[ "$DA_VER" == "0" ]]; then
        echo -e "${RED}DirectAdmin chưa được cài đặt!${NC}"
        read -p "Bạn có muốn cài đặt DirectAdmin không? (y/N): " install_da
        if [[ "$install_da" =~ ^[Yy]$ ]]; then
            doUpGrade
            DA_VER=$(get_da_version)
        else
            exit 1
        fi
    elif [[ "$DA_VER" != "61" && "$DA_VER" != "62" ]]; then
        echo -e "${YELLOW}Phiên bản DirectAdmin cần nâng cấp (hiện tại: $DA_VER)${NC}"
        read -p "Bạn có muốn nâng cấp không? (y/N): " upgrade_confirm
        if [[ "$upgrade_confirm" =~ ^[Yy]$ ]]; then
            doUpGrade
            DA_VER=$(get_da_version)
        fi
    fi

    echo -e "${GREEN}DirectAdmin version hiện tại: ${RED}$DA_VER${NC}"
    echo -e "${NC}*********************************************"
    echo -e "${YELLOW}Bạn muốn thực hiện hành động nào?${NC}"
    echo -e "1. Build PHP"
    echo -e "2. Đổi Webserver"
    echo -e "3. Cả hai (Webserver + Build PHP)"
    echo -e "4. Kiểm tra trạng thái hệ thống"
    echo -e "5. Thoát${NC}"
    read -p "Lựa chọn của bạn (1/2/3/4/5): " action

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
            checkSystemStatus
            ;;
        5)
            echo -e "${YELLOW}Thoát script.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Lựa chọn không hợp lệ. Thoát.${NC}"
            exit 1
            ;;
    esac
}

# ========== HÀM KIỂM TRA TRẠNG THÁI HỆ THỐNG ==========
checkSystemStatus() {
    echo -e "${BLUE}=== KIỂM TRA TRẠNG THÁI HỆ THỐNG ===${NC}"
    
    # Kiểm tra webserver
    current_webserver=$(grep ^webserver= "$custombuild/options.conf" 2>/dev/null | cut -d= -f2)
    echo -e "${GREEN}Webserver hiện tại: ${YELLOW}${current_webserver:-"Không xác định"}${NC}"
    
    # Kiểm tra PHP versions
    echo -e "\n${GREEN}Phiên bản PHP được cấu hình:${NC}"
    for i in {1..4}; do
        php_ver=$(grep "^php${i}_release=" "$custombuild/options.conf" 2>/dev/null | cut -d= -f2)
        php_mode=$(grep "^php${i}_mode=" "$custombuild/options.conf" 2>/dev/null | cut -d= -f2)
        if [[ "$php_ver" != "no" && -n "$php_ver" ]]; then
            echo -e "  PHP$i: ${YELLOW}$php_ver${NC} (Mode: ${YELLOW}$php_mode${NC})"
        fi
    done
    
    # Kiểm tra services
    echo -e "\n${GREEN}Trạng thái services:${NC}"
    case $current_webserver in
        "apache")
            check_service "httpd"
            ;;
        "nginx_apache")
            check_service "nginx"
            check_service "httpd"
            ;;
        "openlitespeed")
            check_service "lsws"
            ;;
    esac
    
}

# ========== HÀM KIỂM TRA PHP HIỆN TẠI ==========
doCheckPHP() {
    if [[ ! -f "$custombuild/options.conf" ]]; then
        echo -e "${RED}Không tìm thấy file cấu hình custombuild!${NC}"
        return 1
    fi
    
    current_webserver=$(grep ^webserver= "$custombuild/options.conf" | cut -d= -f2)
    echo -e "${GREEN}Webserver đang sử dụng: ${YELLOW}$current_webserver${NC}"
    echo -e "${RED}Các phiên bản PHP đang được sử dụng:${NC}"
    
    for i in {1..4}; do
        php_release=$(grep "^php${i}_release=" "$custombuild/options.conf" | cut -d= -f2)
        php_mode=$(grep "^php${i}_mode=" "$custombuild/options.conf" | cut -d= -f2)
        if [[ "$php_release" != "no" && -n "$php_release" ]]; then
            echo -e "- PHP$i: ${YELLOW}$php_release${NC} (${BLUE}$php_mode${NC})"
        fi
    done
}

# ========== HÀM ĐỔI WEBSERVER ==========
changeWebServer() {
    if [[ ! -f "$custombuild/options.conf" ]]; then
        echo -e "${RED}Không tìm thấy file cấu hình custombuild!${NC}"
        return 1
    fi
    
    current_webserver=$(grep ^webserver= "$custombuild/options.conf" | cut -d= -f2)
    echo -e "${GREEN}Webserver hiện tại: ${YELLOW}$current_webserver${NC}"
    echo -e "${RED}Bạn có muốn thay đổi webserver không?${NC}"
    echo -e "${YELLOW}Các tùy chọn: apache, nginx_apache, openlitespeed${NC}"
    echo -e "${NC}Y/y : YES"
    echo -e "${NC}N/n : NO"
    read -p "Lựa chọn của bạn: " opt_web
    
    case $opt_web in
        YES|Y|y|yes)
            echo -e "${YELLOW}Các webserver hỗ trợ:${NC}"
            echo -e "1. apache"
            echo -e "2. nginx_apache" 
            echo -e "3. openlitespeed"
            read -p "Chọn webserver (1-3): " choice
            
            case $choice in
                1) new_webserver="apache" ;;
                2) new_webserver="nginx_apache" ;;
                3) new_webserver="openlitespeed" ;;
                *) 
                    echo -e "${RED}Lựa chọn không hợp lệ!${NC}"
                    return 1
                    ;;
            esac
            
            if [[ "$new_webserver" == "$current_webserver" ]]; then
                echo -e "${YELLOW}Webserver hiện tại đã là $new_webserver${NC}"
                return 0
            fi
            
            echo -e "${YELLOW}Đang cập nhật webserver thành $new_webserver...${NC}"
            
            # Kiểm tra custombuild directory
            if [[ ! -d "$custombuild" ]]; then
                echo -e "${RED}Lỗi: Không tìm thấy thư mục $custombuild${NC}"
                return 1
            fi
            
            cd "$custombuild" || exit 1
            
            # Backup current config
            backup_config "options.conf" || return 1
            
            # Set webserver
            echo -e "${YELLOW}Bước 1: Cập nhật cấu hình webserver...${NC}"
            ./build set webserver "$new_webserver"
            
            # Xử lý đặc biệt cho nginx_apache
            if [[ "$new_webserver" == "nginx_apache" ]]; then
                echo -e "${YELLOW}Kiểm tra php_mode cho nginx_apache...${NC}"
                php_mode=$(grep ^php1_mode= "$custombuild/options.conf" | cut -d= -f2)
                
                if [[ "$php_mode" == "lsphp" ]]; then
                    echo -e "${RED}Cảnh báo: php1_mode hiện tại là lsphp, không tương thích với nginx_apache.${NC}"
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
            
            # Build webserver
            echo -e "${YELLOW}Bước 3: Cài đặt $new_webserver...${NC}"
            if [[ "$new_webserver" == "openlitespeed" ]]; then
                # Cài đặt dependencies cho OpenLiteSpeed
                yum install -y wget curl gcc gcc-c++ make
                ./build openlitespeed
                if [[ $? -ne 0 ]]; then
                    echo -e "${RED}Lỗi: Không thể cài đặt OpenLiteSpeed. Thử lại...${NC}"
                    ./build clean
                    ./build openlitespeed
                fi
            else
                ./build "$new_webserver"
                if [[ $? -ne 0 ]]; then
                    echo -e "${RED}Lỗi: Không thể cài đặt $new_webserver${NC}"
                    return 1
                fi
            fi
            
            # Rewrite configs
            echo -e "${YELLOW}Bước 4: Cập nhật cấu hình...${NC}"
            ./build rewrite_confs
            
            # Restart services
            echo -e "${YELLOW}Bước 5: Khởi động lại services...${NC}"
            case $new_webserver in
                "openlitespeed")
                    systemctl restart lsws
                    systemctl enable lsws
                    echo -e "${GREEN}OpenLiteSpeed Admin Panel: https://$(hostname -I | awk '{print $1}'):7080${NC}"
                    echo -e "${GREEN}Default admin user: admin${NC}"
                    echo -e "${GREEN}Default admin pass: 123456${NC}"
                    ;;
                "nginx_apache")
                    systemctl restart nginx httpd
                    systemctl enable nginx httpd
                    ;;
                "apache")
                    systemctl restart httpd
                    systemctl enable httpd
                    ;;
            esac
            
            echo -e "${GREEN}✅ Đã đổi webserver thành $new_webserver thành công!${NC}"
            
            # Verify installation
            echo -e "${YELLOW}Kiểm tra trạng thái:${NC}"
            current_webserver_new=$(grep ^webserver= "$custombuild/options.conf" | cut -d= -f2)
            echo -e "${GREEN}Webserver trong config: $current_webserver_new${NC}"
            
            # Cleanup old backups (giữ 5 backup gần nhất)
            echo -e "${YELLOW}Dọn dẹp backup cũ...${NC}"
            ls -t options.conf.backup.* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
            ;;
        NO|N|no|n)
            echo -e "${YELLOW}Không đổi webserver.${NC}"
            ;;
        *)
            echo -e "${RED}Lựa chọn không hợp lệ.${NC}"
            return 1
            ;;
    esac
}

# ========== HÀM CẤU HÌNH VÀ BUILD PHP ==========
doBuild() {
    if [[ ! -d "$custombuild" ]]; then
        echo -e "${RED}Không tìm thấy thư mục custombuild!${NC}"
        return 1
    fi
    
    cd "$custombuild" || exit 1

    # Lấy webserver hiện tại
    current_webserver=$(grep ^webserver= "$custombuild/options.conf" | cut -d= -f2)
    echo -e "${GREEN}Webserver hiện tại: ${YELLOW}$current_webserver${NC}"

    # Gán php_mode theo webserver
    case $current_webserver in
        "openlitespeed")
            auto_php_mode="lsphp"
            ;;
        *)
            auto_php_mode="php-fpm"
            ;;
    esac

    echo -e "${BLUE}Chế độ PHP tự động: ${YELLOW}$auto_php_mode${NC}"

    # Nhập PHP release thủ công, mode tự động theo webserver
    echo -e "${YELLOW}Cấu hình các phiên bản PHP:${NC}"
    for i in {1..4}; do
        echo -e "${GREEN}--- PHP$i ---${NC}"
        read -p "Nhập php${i}_release (ví dụ: 8.1, 8.2, 8.3 hoặc để trống): " php_release
        
        if [[ -n "$php_release" ]]; then
            # Validate PHP version format
            if [[ ! "$php_release" =~ ^[5-8]\.[0-9]$ ]]; then
                echo -e "${RED}Định dạng PHP không hợp lệ! Sử dụng định dạng: x.y (ví dụ: 8.1)${NC}"
                continue
            fi
            
            ./build set php${i}_release "$php_release"
            ./build set php${i}_mode "$auto_php_mode"
            echo -e "${GREEN}✓ Đã cấu hình PHP$i: release=$php_release, mode=$auto_php_mode${NC}"
        else
            echo -e "${YELLOW}Không sử dụng PHP$i${NC}"
            ./build set php${i}_release "no"
        fi
    done

    echo -e "${YELLOW}Đang cài đặt thư viện cần thiết và build PHP...${NC}"
    
    # Cài đặt dependencies
    echo -e "${YELLOW}Cài đặt dependencies...${NC}"
    yum install -y libjpeg* libpng* freetype* curl-devel openssl-devel
    
    # Update custombuild
    echo -e "${YELLOW}Cập nhật custombuild...${NC}"
    ./build update
    
    # Build ICU (Unicode support)
    echo -e "${YELLOW}Build ICU...${NC}"
    ./build icu
    
    # Build PHP
    echo -e "${YELLOW}Build PHP (có thể mất nhiều thời gian)...${NC}"
    ./build php n
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Build PHP thành công${NC}"
        
        # Build phpMyAdmin
        echo -e "${YELLOW}Cài đặt phpMyAdmin...${NC}"
        ./build phpmyadmin
        
        # Rewrite configs
        echo -e "${YELLOW}Cập nhật cấu hình...${NC}"
        ./build rewrite_confs
        
        echo -e "${GREEN}✅ Hoàn tất build PHP!${NC}"
    else
        echo -e "${RED}✗ Build PHP thất bại!${NC}"
        return 1
    fi
}

# ========== MAIN ==========
main() {
    echo -e "${BLUE}DirectAdmin Management Script${NC}"
    echo -e "${BLUE}==============================${NC}"
    
    # Kiểm tra quyền root
    check_root
    
    # Kiểm tra DirectAdmin
    doCheckVersionDA
}

# Chạy script
main "$@"
