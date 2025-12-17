#!/bin/bash

# APT 大文件拦截脚本
# 拦截超过指定大小的索引文件下载

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}配置 APT 大文件拦截${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# 方案：修改APT配置，使用pdiff而不是完整索引
cat > /etc/apt/apt.conf.d/01-minimal-download << 'EOF'
# 只下载差异文件，不下载完整索引
Acquire::PDiffs "true";

# 禁用所有Contents索引
Acquire::IndexTargets::deb::Contents-deb::DefaultEnabled "false";
Acquire::IndexTargets::deb::Contents-all::DefaultEnabled "false";

# 不下载翻译
Acquire::Languages "none";

# 不下载图标等元数据
Acquire::IndexTargets::deb::DEP11::DefaultEnabled "false";
Acquire::IndexTargets::deb::DEP11-icons::DefaultEnabled "false";

# 限制并发下载（减慢速度，但更容易中断）
Acquire::Queue-Mode "access";
EOF

# 创建最小化的sources.list
cat > /etc/apt/sources.list << 'EOF'
# 最小化配置 - 只保留main仓库
deb http://ports.ubuntu.com/ubuntu-ports jammy main
deb http://ports.ubuntu.com/ubuntu-ports jammy-updates main
EOF

# 禁用其他所有第三方源
if [ -d /etc/apt/sources.list.d/ ]; then
    for file in /etc/apt/sources.list.d/*.list; do
        if [ -f "$file" ]; then
            mv "$file" "$file.disabled"
            echo -e "${YELLOW}已禁用: $(basename $file)${NC}"
        fi
    done
fi

# 清理现有缓存
rm -rf /var/lib/apt/lists/*
mkdir -p /var/lib/apt/lists/partial
apt-get clean

echo ""
echo -e "${GREEN}配置完成！${NC}"
echo ""
echo -e "${YELLOW}现在测试 apt-get update...${NC}"
echo ""

# 显示下载统计
apt-get update 2>&1 | tee /tmp/apt-update.log

# 统计下载量
DOWNLOADED=$(grep "Fetched" /tmp/apt-update.log | awk '{print $2, $3}')

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}下载统计: ${DOWNLOADED}${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# 检查是否还有大文件
if grep -q "Contents.*MB\]" /tmp/apt-update.log; then
    echo -e "${RED}警告: 仍在下载Contents文件！${NC}"
    echo ""
    echo -e "${YELLOW}终极方案：完全禁用apt update，改用手动安装${NC}"
    echo "需要安装软件时："
    echo "1. 从网页下载 .deb 文件"
    echo "2. 使用 dpkg -i xxx.deb 安装"
    echo "3. 使用 apt-get install -f 修复依赖"
else
    echo -e "${GREEN}✓ 成功！不再下载大文件${NC}"
fi

rm -f /tmp/apt-update.log