#!/bin/bash

# ------------------------------------------------------------------------------
# 容器参数配置
# ------------------------------------------------------------------------------
SS_CONTAINER_NAME="shadowsocks-server" 
SS_IMAGE="teddysun/shadowsocks-r"

# ShadowsocksR 配置
SS_PORT="443"     
SS_PASSWORD="msfFIS294tu9jds"
SS_METHOD="chacha20" 
SS_PROTOCOL="auth_chain_a"
SS_PROTOCOL_PARAM=""
SS_OBFS="tls1.2_ticket_auth"
SS_OBFS_PARAM=""

# 配置文件路径
CONFIG_FILE="./config.json"

# ------------------------------------------------------------------------------
# 颜色
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查并安装 Docker
install_docker_if_not_present() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW} 检测到 Docker 未安装，正在尝试自动安装...${NC}"
        # 检测操作系统类型
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            OS=${ID}
            VERSION_ID=${VERSION_ID%.*} # 获取主版本号
        fi

        case "$OS" in
            ubuntu|debian)
                echo -e "${BLUE} 检测到 ${OS} 系统，正在使用 apt 安装 Docker...${NC}"
                sudo apt-get update || { echo -e "${RED}Error: apt update failed.${NC}"; exit 1; }
                sudo apt-get install -y ca-certificates curl gnupg lsb-release || { echo -e "${RED}Error: Failed to install dependencies.${NC}"; exit 1; }
                
                # 添加 Docker 的官方 GPG 密钥
                sudo mkdir -m 0755 -p /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/${OS}/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || { echo -e "${RED}Error: Failed to add Docker GPG key.${NC}"; exit 1; }
                
                # 添加 Docker apt 仓库
                echo \
                  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS} \
                  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || { echo -e "${RED}Error: Failed to add Docker repository.${NC}"; exit 1; }
                
                sudo apt-get update || { echo -e "${RED}Error: apt update failed.${NC}"; exit 1; }
                sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { echo -e "${RED}Error: Failed to install Docker engine.${NC}"; exit 1; }
                
                sudo systemctl start docker || { echo -e "${RED}Error: Failed to start Docker service.${NC}"; exit 1; }
                sudo systemctl enable docker || { echo -e "${RED}Error: Failed to enable Docker on startup.${NC}"; exit 1; }
                ;;
            centos|rhel|fedora)
                echo -e "${BLUE} 检测到 ${OS} 系统，正在使用 yum/dnf 安装 Docker...${NC}"
                sudo yum install -y yum-utils || { echo -e "${RED}Error: Failed to install yum-utils.${NC}"; exit 1; }
                sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || { echo -e "${RED}Error: Failed to add Docker repository.${NC}"; exit 1; }
                sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { echo -e "${RED}Error: Failed to install Docker engine.${NC}"; exit 1; }
                
                sudo systemctl start docker || { echo -e "${RED}Error: Failed to start Docker service.${NC}"; exit 1; }
                sudo systemctl enable docker || { echo -e "${RED}Error: Failed to enable Docker on startup.${NC}"; exit 1; }
                ;;
            *)
                echo -e "${RED} 错误: 不支持的操作系统类型 (${OS})。请手动安装 Docker。${NC}"
                exit 1
                ;;
        esac
        echo -e "${GREEN} Docker 安装成功。${NC}"
    else
        echo -e "${GREEN} Docker 已安装。${NC}"
    fi
}

