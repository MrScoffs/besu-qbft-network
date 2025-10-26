#!/bin/bash

# Dashboard de Monitoramento da Rede Besu QBFT
# Mostra status em tempo real dos nós, peers, blocos e transações

# Cores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Função para limpar a tela
clear_screen() {
    printf '\033[2J\033[H'
}

# Função para obter informação via RPC
get_rpc_info() {
    local port=$1
    local method=$2
    local result=$(curl -s -X POST --max-time 2 \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":[],\"id\":1}" \
        http://127.0.0.1:$port 2>/dev/null)

    if [ -z "$result" ] || echo "$result" | grep -q "error"; then
        echo "N/A"
    else
        echo "$result" | grep -oP '"result":"\K[^"]+' || echo "$result" | grep -oP '"result":\K[^,}]+'
    fi
}

# Função para converter hex para decimal
hex_to_dec() {
    local hex=$1
    if [ "$hex" == "N/A" ] || [ -z "$hex" ]; then
        echo "N/A"
    else
        printf "%d" "$hex" 2>/dev/null || echo "N/A"
    fi
}

# Função para obter enode
get_enode() {
    local port=$1
    local enode=$(curl -s -X POST --max-time 2 \
        --data '{"jsonrpc":"2.0","method":"net_enode","params":[],"id":1}' \
        http://127.0.0.1:$port 2>/dev/null)

    if echo "$enode" | grep -q '"result"'; then
        echo "$enode" | grep -oP '"result":"\K[^"]+' | sed 's/enode:\/\/\([^@]*\).*/\1/' | cut -c1-16
    else
        echo "N/A"
    fi
}

# Intervalo de atualização (segundos)
REFRESH_INTERVAL=5

echo -e "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     DASHBOARD DE MONITORAMENTO - BESU QBFT NETWORK            ║"
echo "║     Pressione Ctrl+C para sair                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
sleep 2

while true; do
    clear_screen

    # Cabeçalho
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}                     BESU QBFT NETWORK DASHBOARD                          ${NC}"
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Timestamp
    echo -e "${YELLOW} Última atualização: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""

    # Status dos containers
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}${BOLD} STATUS DOS CONTAINERS${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    healthy_count=0
    for i in {1..6}; do
        status=$(docker inspect -f '{{.State.Status}}' node$i 2>/dev/null || echo "not_found")
        uptime=$(docker inspect -f '{{.State.StartedAt}}' node$i 2>/dev/null || echo "N/A")

        if [ "$status" == "running" ]; then
            echo -e " ${GREEN}●${NC} Node-$i: ${GREEN}Running${NC}"
            ((healthy_count++))
        elif [ "$status" == "exited" ]; then
            exit_code=$(docker inspect -f '{{.State.ExitCode}}' node$i 2>/dev/null || echo "?")
            echo -e " ${RED}●${NC} Node-$i: ${RED}Exited (código: $exit_code)${NC}"
        else
            echo -e " ${YELLOW}●${NC} Node-$i: ${YELLOW}$status${NC}"
        fi
    done

    echo ""
    echo -e " ${BOLD}Total:${NC} $healthy_count/6 nós rodando"

    # Informações da rede
    echo ""
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}${BOLD} INFORMAÇÕES DA REDE${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    printf " ${BOLD}%-8s %-10s %-8s %-10s %-10s %-18s${NC}\n" \
        "NODE" "STATUS" "PEERS" "BLOCK" "TX POOL" "ENODE"
    echo " ────────────────────────────────────────────────────────────────────────────"

    for i in {1..6}; do
        port=$((8544 + i))

        # Verificar se o container está rodando
        status=$(docker inspect -f '{{.State.Status}}' node$i 2>/dev/null || echo "down")

        if [ "$status" == "running" ]; then
            # Obter informações via RPC
            listening=$(get_rpc_info $port "net_listening")
            peer_count_hex=$(get_rpc_info $port "net_peerCount")
            peer_count=$(hex_to_dec "$peer_count_hex")
            block_number_hex=$(get_rpc_info $port "eth_blockNumber")
            block_number=$(hex_to_dec "$block_number_hex")
            pending_tx_hex=$(get_rpc_info $port "eth_getBlockTransactionCountByNumber" | head -1)
            pending_tx=$(hex_to_dec "$pending_tx_hex")
            enode_short=$(get_enode $port)

            # Status colorido
            if [ "$listening" == "true" ]; then
                status_icon="${GREEN}✓${NC}"
                status_text="${GREEN}UP${NC}"
            else
                status_icon="${YELLOW}⚠${NC}"
                status_text="${YELLOW}DOWN${NC}"
            fi

            # Peers colorido
            if [ "$peer_count" == "N/A" ]; then
                peer_display="${YELLOW}N/A${NC}"
            elif [ "$peer_count" -ge 5 ]; then
                peer_display="${GREEN}$peer_count${NC}"
            elif [ "$peer_count" -gt 0 ]; then
                peer_display="${YELLOW}$peer_count${NC}"
            else
                peer_display="${RED}$peer_count${NC}"
            fi

            printf " $status_icon %-6s %-18s %-14s %-10s %-10s %s\n" \
                "Node-$i" "$status_text" "$peer_display" "$block_number" "$pending_tx" "$enode_short..."
        else
            printf " ${RED}✗${NC} %-6s ${RED}%-18s${NC} %-14s %-10s %-10s %s\n" \
                "Node-$i" "OFFLINE" "-" "-" "-" "-"
        fi
    done

    # Consenso QBFT
    echo ""
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}${BOLD}  CONSENSO QBFT${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Pegar informações do primeiro nó disponível
    for i in {1..6}; do
        port=$((8544 + i))
        status=$(docker inspect -f '{{.State.Status}}' node$i 2>/dev/null || echo "down")

        if [ "$status" == "running" ]; then
            block_number_hex=$(get_rpc_info $port "eth_blockNumber")
            block_number=$(hex_to_dec "$block_number_hex")

            if [ "$block_number" != "N/A" ]; then
                echo -e " ${CYAN}Último bloco:${NC}        #$block_number"
                echo -e " ${CYAN}Chain ID:${NC}            381660001"
                echo -e " ${CYAN}Período de bloco:${NC}    5 segundos"
                echo -e " ${CYAN}Validadores:${NC}         6 nós"
                break
            fi
        fi
    done

    # Estatísticas de rede
    echo ""
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}${BOLD} ESTATÍSTICAS${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    total_peers=0
    nodes_with_peers=0
    max_block=0
    min_block=999999999

    for i in {1..6}; do
        port=$((8544 + i))
        status=$(docker inspect -f '{{.State.Status}}' node$i 2>/dev/null || echo "down")

        if [ "$status" == "running" ]; then
            peer_count_hex=$(get_rpc_info $port "net_peerCount")
            peer_count=$(hex_to_dec "$peer_count_hex")

            if [ "$peer_count" != "N/A" ]; then
                total_peers=$((total_peers + peer_count))
                if [ "$peer_count" -gt 0 ]; then
                    ((nodes_with_peers++))
                fi
            fi

            block_number_hex=$(get_rpc_info $port "eth_blockNumber")
            block_number=$(hex_to_dec "$block_number_hex")

            if [ "$block_number" != "N/A" ] && [ "$block_number" -gt 0 ]; then
                if [ "$block_number" -gt "$max_block" ]; then
                    max_block=$block_number
                fi
                if [ "$block_number" -lt "$min_block" ]; then
                    min_block=$block_number
                fi
            fi
        fi
    done

    avg_peers=0
    if [ "$healthy_count" -gt 0 ]; then
        avg_peers=$((total_peers / healthy_count))
    fi

    sync_status="✓ Sincronizado"
    if [ "$max_block" != "$min_block" ] && [ "$min_block" != 999999999 ]; then
        sync_status="⚠ Dessincronizado (diferença: $((max_block - min_block)) blocos)"
    fi

    echo -e " ${CYAN}Nós ativos:${NC}          $healthy_count/6"
    echo -e " ${CYAN}Nós com peers:${NC}       $nodes_with_peers/6"
    echo -e " ${CYAN}Média de peers:${NC}      $avg_peers peers/nó"
    echo -e " ${CYAN}Status de sincronização:${NC}  $sync_status"

    # Portas de acesso
    echo ""
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}${BOLD}🔌 PORTAS DE ACESSO${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    printf " ${BOLD}%-8s %-12s %-12s %-12s %-12s${NC}\n" \
        "NODE" "HTTP RPC" "WebSocket" "P2P" "Metrics"
    echo " ────────────────────────────────────────────────────────────────"

    for i in {1..6}; do
        http_port=$((8544 + i))
        ws_port=$((8644 + i))
        p2p_port=$((30302 + i))
        metrics_port=$((9544 + i))

        status=$(docker inspect -f '{{.State.Status}}' node$i 2>/dev/null || echo "down")

        if [ "$status" == "running" ]; then
            icon="${GREEN}●${NC}"
        else
            icon="${RED}●${NC}"
        fi

        printf " $icon %-6s %-12s %-12s %-12s %-12s\n" \
            "Node-$i" ":$http_port" ":$ws_port" ":$p2p_port" ":$metrics_port"
    done

    # Comandos úteis
    echo ""
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}${BOLD} COMANDOS ÚTEIS${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e " ${CYAN}Ver logs de um nó:${NC}        docker logs -f node1"
    echo -e " ${CYAN}Reiniciar rede:${NC}           ./restart-network.sh"
    echo -e " ${CYAN}Validar configuração:${NC}     ./validate-config.sh"
    echo -e " ${CYAN}Testar RPC:${NC}               curl -X POST --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' http://127.0.0.1:8545"

    # Rodapé
    echo ""
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Próxima atualização em $REFRESH_INTERVAL segundos... (Ctrl+C para sair)${NC}"

    sleep $REFRESH_INTERVAL
done
