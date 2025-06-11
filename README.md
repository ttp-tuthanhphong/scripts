# Build PHP Webserver Script

## Hướng dẫn cài đặt

### Step 1: Tải script
```bash
curl -O https://raw.githubusercontent.com/ttp-tuthanhphong/scripts/main/build-php.sh
```

### Step 2: Kích hoạt alias
```bash
source build-php.sh && rm -f build-php.sh
```

### Step 3: Chạy script
```bash
build-php
```

### Kiểm tra log
Kiểm tra log tại đường dẫn sau:
```bash
tail -f /var/log/build_da.log
```

### Xóa alias hoàn toàn và làm sạch
```bash
# Xóa alias
unalias build-php 2>/dev/null

# Xóa script đã tải (nếu có)
rm -f build-php.sh build_php_webserver.sh

# Reload shell
exec bash
```

## Lưu ý
- Script cần chạy với quyền root
- Hỗ trợ DirectAdmin phiên bản 6.1 trở lên
- Hỗ trợ các webserver: Apache, Nginx+Apache, OpenLiteSpeed