# 生成 Shadowsocks 配置文件
generate_config_file() {
    echo -e "${BLUE} 正在生成 Shadowsocks 配置文件: $CONFIG_FILE...${NC}"
    
    # 使用 here-string 构建基础 JSON
    CONFIG_JSON=$(cat <<EOF
{
    "server":"0.0.0.0",
    "server_ipv6":"::",
    "local_address":"127.0.0.1",
    "local_port":1080,
    "server_port":$SS_PORT,
    "password":"$SS_PASSWORD",
    "timeout":120,
    "method":"$SS_METHOD",
    "protocol":"$SS_PROTOCOL",
    "protocol_param":"$SS_PROTOCOL_PARAM",
    "obfs":"$SS_OBFS",
    "obfs_param":"$SS_OBFS_PARAM",
    "redirect":"",
    "dns_ipv6":false,
    "fast_open":false,
    "workers":1
}
EOF
)

    echo "$CONFIG_JSON" > "$CONFIG_FILE"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN} 配置文件生成成功:${NC}"
    else
        echo -e "${RED} 错误: 生成配置文件失败。${NC}"
        exit 1
    fi
}

    # 获取公网 IP 地址
get_public_ip() {
    PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null)
    if [ -z "$PUBLIC_IP" ]; then
        PUBLIC_IP=$(curl -s ipinfo.io/ip 2>/dev/null)
    fi
    if [ -z "$PUBLIC_IP" ]; then
        PUBLIC_IP=$(curl -s icanhazip.com 2>/dev/null)
    fi
    echo "$PUBLIC_IP"
}

# 生成 SSR 客户端链接
generate_ssr_link() {
    echo -e "${BLUE} 正在生成 SSR 客户端连接链接...${NC}"
    
    # 获取服务器 IP
    SERVER_IP=$(get_public_ip)
    if [ -z "$SERVER_IP" ]; then
        echo -e "${YELLOW} 警告: 无法获取公网 IP, 使用示例 IP${NC}"
        SERVER_IP="1.2.3.4"
    else
        echo -e "${GREEN} 检测到公网 IP: $SERVER_IP${NC}"
    fi
    
    # 对密码和备注进行 Base64 编码
    PASSWORD_B64=$(echo -n "$SS_PASSWORD" | base64 | tr -d '\n=')
    REMARKS_B64=$(echo -n "SSR-Server" | base64 | tr -d '\n=')
    
    # 构建连接字符串
    CONNECTION_STRING="${SERVER_IP}:${SS_PORT}:${SS_PROTOCOL}:${SS_METHOD}:${SS_OBFS}:${PASSWORD_B64}/?remarks=${REMARKS_B64}"
    
    # 生成 SSR 链接
    SSR_LINK="ssr://$(echo -n "$CONNECTION_STRING" | base64 | tr -d '\n=')"
    
    echo ""
    echo -e "${GREEN}=================================="
    echo "SSR 客户端配置信息:"
    echo "=================================="
    echo -e "${YELLOW}服务器 IP:${NC} $SERVER_IP"
    echo -e "${YELLOW}端口:${NC} $SS_PORT"
    echo -e "${YELLOW}密码:${NC} $SS_PASSWORD"
    echo -e "${YELLOW}加密方法:${NC} $SS_METHOD"
    echo -e "${YELLOW}协议:${NC} $SS_PROTOCOL"
    echo -e "${YELLOW}混淆:${NC} $SS_OBFS"
    echo -e "${GREEN}=================================="
    echo "SSR 客户端链接:"
    echo "=================================="
    echo -e "${BLUE}$SSR_LINK${NC}"
    echo -e "${GREEN}=================================="
    echo ""
    
    # 保存配置信息
    cat > ssr_client_config.txt << EOF
SSR 客户端配置信息:
==================================
服务器 IP: $SERVER_IP
端口: $SS_PORT
密码: $SS_PASSWORD
加密方法: $SS_METHOD
协议: $SS_PROTOCOL
混淆: $SS_OBFS
==================================
SSR 客户端链接:
${YELLOW}$SSR_LINK${NC}
==================================
EOF
    echo -e "${GREEN}配置信息已保存到 ssr_client_config.txt${NC}"
}

