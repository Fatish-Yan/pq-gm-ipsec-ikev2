#!/bin/bash
# PQ-GM-IPSec & IKEv2 - Docker 测试脚本
#
# 用法:
#   sudo ./run-test.sh [init|build|start|stop|status|logs|exec]

set -e

# Sudo 密码（用于自动化脚本）
SUDO_PASSWORD="1574a"
SUDO="echo $SUDO_PASSWORD | sudo -S"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 初始化测试环境
init_test() {
    log_info "初始化测试环境..."

    # 创建测试数据目录
    mkdir -p "$PROJECT_ROOT/tests/data/pcaps"
    mkdir -p "$PROJECT_ROOT/tests/data/logs"
    mkdir -p "$PROJECT_ROOT/tests/data/configs_snapshot"

    # 生成测试证书
    log_info "生成测试证书..."
    cd "$SCRIPT_DIR/configs"

    # CA
    if [ ! -f caCert.pem ]; then
        pki --gen --type rsa --size 3072 --outform pem > caKey.pem
        pki --self --type rsa --in caKey.pem --dn "C=CN, O=PQGM, CN=PQGM Test CA" --ca --lifetime 3650 --outform pem > caCert.pem
        log_info "CA 证书已生成"
    fi

    # Initiator
    if [ ! -f initiatorCert.pem ]; then
        pki --gen --type rsa --size 3072 --outform pem > initiator/initiatorKey.pem
        pki --pub --type rsa --in initiator/initiatorKey.pem | pki --issue --cacert caCert.pem --cakey caKey.pem --dn "C=CN, O=PQGM, CN=initiator" --san initator.pqgm.test --lifetime 365 --outform pem > initiator/initiatorCert.pem
        cp caCert.pem initiator/
        log_info "Initiator 证书已生成"
    fi

    # Responder
    if [ ! -f responderCert.pem ]; then
        pki --gen --type rsa --size 3072 --outform pem > responder/responderKey.pem
        pki --pub --type rsa --in responder/responderKey.pem | pki --issue --cacert caCert.pem --cakey caKey.pem --dn "C=CN, O=PQGM, CN=responder" --san responder.pqgm.test --lifetime 365 --outform pem > responder/responderCert.pem
        cp caCert.pem responder/
        log_info "Responder 证书已生成"
    fi

    log_info "初始化完成！"
}

# 构建 Docker 镜像
build() {
    log_info "构建 Docker 镜像..."
    cd "$SCRIPT_DIR"
    $SUDO docker-compose build
}

# 启动容器
start() {
    log_info "启动测试容器..."
    cd "$SCRIPT_DIR"
    $SUDO docker-compose up -d
    log_info "容器已启动"
    status
}

# 停止容器
stop() {
    log_info "停止测试容器..."
    cd "$SCRIPT_DIR"
    $SUDO docker-compose down
    log_info "容器已停止"
}

# 查看状态
status() {
    log_info "容器状态:"
    $SUDO docker-compose ps
    echo ""
    log_info "网络状态:"
    $SUDO docker network inspect docker_pqgm_net 2>/dev/null || echo "网络未创建"
}

# 查看日志
logs() {
    local service=$1
    cd "$SCRIPT_DIR"
    if [ -z "$service" ]; then
        $SUDO docker-compose logs -f
    else
        $SUDO docker-compose logs -f "$service"
    fi
}

# 进入容器
exec_container() {
    local service=$1
    if [ -z "$service" ]; then
        log_error "请指定容器名称 (initiator 或 responder)"
        exit 1
    fi
    cd "$SCRIPT_DIR"
    $SUDO docker-compose exec "$service" bash
}

# 运行测试用例
run_test() {
    local tc_id=$1
    if [ -z "$tc_id" ]; then
        log_error "请指定测试用例 ID (如 TC-HS-001)"
        exit 1
    fi

    log_info "运行测试用例: $tc_id"

    # 保存配置快照
    local snapshot_dir="$PROJECT_ROOT/tests/data/configs_snapshot"
    cp -r "$SCRIPT_DIR/configs"/* "$snapshot_dir/$tc_id.conf/"

    # 启动 charon 并记录日志
    local log_file="$PROJECT_ROOT/tests/data/logs/$tc_id.log"
    local pcap_file="$PROJECT_ROOT/tests/data/pcaps/$tc_id.pcapng"

    # TODO: 实现 actual test logic
    log_warn "测试用例执行逻辑待实现"
}

# 主函数
case "${1:-}" in
    init)
        init_test
        ;;
    build)
        build
        ;;
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop && start
        ;;
    status)
        status
        ;;
    logs)
        logs "${2:-}"
        ;;
    exec)
        exec_container "${2:-}"
        ;;
    test)
        run_test "${2:-}"
        ;;
    *)
        echo "用法: $0 {init|build|start|stop|restart|status|logs|exec|test}"
        echo ""
        echo "命令说明:"
        echo "  init       - 初始化测试环境（生成证书等）"
        echo "  build      - 构建 Docker 镜像"
        echo "  start      - 启动测试容器"
        echo "  stop       - 停止测试容器"
        echo "  restart    - 重启测试容器"
        echo "  status     - 查看容器状态"
        echo "  logs [srv] - 查看日志 (srv: initiator|responder)"
        echo "  exec srv   - 进入容器 (srv: initiator|responder)"
        echo "  test TC-ID - 运行测试用例"
        exit 1
        ;;
esac
