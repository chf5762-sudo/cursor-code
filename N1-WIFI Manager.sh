#!/bin/bash

################################################################################
# N1-WIFI Manager - 单文件完整版
# 功能：AP热点配置 + Web界面 + 自动切换
# 适用：Armbian及所有支持NetworkManager的Linux物联网设备
# 管理IP：192.168.1.1 (Web界面访问，无需账号密码)
################################################################################

set -e

INSTALL_DIR="/opt/n1-wifi-manager"
CONFIG_FILE="/etc/wifi-config.conf"
LOG_FILE="$INSTALL_DIR/logs/wifi-setup.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：此脚本需要root权限${NC}"
        echo -e "${YELLOW}请使用: sudo bash $0${NC}"
        exit 1
    fi
}

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

################################################################################
# 安装函数
################################################################################

install_system() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  N1-WIFI Manager 安装程序${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    check_root
    
    # 创建目录
    echo -e "${CYAN}创建目录结构...${NC}"
    mkdir -p "$INSTALL_DIR"/{www/cgi-bin,logs}
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # 创建配置文件
    touch "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    
    # 写入所有脚本文件
    create_ap_startup_script
    create_countdown_daemon
    create_switch_sta_script
    create_web_server_script
    create_stop_services_script
    create_cgi_scripts
    create_web_interface
    create_systemd_service
    
    # 设置权限
    chmod +x "$INSTALL_DIR"/*.sh
    chmod +x "$INSTALL_DIR"/www/cgi-bin/*.sh
    
    # 安装服务
    systemctl daemon-reload
    systemctl enable n1-wifi-setup.service
    
    echo ""
    echo -e "${GREEN}✓ 安装完成！${NC}"
    echo ""
    echo -e "${YELLOW}使用方法：${NC}"
    echo -e "  ${GREEN}sudo systemctl start n1-wifi-setup${NC}   # 立即启动AP配置模式"
    echo -e "  ${GREEN}sudo systemctl stop n1-wifi-setup${NC}    # 停止服务"
    echo -e "  ${GREEN}sudo systemctl status n1-wifi-setup${NC}  # 查看状态"
    echo ""
    echo -e "${YELLOW}查看日志：${NC}"
    echo -e "  ${GREEN}tail -f $LOG_FILE${NC}"
    echo ""
    echo -e "${YELLOW}重启后自动生效，或立即测试：${NC}"
    echo -e "  ${GREEN}sudo systemctl start n1-wifi-setup${NC}"
    echo ""
}

################################################################################
# 创建 AP 启动脚本
################################################################################

create_ap_startup_script() {
    cat > "$INSTALL_DIR/ap-startup.sh" << 'EOFSCRIPT'
#!/bin/bash

LOG_FILE="/opt/n1-wifi-manager/logs/wifi-setup.log"
AP_NAME="N1-AP-Setup"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "========== AP模式启动 =========="

# 确保WiFi已启用
nmcli radio wifi on
sleep 1

# 删除旧的AP连接
nmcli connection delete "$AP_NAME" 2>/dev/null

# 创建AP连接
log "创建AP连接配置..."
nmcli connection add type wifi ifname wlan0 \
    con-name "$AP_NAME" \
    autoconnect no \
    ssid "N1-Setup" \
    mode ap \
    802-11-wireless.band bg \
    802-11-wireless.channel 6 \
    ipv4.method shared \
    ipv4.addresses 192.168.1.1/24 >> "$LOG_FILE" 2>&1

# 启动AP
log "启动AP热点..."
nmcli connection up "$AP_NAME" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "✓ AP模式启动成功 (SSID: N1-Setup, IP: 192.168.1.1)"
    date +%s > /tmp/ap-start-time
    exit 0
else
    log "✗ AP模式启动失败"
    exit 1
fi
EOFSCRIPT
}

################################################################################
# 创建倒计时守护进程
################################################################################

create_countdown_daemon() {
    cat > "$INSTALL_DIR/countdown-daemon.sh" << 'EOFSCRIPT'
#!/bin/bash

LOG_FILE="/opt/n1-wifi-manager/logs/wifi-setup.log"
CONFIG_FLAG="/tmp/wifi-user-configured"
AP_TIMEOUT=30
TOTAL_TIMEOUT=60

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "========== 倒计时守护进程启动 =========="
log "AP超时: ${AP_TIMEOUT}秒, 总超时: ${TOTAL_TIMEOUT}秒"

START_TIME=$(date +%s)
AP_DETECTED=false

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    REMAINING=$((TOTAL_TIMEOUT - ELAPSED))
    
    # 检查AP是否在运行
    if ! $AP_DETECTED; then
        if nmcli connection show --active | grep -q "N1-AP-Setup"; then
            log "✓ AP信号已建立"
            AP_DETECTED=true
        elif [ $ELAPSED -ge $AP_TIMEOUT ]; then
            log "✗ 30秒内未建立AP信号，切换到STA模式"
            /opt/n1-wifi-manager/switch-to-sta.sh
            exit 0
        fi
    fi
    
    # 检查用户配置
    if [ -f "$CONFIG_FLAG" ]; then
        log "✓ 检测到用户配置，立即切换"
        sleep 2
        /opt/n1-wifi-manager/switch-to-sta.sh
        exit 0
    fi
    
    # 检查总超时
    if [ $ELAPSED -ge $TOTAL_TIMEOUT ]; then
        log "⏱ 60秒超时，切换到STA模式"
        /opt/n1-wifi-manager/switch-to-sta.sh
        exit 0
    fi
    
    # 记录
    if [ $((ELAPSED % 10)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        log "⏳ 剩余时间: ${REMAINING}秒"
    fi
    
    sleep 1
done
EOFSCRIPT
}

################################################################################
# 创建切换到STA模式脚本
################################################################################

create_switch_sta_script() {
    cat > "$INSTALL_DIR/switch-to-sta.sh" << 'EOFSCRIPT'
#!/bin/bash

LOG_FILE="/opt/n1-wifi-manager/logs/wifi-setup.log"
CONFIG_FILE="/etc/wifi-config.conf"
AP_NAME="N1-AP-Setup"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "========== 切换到STA模式 =========="

# 停止Web服务
pkill -f "busybox httpd" 2>/dev/null
log "✓ Web服务已停止"

# 关闭AP
nmcli connection down "$AP_NAME" >> "$LOG_FILE" 2>&1
log "✓ AP模式已关闭"

sleep 2

# 检查配置
if [ ! -s "$CONFIG_FILE" ]; then
    log "⚠ 无已保存的WiFi配置"
    rm -f /tmp/wifi-user-configured /tmp/ap-start-time
    exit 0
fi

# 读取第一个WiFi配置
WIFI_LINE=$(head -n 1 "$CONFIG_FILE")
SSID=$(echo "$WIFI_LINE" | cut -d'|' -f1)
ENCODED_PASSWORD=$(echo "$WIFI_LINE" | cut -d'|' -f2)
PASSWORD=$(echo -n "$ENCODED_PASSWORD" | base64 -d)

log "尝试连接到: $SSID"

# 连接WiFi
nmcli dev wifi connect "$SSID" password "$PASSWORD" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    log "✓ 成功连接到: $SSID"
    IP=$(ip -4 addr show wlan0 2>/dev/null | grep inet | awk '{print $2}')
    log "✓ 获取IP: $IP"
else
    log "✗ 连接失败: $SSID"
fi

# 清理
rm -f /tmp/wifi-user-configured /tmp/ap-start-time

log "========== 切换完成 =========="
EOFSCRIPT
}

################################################################################
# 创建Web服务器启动脚本
################################################################################

create_web_server_script() {
    cat > "$INSTALL_DIR/start-web.sh" << 'EOFSCRIPT'
#!/bin/bash

WEB_ROOT="/opt/n1-wifi-manager/www"
LOG_FILE="/opt/n1-wifi-manager/logs/wifi-setup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 确保CGI可执行
chmod +x "$WEB_ROOT/cgi-bin/"*.sh

# 创建httpd配置
cat > /opt/n1-wifi-manager/httpd.conf << 'EOF'
*.sh:/cgi-bin
EOF

# 启动busybox httpd
busybox httpd -p 80 -h "$WEB_ROOT" -c /opt/n1-wifi-manager/httpd.conf 2>&1

if [ $? -eq 0 ]; then
    log "✓ Web服务已启动 (http://192.168.1.1)"
else
    log "✗ Web服务启动失败"
fi
EOFSCRIPT
}

################################################################################
# 创建停止服务脚本
################################################################################

create_stop_services_script() {
    cat > "$INSTALL_DIR/stop-services.sh" << 'EOFSCRIPT'
#!/bin/bash

LOG_FILE="/opt/n1-wifi-manager/logs/wifi-setup.log"

pkill -f countdown-daemon.sh 2>/dev/null
pkill -f "busybox httpd" 2>/dev/null
nmcli connection down N1-AP-Setup 2>/dev/null

echo "[$(date)] 所有服务已停止" >> "$LOG_FILE"
EOFSCRIPT
}

################################################################################
# 创建CGI脚本
################################################################################

create_cgi_scripts() {
    # 扫描WiFi
    cat > "$INSTALL_DIR/www/cgi-bin/scan_wifi.sh" << 'EOFSCRIPT'
#!/bin/bash

echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo ""

nmcli dev wifi rescan 2>/dev/null
sleep 3

echo "["
first=true
nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null | grep -v "^--" | grep -v "^$" | while IFS=: read -r ssid signal security; do
    [ -z "$ssid" ] && continue
    
    if [ "$first" = false ]; then
        echo ","
    fi
    first=false
    
    ssid_escaped=$(echo "$ssid" | sed 's/\\/\\\\/g; s/"/\\"/g')
    security_escaped=$(echo "$security" | sed 's/\\/\\\\/g; s/"/\\"/g')
    
    echo -n "  {\"ssid\":\"$ssid_escaped\",\"signal\":$signal,\"security\":\"$security_escaped\"}"
done
echo ""
echo "]"
EOFSCRIPT

    # 保存配置
    cat > "$INSTALL_DIR/www/cgi-bin/save_config.sh" << 'EOFSCRIPT'
#!/bin/bash

CONFIG_FILE="/etc/wifi-config.conf"
CONFIG_FLAG="/tmp/wifi-user-configured"
LOG_FILE="/opt/n1-wifi-manager/logs/wifi-setup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo ""

read POST_DATA

urldecode() {
    echo -e "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-F][0-9A-F]\)/\\x\1/g')"
}

SSID=$(echo "$POST_DATA" | grep -oP 'ssid=\K[^&]*')
PASSWORD=$(echo "$POST_DATA" | grep -oP 'password=\K[^&]*')

SSID=$(urldecode "$SSID")
PASSWORD=$(urldecode "$PASSWORD")

if [ -z "$SSID" ]; then
    echo '{"status":"error","message":"SSID不能为空"}'
    exit 1
fi

if [ -z "$PASSWORD" ]; then
    echo '{"status":"error","message":"密码不能为空"}'
    exit 1
fi

log "收到配置: SSID=$SSID"

ENCODED_PASSWORD=$(echo -n "$PASSWORD" | base64)

sed -i "/^${SSID}|/d" "$CONFIG_FILE" 2>/dev/null

echo "${SSID}|${ENCODED_PASSWORD}" | cat - "$CONFIG_FILE" > /tmp/wifi-config.tmp 2>/dev/null
mv /tmp/wifi-config.tmp "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

touch "$CONFIG_FLAG"

log "✓ 配置已保存"

echo '{"status":"success","message":"配置已保存，正在连接..."}'
EOFSCRIPT

    # 获取状态
    cat > "$INSTALL_DIR/www/cgi-bin/get_status.sh" << 'EOFSCRIPT'
#!/bin/bash

echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo ""

if [ -f /tmp/ap-start-time ]; then
    START_TIME=$(cat /tmp/ap-start-time)
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    REMAINING=$((60 - ELAPSED))
    
    [ $REMAINING -lt 0 ] && REMAINING=0
else
    REMAINING=0
fi

if [ -f /tmp/wifi-user-configured ]; then
    STATUS="connecting"
else
    STATUS="waiting"
fi

echo "{\"remaining\":$REMAINING,\"status\":\"$STATUS\"}"
EOFSCRIPT
}

################################################################################
# 创建Web界面
################################################################################

create_web_interface() {
    cat > "$INSTALL_DIR/www/index.html" << 'EOFHTML'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>N1-WIFI Manager 配置</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            max-width: 500px;
            width: 100%;
            padding: 30px;
        }
        h1 {
            color: #333;
            text-align: center;
            margin-bottom: 10px;
            font-size: 24px;
        }
        .countdown {
            text-align: center;
            font-size: 16px;
            color: #666;
            margin-bottom: 20px;
            padding: 12px;
            background: #f0f0f0;
            border-radius: 8px;
            font-weight: 500;
        }
        .countdown.urgent {
            background: #ffe6e6;
            color: #d63031;
            animation: pulse 1s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.7; }
        }
        .wifi-list {
            max-height: 350px;
            overflow-y: auto;
            margin-bottom: 20px;
            border: 1px solid #e0e0e0;
            border-radius: 8px;
        }
        .wifi-item {
            border-bottom: 1px solid #f0f0f0;
            padding: 15px;
            cursor: pointer;
            transition: all 0.2s;
        }
        .wifi-item:last-child { border-bottom: none; }
        .wifi-item:hover {
            background: #f8f9ff;
        }
        .wifi-item.selected {
            background: #e8ebff;
            border-left: 4px solid #667eea;
        }
        .wifi-ssid {
            font-weight: 600;
            font-size: 15px;
            margin-bottom: 5px;
            color: #333;
        }
        .wifi-info {
            font-size: 12px;
            color: #666;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .signal-bar {
            display: inline-block;
            width: 50px;
            height: 4px;
            background: #e0e0e0;
            border-radius: 2px;
            position: relative;
            overflow: hidden;
        }
        .signal-fill {
            position: absolute;
            left: 0;
            top: 0;
            height: 100%;
            border-radius: 2px;
            transition: width 0.3s;
        }
        .input-group {
            margin-bottom: 20px;
        }
        .input-group label {
            display: block;
            margin-bottom: 8px;
            color: #333;
            font-weight: 600;
            font-size: 14px;
        }
        .input-group input {
            width: 100%;
            padding: 12px 15px;
            border: 2px solid #e0e0e0;
            border-radius: 8px;
            font-size: 14px;
            transition: border-color 0.3s;
        }
        .input-group input:focus {
            outline: none;
            border-color: #667eea;
        }
        .input-group input:read-only {
            background: #f5f5f5;
            cursor: not-allowed;
        }
        .btn {
            width: 100%;
            padding: 14px;
            background: #667eea;
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s;
        }
        .btn:hover {
            background: #5568d3;
            transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
        }
        .btn:disabled {
            background: #ccc;
            cursor: not-allowed;
            transform: none;
        }
        .btn-refresh {
            width: 100%;
            padding: 10px;
            background: #6c757d;
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 14px;
            cursor: pointer;
            margin-bottom: 15px;
            transition: background 0.3s;
        }
        .btn-refresh:hover {
            background: #5a6268;
        }
        .loading {
            text-align: center;
            padding: 30px 20px;
            color: #666;
        }
        .message {
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 20px;
            text-align: center;
            font-size: 14px;
        }
        .message.success {
            background: #d4edda;
            color: #155724;
        }
        .message.error {
            background: #f8d7da;
            color: #721c24;
        }
        .success-page {
            text-align: center;
            padding: 40px 20px;
        }
        .success-page h1 {
            color: #28a745;
            font-size: 32px;
            margin-bottom: 20px;
        }
        .success-page p {
            color: #666;
            font-size: 16px;
            line-height: 1.6;
            margin-bottom: 10px;
        }
    </style>
</head>
<body>
    <div class="container" id="mainContainer">
        <h1>🌐 WiFi 配置</h1>
        <div class="countdown" id="countdown">正在检测倒计时...</div>
        
        <div id="message"></div>
        
        <button class="btn-refresh" onclick="scanWifi()">🔄 刷新WiFi列表</button>
        
        <div id="wifiList" class="wifi-list">
            <div class="loading">正在扫描WiFi网络...</div>
        </div>
        
        <div class="input-group">
            <label>选中的WiFi</label>
            <input type="text" id="selectedSsid" readonly placeholder="请从上方列表选择">
        </div>
        
        <div class="input-group">
            <label>WiFi密码</label>
            <input type="password" id="password" placeholder="请输入密码">
        </div>
        
        <button class="btn" id="connectBtn" onclick="connectWifi()">连接WiFi</button>
    </div>

    <script>
        let selectedSsid = '';
        let countdownInterval;

        function updateCountdown() {
            fetch('/cgi-bin/get_status.sh')
                .then(res => res.json())
                .then(data => {
                    const el = document.getElementById('countdown');
                    if (data.status === 'connecting') {
                        el.textContent = '⏳ 正在连接WiFi，请稍候...';
                        el.classList.add('urgent');
                    } else if (data.remaining > 0) {
                        el.textContent = `⏱ 剩余时间: ${data.remaining} 秒`;
                        if (data.remaining <= 10) {
                            el.classList.add('urgent');
                        } else {
                            el.classList.remove('urgent');
                        }
                    } else {
                        el.textContent = '⏱ 时间已到，正在切换...';
                        el.classList.add('urgent');
                    }
                })
                .catch(err => console.error('状态获取失败:', err));
        }

        function scanWifi() {
            const listEl = document.getElementById('wifiList');
            listEl.innerHTML = '<div class="loading">正在扫描WiFi网络...</div>';
            
            fetch('/cgi-bin/scan_wifi.sh')
                .then(res => res.json())
                .then(data => {
                    if (!data || data.length === 0) {
                        listEl.innerHTML = '<div class="loading">未找到WiFi网络</div>';
                        return;
                    }
                    
                    listEl.innerHTML = '';
                    data.forEach((wifi, index) => {
                        const item = document.createElement('div');
                        item.className = 'wifi-item';
                        item.onclick = () => selectWifi(wifi.ssid, item);
                        
                        const signalPercent = Math.min(wifi.signal, 100);
                        let signalColor = '#4CAF50';
                        if (signalPercent < 30) signalColor = '#f44336';
                        else if (signalPercent < 60) signalColor = '#ff9800';
                        
                        item.innerHTML = `
                            <div class="wifi-ssid">${index + 1}. ${wifi.ssid}</div>
                            <div class="wifi-info">
                                <span>信号 ${wifi.signal}%</span>
                                <span class="signal-bar">
                                    <span class="signal-fill" style="width: ${signalPercent}%; background: ${signalColor};"></span>
                                </span>
                                <span>${wifi.security || '开放'}</span>
                            </div>
                        `;
                        
                        listEl.appendChild(item);
                    });
                })
                .catch(err => {
                    listEl.innerHTML = '<div class="loading">扫描失败，请点击刷新重试</div>';
                    console.error('扫描失败:', err);
                });
        }

        function selectWifi(ssid, element) {
            document.querySelectorAll('.wifi-item').forEach(item => {
                item.classList.remove('selected');
            });
            
            element.classList.add('selected');
            selectedSsid = ssid;
            document.getElementById('selectedSsid').value = ssid;
            document.getElementById('password').focus();
        }

        function connectWifi() {
            const password = document.getElementById('password').value;
            const messageEl = document.getElementById('message');
            const connectBtn = document.getElementById('connectBtn');
            
            if (!selectedSsid) {
                showMessage('请先选择一个WiFi网络', 'error');
                return;
            }
            
            if (!password) {
                showMessage('请输入WiFi密码', 'error');
                return;
            }
            
            connectBtn.disabled = true;
            connectBtn.textContent = '正在连接...';
            
            const formData = `ssid=${encodeURIComponent(selectedSsid)}&password=${encodeURIComponent(password)}`;
            
            fetch('/cgi-bin/save_config.sh', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: formData
            })
            .then(res => res.json())
            .then(data => {
                if (data.status === 'success') {
                    showMessage('✓ ' + data.message, 'success');
                    setTimeout(() => {
                        document.getElementById('mainContainer').innerHTML = `
                            <div class="success-page">
                                <h1>✓ 配置成功</h1>
                                <p>WiFi配置已保存</p>
                                <p>设备正在切换网络...</p>
                                <p>请稍候片刻后重新连接到您的WiFi</p>
                            </div>
                        `;
                    }, 1500);
                } else {
                    showMessage('✗ ' + data.message, 'error');
                    connectBtn.disabled = false;
                    connectBtn.textContent = '连接WiFi';
                }
            })
            .catch(err => {
                showMessage('✗ 连接失败，请重试', 'error');
                connectBtn.disabled = false;
                connectBtn.textContent = '连接WiFi';
                console.error('连接失败:', err);
            });
        }

        function showMessage(msg, type) {
            const messageEl = document.getElementById('message');
            messageEl.className = `message ${type}`;
            messageEl.textContent = msg;
            setTimeout(() => {
                messageEl.textContent = '';
                messageEl.className = '';
            }, 5000);
        }

        scanWifi();
        updateCountdown();
        countdownInterval = setInterval(updateCountdown, 1000);
    </script>
</body>
</html>
EOFHTML
}

################################################################################
# 创建systemd服务
################################################################################

create_systemd_service() {
    cat > /etc/systemd/system/n1-wifi-setup.service << 'EOFSERVICE'
[Unit]
Description=N1-WIFI Manager AP Setup Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '/opt/n1-wifi-manager/ap-startup.sh && sleep 3 && /opt/n1-wifi-manager/start-web.sh && /opt/n1-wifi-manager/countdown-daemon.sh &'
ExecStop=/opt/n1-wifi-manager/stop