# Deploy/Install Shadowsocks
install_shadowsocks() {
    echo -e "${BLUE} 开始部署 Shadowsocks 容器...${NC}"

    install_docker_if_not_present

    # 检查是否存在现有容器
    if sudo docker ps -a --format '{{.Names}}' | grep -q "$SS_CONTAINER_NAME"; then
        echo -e "${YELLOW} 检测到名为 '$SS_CONTAINER_NAME' 的现有 Shadowsocks 容器。${NC}"
        if sudo docker ps --format '{{.Names}}' | grep -q "$SS_CONTAINER_NAME"; then
            echo -e "${YELLOW} 此容器当前正在运行。${NC}"
            read -p "要继续运行现有容器吗? (y/N): " choice
            if [[ "$choice" =~ ^[yY]$ ]]; then
                echo -e "${GREEN} 继续运行现有 Shadowsocks 容器。${NC}"
                generate_ssr_link
                exit 0
            else
                echo -e "${YELLOW} 用户选择重新部署。停止并删除旧容器...${NC}"
                sudo docker stop "$SS_CONTAINER_NAME" &> /dev/null
                sudo docker rm "$SS_CONTAINER_NAME" &> /dev/null
                echo -e "${GREEN} 旧容器已清理。${NC}"
            fi
        else
            echo -e "${YELLOW} 此容器未运行。${NC}"
            read -p "Do you want to start and use the existing container? (y/N): " choice
            if [[ "$choice" =~ ^[yY]$ ]]; then
                echo -e "${BLUE} 启动现有 Shadowsocks 容器...${NC}"
                sudo docker start "$SS_CONTAINER_NAME"
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN} Shadowsocks 容器已启动。${NC}"
                    generate_ssr_link
                    exit 0
                else
                    echo -e "${RED} 错误: 启动现有 Shadowsocks 容器失败。${NC}"
                    sudo docker rm "$SS_CONTAINER_NAME" &> /dev/null
                fi
            else
                echo -e "${YELLOW} 用户选择重新部署。删除旧容器...${NC}"
                sudo docker rm "$SS_CONTAINER_NAME" &> /dev/null
                echo -e "${GREEN} 旧容器已清理。${NC}"
            fi
        fi
    fi

    # 生成配置文件
    generate_config_file

    # 拉取 Shadowsocks Docker 镜像
    echo -e "${BLUE} 正在拉取 Docker 镜像: $SS_IMAGE...${NC}"
    sudo docker pull "$SS_IMAGE"
    if [ $? -ne 0 ]; then
        echo -e "${RED} 错误: 拉取 Docker 镜像失败。检查网络连接或镜像名称。${NC}"
        rm -f "$CONFIG_FILE"
        exit 1
    fi
    echo -e "${GREEN} Docker 镜像拉取成功。${NC}"

    # 运行 Shadowsocks 容器
    echo -e "${BLUE} 正在运行 Shadowsocks 容器...${NC}"
    sudo docker run -d \
        --name "$SS_CONTAINER_NAME" \
        --restart always \
        -p "$SS_PORT:$SS_PORT/tcp" \
        -p "$SS_PORT:$SS_PORT/udp" \
        -v "$(pwd)/config.json:/etc/shadowsocks-r/config.json" \
        "$SS_IMAGE"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED} 错误: 运行 Shadowsocks 容器失败。检查端口是否被占用或配置。${NC}"
        echo -e "${RED} 确保 Docker 镜像 ($SS_IMAGE) 支持通过挂载配置文件启动。${NC}"
        rm -f "$CONFIG_FILE"
        exit 1
    fi

    echo -e "${GREEN} Shadowsocks 容器部署并启动成功!${NC}"
    echo -e "${YELLOW} 注意: 请手动配置防火墙以允许 TCP 和 UDP 连接到端口 ${SS_PORT}。${NC}"
    
    # 生成并显示 SSR 链接
    generate_ssr_link
}

# 启动 Shadowsocks
start_shadowsocks() {
    echo -e "${BLUE} 启动 Shadowsocks 容器...${NC}"
    install_docker_if_not_present
    if sudo docker ps -a --format '{{.Names}}' | grep -q "$SS_CONTAINER_NAME"; then
        sudo docker start "$SS_CONTAINER_NAME"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN} Shadowsocks 容器已启动。${NC}"
            generate_ssr_link
        else
            echo -e "${RED} 错误: 启动 Shadowsocks 容器失败。${NC}"
        fi
    else
        echo -e "${YELLOW} Shadowsocks 容器不存在。请先运行 'install' 命令部署。${NC}"
    fi
}


