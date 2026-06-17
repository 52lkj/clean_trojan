#!/bin/bash

echo "======================================================"
echo "  开始清理 .kworker_u8 及高阶防护版 DDoS/挖矿木马"
echo "======================================================"

# 0. 剥除文件系统底层的防篡改锁 (关键破防步骤)
echo "[1/7] 正在强制解除系统底层锁 (chattr -ia)..."
chattr -ia /var/spool/cron/root 2>/dev/null
chattr -ia /var/spool/cron/crontabs/root 2>/dev/null
chattr -ia /etc/crontab 2>/dev/null
chattr -ia /etc/rc.local 2>/dev/null
chattr -ia /etc/rc.d/rc.local 2>/dev/null
chattr -ia /dev/shm/.kworker_u8 2>/dev/null
chattr -ia /tmp/.font-unix 2>/dev/null
chattr -ia /tmp/.font-unix/* 2>/dev/null
chattr -ia /tmp/c78a* 2>/dev/null

# 1. 强制击杀恶意进程
echo "[2/7] 正在强制击杀恶意木马进程及看门狗..."
pkill -9 -x .kworker_u8
pkill -9 -f "c78a96833603" 

# 2. 清理定时任务
echo "[3/7] 正在清空当前用户的定时任务..."
crontab -r 2>/dev/null
echo "  -> 定时任务已尝试清空。"

# 3. 删除内存盘中的木马本体
echo "[4/7] 正在删除 /dev/shm 下的木马本体..."
rm -f /dev/shm/.kworker_u8

# 4. 删除隐藏锁文件和伪装目录
echo "[5/7] 正在捣毁 /tmp 下的伪装隐藏目录..."
rm -rf /tmp/.font-unix/

# 5. 删除母体投递脚本
echo "[6/7] 正在清理 /tmp 下的母体脚本残留..."
rm -f /tmp/c78a*

# 6. 自动修复开机自启项 (剔除恶意代码)
echo "[7/7] 正在检查并修复开机启动项 (rc.local)..."
if [ -f /etc/rc.local ]; then
    sed -i '/\.kworker_u8/d' /etc/rc.local
    sed -i '/c78a968/d' /etc/rc.local
fi
if [ -f /etc/rc.d/rc.local ]; then
    sed -i '/\.kworker_u8/d' /etc/rc.d/rc.local
    sed -i '/c78a968/d' /etc/rc.d/rc.local
fi

echo "======================================================"
echo "  强力清理执行完毕！文件锁已解除，木马核心已被摧毁。"
echo "======================================================"
