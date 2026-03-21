#!/bin/bash

# =================================================================
# 颜色与变量定义
# =================================================================
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

MARKER="$HOME/.initial_update_done"
ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}

# =================================================================
# 辅助函数：提权执行
# =================================================================
# 检查 sudo 权限，如果没有则尝试获取
check_sudo() {
    if ! sudo -v; then
        echo -e "${RED}错误: 需要 sudo 权限执行系统级任务。${NC}"
        exit 1
    fi
}

# =================================================================
# 1. Update & Upgrade (仅运行一次)
# =================================================================
if [ ! -f "$MARKER" ]; then
    echo -e "${GREEN}[1/6] 正在执行系统更新 (仅限首次)...${NC}"
    check_sudo
    sudo apt update && sudo apt upgrade -y
    touch "$MARKER"
else
    echo -e "${YELLOW}[1/6] 检测到已更新记录，跳过系统升级。${NC}"
fi

# =================================================================
# 2. 安装基础依赖
# =================================================================
echo -e "${GREEN}[2/6] 安装必备依赖软件...${NC}"
check_sudo
DEPENDENCIES=(zsh unzip git command-not-found htop net-tools bind9-dnsutils neovim wget curl mtr tmux ufw)
sudo apt install -y "${DEPENDENCIES[@]}"

# =================================================================
# 3. 配置 Oh-My-Zsh & 插件 (用户级配置)
# =================================================================
echo -e "${GREEN}[3/6] 配置 Oh-My-Zsh...${NC}"

# 安装 Oh-My-Zsh (幂等)
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    # 使用 --unattended 避免安装完后直接跳入 zsh 导致脚本中断
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    # 修改默认 shell
    check_sudo
    sudo chsh -s $(which zsh) $USER
fi

# 下载主题和插件 (幂等)
[[ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]] && git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
[[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] && git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
[[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# 修改 .zshrc
if [ -f "$HOME/.zshrc" ]; then
    sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="simple"/' "$HOME/.zshrc"
    # 幂等修改插件列表：如果不在列表中才替换
    if ! grep -q "zsh-autosuggestions" "$HOME/.zshrc"; then
        sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting command-not-found)/' "$HOME/.zshrc"
    fi
fi

# =================================================================
# 4. SSH 安全配置 (系统级配置)
# =================================================================
echo -e "${GREEN}[4/6] SSH 安全增强配置...${NC}"
OVERWRITE_CONF="/etc/ssh/sshd_config.d/99-overwrite.conf"

# 准备临时文件以避免 sudo 权限下的重定向麻烦
TEMP_SSH_CONF=$(mktemp)

# 公钥配置
read -p "是否上传 SSH 公钥？(y/n): " confirm_pubkey
if [[ $confirm_pubkey == [yY] ]]; then
    read -p "请输入你的公钥内容 (ssh-rsa ...): " pubkey_content
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    echo "$pubkey_content" >> "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    echo "PubkeyAuthentication yes" >> "$TEMP_SSH_CONF"
fi

# 端口配置
read -p "是否更改 SSH 端口？(默认不修改输入n, 否则输入端口号): " ssh_port
if [[ $ssh_port =~ ^[0-9]+$ ]]; then
    echo "Port $ssh_port" >> "$TEMP_SSH_CONF"
    check_sudo
    sudo ufw allow "$ssh_port"/tcp
    echo -e "${YELLOW}已在 UFW 中放行端口 $ssh_port${NC}"
fi

# 禁用密码登录
read -p "是否禁止密码登录？(y/n): " disable_password
if [[ $disable_password == [yY] ]]; then
    echo "PasswordAuthentication no" >> "$TEMP_SSH_CONF"
fi

# 写入配置文件
if [ -s "$TEMP_SSH_CONF" ]; then
    check_sudo
    sudo mkdir -p /etc/ssh/sshd_config.d/
    sudo cp "$TEMP_SSH_CONF" "$OVERWRITE_CONF"
    
    # 重启 SSH 服务 (兼容 Ubuntu 24.04 socket 模式)
    sudo systemctl daemon-reload
    if sudo systemctl is-active --quiet ssh.socket; then
        sudo systemctl restart ssh.socket
    else
        sudo systemctl restart ssh
    fi
fi
rm -f "$TEMP_SSH_CONF"

# =================================================================
# 5. 可选安装项菜单 (引导提权)
# =================================================================
echo -e "${GREEN}[5/6] 进入可选组件安装...${NC}"

install_caddy() {
    check_sudo
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    sudo apt update && sudo apt install caddy -y
    sudo ufw allow http && sudo ufw allow https
}

install_docker() {
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh && rm get-docker.sh
}

install_easytier() {
    wget -O /tmp/easytier.sh "https://raw.githubusercontent.com/EasyTier/EasyTier/main/script/install.sh"
    sudo bash /tmp/easytier.sh install --no-gh-proxy
    sudo systemctl disable --now easytier@default
    echo -e "${YELLOW}EasyTier 已安装。请手动编辑 /opt/easytier/config/default.conf${NC}"
}

install_singbox() {
    check_sudo
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://sing-box.app/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/sagernet.gpg
    echo "deb [signed-by=/etc/apt/keyrings/sagernet.gpg] https://deb.sagernet.org/ * main" | sudo tee /etc/apt/sources.list.d/sagernet.list
    sudo apt update && sudo apt install sing-box -y
}

while true; do
    echo -e "${BLUE}请选择安装组件 (输入数字，q 退出):${NC}"
    echo "1) Caddy (自动 UFW)"
    echo "2) Docker"
    echo "3) EasyTier"
    echo "4) sing-box"
    echo "5) s-ui (脚本可能接管终端)"
    echo "6) 3x-ui (脚本可能接管终端)"
    echo "q) 退出"
    read -p "选择: " opt
    case $opt in
        1) install_caddy ;;
        2) install_docker ;;
        3) install_easytier ;;
        4) install_singbox ;;
        5) bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/master/install.sh) ;;
        6) bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) ;;
        q) break ;;
        *) echo "无效选项" ;;
    esac
done

# =================================================================
# 6. 收尾
# =================================================================
echo -e "${GREEN}[6/6] 环境配置完成！${NC}"
echo -e "${YELLOW}请重新连接 SSH 或执行 'zsh' 进入新环境。${NC}"