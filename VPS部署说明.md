# N1-WIFI Manager VPS 部署指南

## 📋 前置要求

- Linux VPS（推荐 Ubuntu/Debian/Armbian）
- Root 权限或 sudo 权限
- 已安装 NetworkManager
- 已安装 busybox（用于 Web 服务器）

## 🚀 快速部署步骤

### 方法一：直接从 GitHub 下载（推荐）

```bash
# 1. 连接到你的 VPS
ssh user@your-vps-ip

# 2. 下载脚本
wget https://raw.githubusercontent.com/chf5762-sudo/cursor-code/main/N1-WIFI%20Manager.sh

# 或者使用 curl
curl -O https://raw.githubusercontent.com/chf5762-sudo/cursor-code/main/N1-WIFI%20Manager.sh

# 3. 重命名文件（处理空格）
mv "N1-WIFI Manager.sh" n1-wifi-manager.sh

# 4. 添加执行权限
chmod +x n1-wifi-manager.sh

# 5. 运行安装（需要 root 权限）
sudo bash n1-wifi-manager.sh
```

### 方法二：使用 Git 克隆

```bash
# 1. 克隆仓库
git clone https://github.com/chf5762-sudo/cursor-code.git
cd cursor-code

# 2. 重命名文件
mv "N1-WIFI Manager.sh" n1-wifi-manager.sh

# 3. 添加执行权限
chmod +x n1-wifi-manager.sh

# 4. 运行安装
sudo bash n1-wifi-manager.sh
```

### 方法三：手动上传文件

```bash
# 1. 在本地使用 SCP 上传文件
scp "N1-WIFI Manager.sh" user@your-vps-ip:~/

# 2. SSH 连接到 VPS
ssh user@your-vps-ip

# 3. 重命名并添加执行权限
mv "N1-WIFI Manager.sh" n1-wifi-manager.sh
chmod +x n1-wifi-manager.sh

# 4. 运行安装
sudo bash n1-wifi-manager.sh
```

## 📦 安装依赖（如需要）

如果系统缺少必要组件，请先安装：

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y network-manager busybox git

# 确保 NetworkManager 服务运行
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager
```

## ✅ 安装完成后的操作

安装脚本会自动：
- 创建安装目录：`/opt/n1-wifi-manager`
- 创建配置文件：`/etc/wifi-config.conf`
- 创建 systemd 服务：`n1-wifi-setup.service`
- 设置自动启动

### 启动服务

```bash
# 启动 WiFi 配置模式（AP 热点模式）
sudo systemctl start n1-wifi-setup

# 查看服务状态
sudo systemctl status n1-wifi-setup

# 停止服务
sudo systemctl stop n1-wifi-setup
```

### 查看日志

```bash
# 实时查看日志
sudo tail -f /opt/n1-wifi-manager/logs/wifi-setup.log

# 查看最近 50 行日志
sudo tail -n 50 /opt/n1-wifi-manager/logs/wifi-setup.log
```

## 🌐 使用 Web 界面配置

1. **启动 AP 模式后**，设备会创建一个 WiFi 热点：
   - SSID: `N1-Setup`
   - 管理 IP: `192.168.1.1`

2. **连接 WiFi 热点**：
   - 用手机或电脑连接到 `N1-Setup` 热点

3. **访问 Web 界面**：
   - 打开浏览器访问：`http://192.168.1.1`
   - 无需账号密码

4. **配置 WiFi**：
   - 在 Web 界面扫描并选择要连接的 WiFi
   - 输入 WiFi 密码
   - 点击连接

5. **自动切换**：
   - 配置完成后，设备会自动切换到 STA 模式
   - 连接到您配置的 WiFi 网络

## 🔧 常用命令

```bash
# 查看已保存的 WiFi 配置
sudo cat /etc/wifi-config.conf

# 手动切换到 STA 模式
sudo /opt/n1-wifi-manager/switch-to-sta.sh

# 重启 WiFi 管理器服务
sudo systemctl restart n1-wifi-setup

# 禁用自动启动
sudo systemctl disable n1-wifi-setup

# 启用自动启动
sudo systemctl enable n1-wifi-setup
```

## ⚠️ 注意事项

1. **需要 root 权限**：脚本必须使用 `sudo` 运行
2. **WiFi 接口**：脚本默认使用 `wlan0`，如果您的设备 WiFi 接口不同，需要修改脚本
3. **防火墙**：确保端口 80 未被占用或防火墙允许
4. **NetworkManager**：必须安装并运行 NetworkManager
5. **AP 模式超时**：AP 模式会在 60 秒后自动切换到 STA 模式

## 🐛 故障排查

### 问题：无法启动 AP 模式

```bash
# 检查 NetworkManager 状态
sudo systemctl status NetworkManager

# 检查 WiFi 是否启用
nmcli radio wifi

# 启用 WiFi
sudo nmcli radio wifi on

# 查看详细日志
sudo journalctl -u n1-wifi-setup -n 50
```

### 问题：Web 界面无法访问

```bash
# 检查 busybox httpd 是否运行
ps aux | grep busybox

# 检查端口 80 是否被占用
sudo netstat -tulpn | grep :80

# 手动启动 Web 服务
sudo /opt/n1-wifi-manager/start-web.sh
```

### 问题：无法连接到 WiFi

```bash
# 查看 WiFi 连接状态
nmcli connection show

# 查看 WiFi 设备状态
nmcli device status

# 重新扫描 WiFi
sudo nmcli dev wifi rescan

# 查看连接日志
sudo tail -f /opt/n1-wifi-manager/logs/wifi-setup.log
```

## 📝 卸载

如果需要卸载脚本：

```bash
# 停止并禁用服务
sudo systemctl stop n1-wifi-setup
sudo systemctl disable n1-wifi-setup

# 删除服务文件
sudo rm /etc/systemd/system/n1-wifi-setup.service
sudo systemctl daemon-reload

# 删除安装目录
sudo rm -rf /opt/n1-wifi-manager

# 删除配置文件（可选）
sudo rm /etc/wifi-config.conf
```

## 🔗 相关链接

- GitHub 仓库：https://github.com/chf5762-sudo/cursor-code
- 脚本文件：`N1-WIFI Manager.sh`

---

**提示**：如果遇到问题，请查看日志文件获取详细错误信息。