# Uninstall Shadowsocks
uninstall_shadowsocks() {
    echo -e "${RED} 警告: 即将卸载 Shadowsocks 服务。这将停止并删除容器、镜像和配置文件。${NC}"
    read -p " 是否继续? (y/N): " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        echo -e "${BLUE} 正在停止并删除 Shadowsocks 容器...${NC}"
        sudo docker stop "$SS_CONTAINER_NAME" &> /dev/null
        sudo docker rm "$SS_CONTAINER_NAME" &> /dev/null
        echo -e "${GREEN} 容器已删除。${NC}"

        echo -e "${BLUE} 正在删除 Shadowsocks Docker 镜像...${NC}"
        sudo docker rmi "$SS_IMAGE" &> /dev/null
        echo -e "${GREEN} 镜像已删除。${NC}"
        
        echo -e "${BLUE} 正在删除配置文件...${NC}"
        rm -f "$CONFIG_FILE" ssr_client_config.txt
        echo -e "${GREEN} 配置文件已删除。${NC}"

        echo -e "${GREEN} Shadowsocks 服务完全卸载完成。${NC}"
        echo -e "${YELLOW} 注意: 如果需要，请手动删除防火墙规则。${NC}"
    else
        echo -e "${YELLOW} 卸载已取消。${NC}"
    fi
}

# 仅生成 SSR 链接
link_only() {
    echo -e "${BLUE} 正在生成 SSR 客户端链接...${NC}"
    generate_ssr_link
}

# 显示帮助信息
show_help() {
    echo -e "${GREEN} 用法: ${NC}$0 [command]"
    echo -e " 命令:"
    echo -e "  ${YELLOW}install${NC}    部署并启动 Shadowsocks 服务 (如果未安装 Docker 则安装)"
    echo -e "  ${YELLOW}uninstall${NC}  卸载 Shadowsocks 服务"
    echo -e "  ${YELLOW}link${NC}       仅生成 SSR 客户端链接"
    echo -e "  ${YELLOW}help${NC}       显示帮助信息"
    echo -e ""
    echo -e "${BLUE} 当前配置:${NC}"
    echo -e "  ${YELLOW}Port:${NC} $SS_PORT"
    echo -e "  ${YELLOW}Password:${NC} $SS_PASSWORD"
    echo -e "  ${YELLOW}Method:${NC} $SS_METHOD"
    echo -e "  ${YELLOW}Protocol:${NC} $SS_PROTOCOL"
    echo -e "  ${YELLOW}Obfuscation:${NC} $SS_OBFS"
    echo -e ""
    echo -e "${BLUE} 注意:${NC}"
    echo -e "  ${YELLOW}•${NC} 不带参数时默认执行 'install'"
    echo -e "  ${YELLOW}•${NC} 此脚本不自动管理防火墙规则"
    echo -e "  ${YELLOW}•${NC} 请手动配置防火墙以允许端口 ${SS_PORT} (TCP/UDP)"
    echo -e "  ${YELLOW}•${NC} SSR 链接自动生成并保存到文件"
    echo -e "  ${YELLOW}•${NC} 修改 SS_PASSWORD 以提高安全性"
}

# ------------------------------------------------------------------------------
# 主逻辑
# ------------------------------------------------------------------------------
COMMAND="$1"
if [ -z "$COMMAND" ]; then
    COMMAND="install"
fi

case "$COMMAND" in
    install)
        install_shadowsocks
        ;;
    uninstall)
        uninstall_shadowsocks
        ;;
    link)
        link_only
        ;;
    help)
        show_help
        ;;
    *)
        echo -e "${RED} 错误: 无效的命令: $COMMAND${NC}"
        show_help
        exit 1
        ;;
esac 