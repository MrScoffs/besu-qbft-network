#!/bin/bash
set -e

# Script para implantar o contrato Simple na rede Besu
# Deve ser executado após a rede estar estável

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[DEPLOY]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[DEPLOY OK]${NC} $1"
}

log_error() {
    echo -e "${RED}[DEPLOY ERROR]${NC} $1"
}

# Diretórios
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARDHAT_DIR="$BASE_DIR/../Hardhat-contracts"

# Verificar se Hardhat existe
if [ ! -d "$HARDHAT_DIR" ]; then
    log_error "Diretório Hardhat-contracts não encontrado em $HARDHAT_DIR"
    exit 1
fi

cd "$HARDHAT_DIR"

# Verificar conectividade com a rede
log_info "Verificando conectividade com a rede Besu..."
for i in {1..10}; do
    if curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:8545 > /dev/null 2>&1; then
        log_success "Rede Besu acessível"
        break
    fi
    if [ $i -eq 10 ]; then
        log_error "Rede Besu não está acessível em http://127.0.0.1:8545"
        exit 1
    fi
    log_info "Tentativa $i/10 falhou, aguardando 3s..."
    sleep 3
done

# Aguardar estabilização adicional
log_info "Aguardando estabilização adicional (10 segundos)..."
sleep 10

# Deploy do contrato Simple
log_info "Implantando contrato Simple..."

# Executar deploy com Hardhat Ignition (modo não-interativo)
# Usa 'yes' para responder automaticamente a todas as confirmações
# O timeout garante que o yes seja interrompido após o deploy
DEPLOY_OUTPUT=$(timeout 60 bash -c "yes | npx hardhat ignition deploy ./ignition/modules/Simple.ts --network besu --reset" 2>&1)
DEPLOY_EXIT_CODE=$?

# Exit code 124 significa timeout (esperado), consideramos sucesso se deploy ocorreu
if [ $DEPLOY_EXIT_CODE -eq 124 ]; then
    DEPLOY_EXIT_CODE=0
fi

if [ $DEPLOY_EXIT_CODE -ne 0 ]; then
    log_error "Falha ao implantar contrato Simple"
    echo "$DEPLOY_OUTPUT"
    exit 1
fi

# Extrair endereço do contrato do output
CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -oP 'simple#simple - 0x[a-fA-F0-9]{40}' | grep -oP '0x[a-fA-F0-9]{40}' | head -1)

if [ -z "$CONTRACT_ADDRESS" ]; then
    log_error "Não foi possível extrair o endereço do contrato"
    echo "$DEPLOY_OUTPUT"
    exit 1
fi

log_success "Contrato Simple implantado em: $CONTRACT_ADDRESS"

# Atualizar networkconfig.json com novo endereço
NETWORKCONFIG="$BASE_DIR/../Hyperleadger-Caliper/networks/besu/networkconfig.json"

if [ ! -f "$NETWORKCONFIG" ]; then
    log_error "Arquivo networkconfig.json não encontrado em $NETWORKCONFIG"
    exit 1
fi

log_info "Atualizando networkconfig.json com novo endereço..."

# Usar sed para substituir o endereço do contrato simple
sed -i "s/\"simple\": {[^}]*\"address\": \"[^\"]*\"/\"simple\": {\n                \"address\": \"$CONTRACT_ADDRESS\"/" "$NETWORKCONFIG"

# Método mais robusto usando jq se disponível
if command -v jq &> /dev/null; then
    TEMP_FILE=$(mktemp)
    jq ".ethereum.contracts.simple.address = \"$CONTRACT_ADDRESS\"" "$NETWORKCONFIG" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$NETWORKCONFIG"
    log_success "networkconfig.json atualizado com jq"
else
    # Fallback: substituição mais simples
    sed -i "s|\"simple\": {[[:space:]]*\"address\": \"0x[a-fA-F0-9]*\"|\"simple\": {\n                \"address\": \"$CONTRACT_ADDRESS\"|" "$NETWORKCONFIG"
    log_success "networkconfig.json atualizado com sed"
fi

log_success "=========================================="
log_success "Contrato Simple implantado com sucesso!"
log_success "Endereço: $CONTRACT_ADDRESS"
log_success "=========================================="

exit 0
