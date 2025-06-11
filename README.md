# Build PHP Webserver Script

## Hướng dẫn cài đặt

### Step 1: Tải script
```bash
curl -O https://raw.githubusercontent.com/ttp-tuthanhphong/scripts/main/build-php.sh
```

### Step 2: Kích hoạt alias
```bash
source build-php.sh
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

## Lưu ý
- Script cần chạy với quyền root
- Hỗ trợ DirectAdmin phiên bản 6.1 trở lên
- Hỗ trợ các webserver: Apache, Nginx+Apache, OpenLiteSpeed
