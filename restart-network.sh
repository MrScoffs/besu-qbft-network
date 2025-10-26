#!/bin/bash

# Script de Restart Inteligente da Rede Besu QBFT
# Para, valida, reinicia e monitora a rede

set -e

# Cores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE} RESTART INTELIGENTE DA REDE BESU${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Função para log
log_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Função para esperar
wait_with_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# 1. Parar a rede
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}     PARANDO A REDE${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_info "Verificando containers em execução..."
running_containers=$(docker ps -q --filter "name=node" | wc -l)
if [ "$running_containers" -gt 0 ]; then
    log_info "Encontrados $running_containers containers rodando"
    log_info "Executando docker-compose down..."
    docker-compose down
    log_success "Rede parada com sucesso"
else
    log_info "Nenhum container rodando"
fi

# 2. Remover containers antigos
echo ""
log_info "Removendo containers antigos..."
old_containers=$(docker ps -aq --filter "name=node" | wc -l)
if [ "$old_containers" -gt 0 ]; then
    docker ps -aq --filter "name=node" | xargs docker rm -f > /dev/null 2>&1 || true
    log_success "Containers antigos removidos: $old_containers"
else
    log_info "Nenhum container antigo encontrado"
fi

# 3. Validar configurações
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}     VALIDANDO CONFIGURAÇÕES${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ ! -f "./validate-config.sh" ]; then
    log_error "Script de validação não encontrado: ./validate-config.sh"
    exit 1
fi

chmod +x ./validate-config.sh
if ./validate-config.sh; then
    log_success "Validação concluída com sucesso!"
else
    log_error "Validação falhou! Verifique os erros acima."
    read -p "Deseja continuar mesmo assim? (s/N): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[sS]$ ]]; then
        log_info "Restart cancelado pelo usuário"
        exit 1
    fi
fi

# 4. Verificar rede Docker
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}     VERIFICANDO REDE DOCKER${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if docker network inspect besu-network > /dev/null 2>&1; then
    log_success "Rede 'besu-network' já existe"
else
    log_warn "Rede 'besu-network' não existe, criando..."
    docker network create besu-network
    log_success "Rede 'besu-network' criada"
fi

# 5. Subir a rede
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}    INICIANDO A REDE${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_info "Executando docker-compose up -d..."
docker-compose up -d

log_success "Containers iniciados!"
echo ""

# 6. Aguardar inicialização
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}     AGUARDANDO INICIALIZAÇÃO${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_info "Aguardando 10 segundos para os nós iniciarem..."
for i in {10..1}; do
    echo -ne "\r  Aguardando... $i segundos restantes  "
    sleep 1
done
echo -ne "\r  Aguardando... Concluído!           \n"

# 7. Monitorar status dos containers
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}     STATUS DOS CONTAINERS${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

docker ps -a --filter "name=node" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
log_info "Verificando status individual..."
echo ""

healthy_nodes=0
for i in {1..6}; do
    status=$(docker inspect -f '{{.State.Status}}' node$i 2>/dev/null || echo "not_found")
    if [ "$status" == "running" ]; then
        log_success "Node-$i: Running"
        ((healthy_nodes++))
    elif [ "$status" == "exited" ]; then
        exit_code=$(docker inspect -f '{{.State.ExitCode}}' node$i 2>/dev/null || echo "?")
        log_error "Node-$i: Exited (código: $exit_code)"
    else
        log_warn "Node-$i: $status"
    fi
done

echo ""
log_info "Nós saudáveis: $healthy_nodes/6"

# 8. Verificar logs de erro
if [ $healthy_nodes -lt 6 ]; then
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}   VERIFICANDO LOGS DE ERRO${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    for i in {1..6}; do
        status=$(docker inspect -f '{{.State.Status}}' node$i 2>/dev/null || echo "not_found")
        if [ "$status" != "running" ]; then
            log_warn "Últimas 10 linhas de log do Node-$i:"
            echo "---"
            docker logs node$i 2>&1 | tail -10
            echo ""
        fi
    done
fi

# 9. Testar conectividade
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}   TESTANDO CONECTIVIDADE${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

successful_tests=0

for i in {1..6}; do
    port=$((8544 + i))

    # Aguardar mais um pouco antes de testar
    sleep 1

    # Testar se o nó está respondendo
    response=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"net_listening","params":[],"id":1}' \
        http://127.0.0.1:$port 2>/dev/null || echo "error")

    if echo "$response" | grep -q '"result":true'; then
        log_success "Node-$i (porta $port): RPC respondendo, listening=true"
        ((successful_tests++))
    elif echo "$response" | grep -q '"result":false'; then
        log_warn "Node-$i (porta $port): RPC respondendo, mas listening=false"
    else
        log_error "Node-$i (porta $port): RPC não está respondendo"
    fi
done

echo ""
log_info "Testes de conectividade: $successful_tests/6 bem-sucedidos"

# 10. Verificar peer count
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}    VERIFICANDO PEERS${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_info "Aguardando mais 5 segundos para descoberta de peers..."
sleep 5

for i in {1..6}; do
    port=$((8544 + i))

    peer_count_response=$(curl -s -X POST --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        http://127.0.0.1:$port 2>/dev/null || echo "error")

    if echo "$peer_count_response" | grep -q '"result"'; then
        peer_count_hex=$(echo "$peer_count_response" | grep -oP '"result":"\K[^"]+')
        peer_count=$((peer_count_hex))

        if [ "$peer_count" -ge 5 ]; then
            log_success "Node-$i: $peer_count peers conectados (esperado: 5)"
        elif [ "$peer_count" -gt 0 ]; then
            log_warn "Node-$i: $peer_count peers conectados (esperado: 5)"
        else
            log_error "Node-$i: 0 peers conectados"
        fi
    else
        log_error "Node-$i: Não foi possível obter peer count"
    fi
done

# Resumo final
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  RESUMO DO RESTART${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

if [ $healthy_nodes -eq 6 ] && [ $successful_tests -eq 6 ]; then
    echo -e "${GREEN}✓ RESTART CONCLUÍDO COM SUCESSO!${NC}"
    echo ""
    echo "  Nós rodando: $healthy_nodes/6"
    echo "  Testes RPC: $successful_tests/6"
    echo ""
    log_info "Use './monitor-network.sh' para monitoramento contínuo"
    log_info "Use 'docker logs -f node1' para ver logs de um nó específico"
    exit 0
elif [ $healthy_nodes -eq 6 ]; then
    echo -e "${YELLOW}⚠ RESTART CONCLUÍDO COM AVISOS${NC}"
    echo ""
    echo "  Nós rodando: $healthy_nodes/6"
    echo "  Testes RPC: $successful_tests/6"
    echo ""
    log_warn "Alguns nós podem precisar de mais tempo para inicializar"
    log_info "Verifique os logs com: docker logs -f nodeX"
    exit 0
else
    echo -e "${RED}✗ RESTART FALHOU${NC}"
    echo ""
    echo "  Nós rodando: $healthy_nodes/6"
    echo "  Testes RPC: $successful_tests/6"
    echo ""
    log_error "Alguns nós não iniciaram corretamente"
    log_info "Verifique os logs acima para mais detalhes"
    log_info "Use 'docker logs nodeX' para ver logs completos"
    exit 1
fi
