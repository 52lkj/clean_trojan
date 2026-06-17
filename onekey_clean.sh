#!/usr/bin/env bash
set +e

LOG="/root/onekey_clean_$(date +%F_%H%M%S).log"
QDIR="/root/malware_quarantine_$(date +%F_%H%M%S)"
mkdir -p "$QDIR"
exec > >(tee -a "$LOG") 2>&1

echo "===== OneKey Clean Start: $(date) ====="
if [ "$EUID" -ne 0 ]; then
    echo "请用 root 执行"
    exit 1
fi

IOC_REGEX='(/shm/.kworker|/dev/shm/.kworker|/tmp/.kworker|/var/tmp/.kworker|kworker_u8|kdevtmpfsi|kinsing|xmrig|\.xmrig|\.httpd_worker|\.font-unix)'

echo
echo "===== 1. 当前可疑进程 ====="
ps aux | grep -Ei "$IOC_REGEX" | grep -v grep || echo "未发现明显可疑进程"

echo
echo "===== 2. 杀掉可疑进程 ====="
for pat in "/shm/.kworker" "/dev/shm/.kworker" "/tmp/.kworker" "/var/tmp/.kworker" "kworker_u8" "kdevtmpfsi" "kinsing" "xmrig" ".xmrig" ".httpd_worker"; do
    PIDS=$(pgrep -f "$pat")
    if [ -n "$PIDS" ]; then
        echo "发现 $pat 进程: $PIDS"
        kill $PIDS 2>/dev/null
        sleep 2
        kill -9 $PIDS 2>/dev/null
    fi
done

echo
echo "===== 3. 备份并删除可疑文件 ====="
echo ">> 正在解除底层系统锁 (chattr -ia)..."
chattr -ia /tmp/.font-unix 2>/dev/null
chattr -ia /tmp/.font-unix/* 2>/dev/null
chattr -ia /var/lib/.httpd_cache 2>/dev/null
chattr -ia /var/lib/.httpd_cache/* 2>/dev/null
chattr -ia /var/spool/cron/root 2>/dev/null
chattr -ia /var/spool/cron/crontabs/root 2>/dev/null
chattr -ia /etc/crontab 2>/dev/null

for f in \
    /shm/.kworker* \
    /dev/shm/.kworker* \
    /tmp/.kworker* \
    /var/tmp/.kworker* \
    /tmp/kdevtmpfsi \
    /var/tmp/kdevtmpfsi \
    /tmp/kinsing \
    /var/tmp/kinsing \
    /tmp/xmrig \
    /var/tmp/xmrig \
    /tmp/.xmrig \
    /var/tmp/.xmrig \
    /tmp/.font-unix \
    /var/lib/.httpd_cache
do
    if [ -e "$f" ]; then
        echo "备份并删除: $f"
        cp -a "$f" "$QDIR/" 2>/dev/null
        rm -rf "$f"
    fi
done
rmdir /shm 2>/dev/null

echo
echo "===== 4. 清理 crontab 自启动 ====="
clean_file() {
    local file="$1"
    [ -f "$file" ] || return
    if grep -Eq "$IOC_REGEX" "$file"; then
        echo "清理可疑启动项: $file"
        cp -a "$file" "$file.bak.onekey_clean" 2>/dev/null
        tmpf=$(mktemp)
        grep -Ev "$IOC_REGEX" "$file" > "$tmpf"
        cat "$tmpf" > "$file"
        rm -f "$tmpf"
    fi
}
clean_file /etc/crontab
for f in /etc/cron.d/* /var/spool/cron/* /var/spool/cron/crontabs/*; do
    clean_file "$f"
done
TMPCRON=$(mktemp)
crontab -l 2>/dev/null > "$TMPCRON"
if grep -Eq "$IOC_REGEX" "$TMPCRON"; then
    echo "清理 root crontab"
    cp "$TMPCRON" "$QDIR/root_crontab.bak" 2>/dev/null
    grep -Ev "$IOC_REGEX" "$TMPCRON" | crontab -
fi
rm -f "$TMPCRON"

echo
echo "===== 5. 清理 systemd 可疑服务 ====="
FOUND_UNITS=$(grep -RIlE "$IOC_REGEX" /etc/systemd/system /lib/systemd/system 2>/dev/null)
for f in $FOUND_UNITS; do
    echo "发现可疑 systemd 文件: $f"
    cp -a "$f" "$f.bak.onekey_clean" 2>/dev/null
    svc=$(basename "$f")
    systemctl disable --now "$svc" 2>/dev/null
    mv "$f" "$f.disabled_by_onekey_clean" 2>/dev/null
done
systemctl daemon-reload 2>/dev/null

echo
echo "===== 6. 添加/修复 4G swap ====="
SWAP_MB=$(free -m | awk '/^Swap:/ {print $2}')
if [ -z "$SWAP_MB" ]; then
    SWAP_MB=0
fi
if [ "$SWAP_MB" -lt 3000 ]; then
    echo "当前 swap 小于 3G，开始配置 4G swap"
    swapoff /swapfile 2>/dev/null
    fallocate -l 4G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=4096
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
else
    echo "swap 已经足够，跳过"
fi

echo
echo "===== 7. 加固哪吒 Agent，关闭远程命令能力 ====="
for cfg in /opt/nezha/agent/config.yml /opt/nezha/agent/config.yaml; do
    if [ -f "$cfg" ]; then
        echo "处理哪吒配置: $cfg"
        cp -a "$cfg" "$cfg.bak.onekey_clean" 2>/dev/null
        set_bool() {
            local key="$1"
            local val="$2"
            if grep -q "^${key}:" "$cfg"; then
                sed -i "s/^${key}:.*/${key}: ${val}/" "$cfg"
            else
                echo "${key}: ${val}" >> "$cfg"
            fi
        }
        set_bool disable_command_execute true
        set_bool disable_force_update true
        set_bool disable_nat true
        systemctl restart nezha-agent 2>/dev/null
    fi
done

echo
echo "===== 8. 重启 DNS 服务 ====="
systemctl restart systemd-resolved 2>/dev/null

echo
echo "===== 9. 检查 SSH 登录记录 ====="
last -ai | head -30

echo
echo "===== 10. 检查 SSH authorized_keys ====="
if [ -f /root/.ssh/authorized_keys ]; then
    echo "请检查下面有没有陌生 key："
    cat /root/.ssh/authorized_keys
else
    echo "没有发现 /root/.ssh/authorized_keys"
fi

echo
echo "===== 11. 清理后 CPU 前 20 ====="
ps aux --sort=-%cpu | head -20

echo
echo "===== 12. 清理后内存前 20 ====="
ps aux --sort=-%mem | head -20

echo
echo "===== 13. 再查可疑项 ====="
ps aux | grep -Ei "$IOC_REGEX" | grep -v grep || echo "未发现可疑进程"
grep -R "kworker_u8|/shm|.kworker|xmrig|kinsing|kdevtmpfsi|.httpd_worker|.font-unix" /etc/cron* /var/spool/cron* /etc/systemd/system /root 2>/dev/null || echo "未发现明显可疑自启动"

echo
echo "===== 14. 当前内存 ====="
free -h

echo
echo "===== 完成 ====="
echo "日志文件: $LOG"
echo "可疑文件备份目录: $QDIR"
