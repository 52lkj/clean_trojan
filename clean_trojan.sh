#!/bin/bash

echo "======================================================"
echo "    开始清理 .kworker_u8 及相关 DDoS/挖矿木马遗留"
echo "======================================================"

# 1. 强制击杀恶意进程
echo "[1/6] 正在强制击杀恶意木马进程..."
pkill -9 -x .kworker_u8
# 顺手击杀可能还在运行的初始母体脚本
pkill -9 -f "c78a96833603" 

# 2. 清理定时任务
echo "[2/6] 正在清空当前用户的定时任务..."
crontab -r 2>/dev/null
echo "  -> 定时任务已清空。"

# 3. 删除内存盘中的木马本体
echo "[3/6] 正在删除 /dev/shm 下的木马本体..."
rm -f /dev/shm/.kworker_u8

# 4. 删除隐藏锁文件和伪装目录
echo "[4/6] 正在捣毁 /tmp 下的伪装隐藏目录..."
rm -rf /tmp/.font-unix/

# 5. 删除母体投递脚本
echo "[5/6] 正在清理 /tmp 下的母体脚本残留..."
rm -f /tmp/c78a*

# 6. 自动修复开机自启项 (剔除恶意代码)
echo "[6/6] 正在检查并修复开机启动项 (rc.local)..."
if [ -f /etc/rc.local ]; then
    sed -i '/\.kworker_u8/d' /etc/rc.local
    sed -i '/c78a968/d' /etc/rc.local
fi
if [ -f /etc/rc.d/rc.local ]; then
    sed -i '/\.kworker_u8/d' /etc/rc.d/rc.local
    sed -i '/c78a968/d' /etc/rc.d/rc.local
fi

echo "======================================================"
echo "  清理执行完毕！您的服务器已经拔除了所有已知的木马触角。"
echo "======================================================"
