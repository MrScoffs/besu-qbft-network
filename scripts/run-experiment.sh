#!/bin/bash
set -e

# ==========================================
# Script para executar experimentos automatizados
# Uso: ./run-experiment.sh <nodes> <blocktime> <consensus> <version>
# Exemplo: ./run-experiment.sh 6 5 qbft 25.10.0
# ==========================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ==========================================
# 1. VALIDAR PARAMETROS
# ==========================================

if [ "$#" -ne 4 ]; then
    log_error "Uso: $0 <nodes> <blocktime> <consensus> <version>"
    log_error "Exemplo: $0 6 5 qbft 25.10.0"
    exit 1
fi

NODES=$1
BLOCKTIME=$2
CONSENSUS=$3
VERSION=$4

# Validar nodes (4, 6, 8, 10)
if [[ ! "$NODES" =~ ^(4|6|8|10)$ ]]; then
    log_error "Numero de nos invalido: $NODES. Use: 4, 6, 8 ou 10"
    exit 1
fi

# Validar blocktime (2, 5, 10)
if [[ ! "$BLOCKTIME" =~ ^(2|5|10)$ ]]; then
    log_error "Tempo de bloco invalido: $BLOCKTIME. Use: 2, 5 ou 10"
    exit 1
fi

# Validar consensus (qbft, ibft)
if [[ ! "$CONSENSUS" =~ ^(qbft|ibft)$ ]]; then
    log_error "Consenso invalido: $CONSENSUS. Use: qbft ou ibft"
    exit 1
fi

# Validar version
if [[ ! "$VERSION" =~ ^(24\.7\.0|25\.9\.0|25\.10\.0)$ ]]; then
    log_error "Versao invalida: $VERSION. Use: 24.7.0, 25.9.0 ou 25.10.0"
    exit 1
fi

EXP_NAME="${NODES}n-${BLOCKTIME}s-${CONSENSUS}-v${VERSION}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EXP_NAME_WITH_TS="${EXP_NAME}_${TIMESTAMP}"

log_info "=========================================="
log_info "Iniciando experimento: $EXP_NAME"
log_info "Timestamp: $TIMESTAMP"
log_info "=========================================="
log_info "Nos: $NODES"
log_info "Tempo de bloco: ${BLOCKTIME}s"
log_info "Consenso: $CONSENSUS"
log_info "Versao Besu: $VERSION"
log_info "=========================================="

# Diretórios
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

BESU_DIR="$BASE_DIR/besu-$VERSION"
NETWORK_FILES="$BASE_DIR/networkFiles"
PERMISSIONED_NET="$BASE_DIR/Permissioned-Network"
CALIPER_DIR="$BASE_DIR/../Hyperleadger-Caliper"
RESULTS_HTML="$CALIPER_DIR/reports_htmls/experiments/$EXP_NAME_WITH_TS"
RESULTS_CSV="$CALIPER_DIR/reports_csv/experiments/$EXP_NAME_WITH_TS"

# Verificar se Besu existe
if [ ! -d "$BESU_DIR" ]; then
    log_error "Besu $VERSION nao encontrado em $BESU_DIR"
    log_error "Execute: ./scripts/download-besu-versions.sh"
    exit 1
fi

# ==========================================
# 2. PARAR REDE ATUAL E LIMPAR COMPLETAMENTE
# ==========================================

log_info "Parando rede atual..."
if [ -f "$BASE_DIR/docker-compose.yml" ]; then
    cd "$BASE_DIR"
    docker-compose down 2>/dev/null || true
    log_success "Rede parada"
fi

log_info "Limpando estado anterior para evitar vies..."

# Remover containers relacionados
log_info "Removendo containers antigos..."
docker ps -a | grep "node-besu" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || true

# Limpar networkFiles completo (Besu requer que nao exista)
if [ -d "$NETWORK_FILES" ]; then
    log_info "Limpando networkFiles/ completo..."
    rm -rf "$NETWORK_FILES/keys" "$NETWORK_FILES/networkFiles" 2>/dev/null || true
fi

# Limpar Permissioned-Network (usar Docker para limpar arquivos criados por containers)
if [ -d "$PERMISSIONED_NET" ]; then
    log_info "Limpando Permissioned-Network/ (usando Docker)..."
    docker run --rm -v "$PERMISSIONED_NET:/data" busybox sh -c "rm -rf /data/*" 2>/dev/null || true
fi

# Recriar estrutura
mkdir -p "$NETWORK_FILES/keys"
mkdir -p "$PERMISSIONED_NET"

log_success "Limpeza completa realizada"

# ==========================================
# 3. PREPARAR GENESIS
# ==========================================

log_info "Preparando genesis para consenso $CONSENSUS..."

# Selecionar template
if [ "$CONSENSUS" = "qbft" ]; then
    GENESIS_TEMPLATE="$BASE_DIR/genesis_QBFT.json"
else
    GENESIS_TEMPLATE="$BASE_DIR/genesis_IBFT.json"
fi

if [ ! -f "$GENESIS_TEMPLATE" ]; then
    log_error "Template genesis nao encontrado: $GENESIS_TEMPLATE"
    exit 1
fi

# Copiar template e modificar parametros
GENESIS_TEMP="/tmp/genesis_temp_$$.json"
cp "$GENESIS_TEMPLATE" "$GENESIS_TEMP"

# Modificar blockperiodseconds usando jq ou sed
if command -v jq &> /dev/null; then
    log_info "Modificando blockperiodseconds para ${BLOCKTIME}..."
    if [ "$CONSENSUS" = "qbft" ]; then
        jq ".genesis.config.qbft.blockperiodseconds = $BLOCKTIME | .blockchain.nodes.count = $NODES" "$GENESIS_TEMP" > "$GENESIS_TEMP.new"
    else
        jq ".genesis.config.ibft2.blockperiodseconds = $BLOCKTIME | .blockchain.nodes.count = $NODES" "$GENESIS_TEMP" > "$GENESIS_TEMP.new"
    fi
    mv "$GENESIS_TEMP.new" "$GENESIS_TEMP"
else
    log_warning "jq nao encontrado, usando sed..."
    sed -i "s/\"blockperiodseconds\": [0-9]*/\"blockperiodseconds\": $BLOCKTIME/" "$GENESIS_TEMP"
    sed -i "s/\"count\": [0-9]*/\"count\": $NODES/" "$GENESIS_TEMP"
fi

# Salvar para usar depois (Besu vai recriar networkFiles/)
GENESIS_FINAL="/tmp/genesis_final_$$.json"
cp "$GENESIS_TEMP" "$GENESIS_FINAL"
rm "$GENESIS_TEMP"

log_success "Genesis configurado"

# ==========================================
# 4. GERAR CHAVES COM BESU
# ==========================================

log_info "Gerando chaves para $NODES nos usando Besu $VERSION..."

# Besu requer que networkFiles NAO exista - remover completamente
rm -rf "$NETWORK_FILES"

cd "$BASE_DIR"

if [ "$CONSENSUS" = "qbft" ]; then
    CONSENSUS_PARAM="QBFT"
else
    CONSENSUS_PARAM="IBFT2"
fi

# Besu vai criar networkFiles/ do zero
"$BESU_DIR/bin/besu" operator generate-blockchain-config \
    --config-file="$GENESIS_FINAL" \
    --to=networkFiles \
    --private-key-file-name=key 2>&1 | grep -v "^SLF4J" || true

# Limpar arquivo temporario
rm -f "$GENESIS_FINAL"

log_success "Chaves geradas em $NETWORK_FILES/keys/"

# ==========================================
# 5. CONFIGURAR NOS
# ==========================================

log_info "Executando generate-nodes-config.sh..."
cd "$BASE_DIR"
bash ./generate-nodes-config.sh > /dev/null 2>&1

if [ ! -d "$PERMISSIONED_NET/Node-1" ]; then
    log_error "Falha ao gerar configuracao dos nos"
    exit 1
fi

log_success "Nos configurados em $PERMISSIONED_NET/"

# Copiar genesis.json para Permissioned-Network (necessario para Docker)
log_info "Copiando genesis.json para Permissioned-Network/..."
cp "$NETWORK_FILES/genesis.json" "$PERMISSIONED_NET/genesis.json"

# Adicionar permissao para conta do Hardhat deploy
log_info "Adicionando permissao para conta de deploy do Hardhat..."
DEPLOY_ACCOUNT="0x171aaf31af122474e10b72e9eda8c90acf4a74ca"  # lowercase para consistencia

for node_dir in "$PERMISSIONED_NET"/Node-*; do
    if [ -d "$node_dir" ]; then
        PERMISSIONS_FILE="$node_dir/data/permissions_config.toml"
        if [ -f "$PERMISSIONS_FILE" ]; then
            # Verificar se a conta ja esta presente (case insensitive)
            if ! grep -qi "$DEPLOY_ACCOUNT" "$PERMISSIONS_FILE"; then
                # Ler a linha atual de accounts-allowlist
                current_line=$(grep "^accounts-allowlist=" "$PERMISSIONS_FILE")
                # Adicionar nova conta (antes do colchete final)
                new_line=$(echo "$current_line" | sed "s/\]$/,\"$DEPLOY_ACCOUNT\"\]/")
                # Substituir a linha
                sed -i "s|^accounts-allowlist=.*|$new_line|" "$PERMISSIONS_FILE"
                log_info "  Permissao adicionada em $(basename $node_dir)"
            else
                log_info "  Conta ja presente em $(basename $node_dir)"
            fi
        fi
    fi
done

log_success "Permissoes configuradas"

# ==========================================
# 7. GERAR DOCKER-COMPOSE
# ==========================================

log_info "Gerando docker-compose.yml com imagem Besu $VERSION..."

# Backup do script original
cp generate-docker-compose.sh generate-docker-compose.sh.bak

# Modificar IMAGE_NAME no script
sed -i "s/IMAGE_NAME=\"besu-image-local:[^\"]*\"/IMAGE_NAME=\"besu-image-local:$VERSION\"/" generate-docker-compose.sh

bash ./generate-docker-compose.sh > /dev/null 2>&1

# Restaurar script original
mv generate-docker-compose.sh.bak generate-docker-compose.sh

if [ ! -f "$BASE_DIR/docker-compose.yml" ]; then
    log_error "Falha ao gerar docker-compose.yml"
    exit 1
fi

log_success "docker-compose.yml gerado"

# ==========================================
# 8. BUILD DA IMAGEM DOCKER
# ==========================================

log_info "Verificando se precisa fazer build da imagem..."

if ! docker images | grep -q "besu-image-local.*$VERSION"; then
    log_info "Fazendo build da imagem besu-image-local:$VERSION..."

    # Criar Dockerfile temporario
    cat > Dockerfile.temp <<EOF
FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y openjdk-21-jre-headless && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY besu-$VERSION /opt/besu

WORKDIR /opt/besu

ENTRYPOINT ["/opt/besu/bin/besu"]
EOF

    docker build -t "besu-image-local:$VERSION" -f Dockerfile.temp . 2>&1 | grep -E "(Step|Successfully)" || true
    rm Dockerfile.temp

    log_success "Imagem Docker criada"
else
    log_success "Imagem besu-image-local:$VERSION ja existe"
fi

# ==========================================
# 9. CRIAR REDE DOCKER
# ==========================================

log_info "Criando rede Docker..."
docker network create besu-network 2>/dev/null || log_warning "Rede besu-network ja existe"

# ==========================================
# 10. SUBIR REDE
# ==========================================

log_info "Subindo rede com docker-compose..."
cd "$BASE_DIR"
docker-compose up -d

log_success "Containers iniciados"

# ==========================================
# 11. AGUARDAR ESTABILIZACAO
# ==========================================

log_info "Aguardando rede estabilizar (90s)..."
sleep 90

# Verificar se algum node esta respondendo
log_info "Verificando conectividade..."
for i in {1..10}; do
    if curl -s -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:8545 > /dev/null 2>&1; then
        log_success "Rede operacional"
        break
    fi
    if [ $i -eq 10 ]; then
        log_error "Rede nao respondeu apos 10 tentativas"
        log_info "Mostrando logs dos containers..."
        docker-compose logs --tail=30
        exit 1
    fi
    log_info "Tentativa $i/10 falhou, aguardando 10s..."
    sleep 10
done

# ==========================================
# 12. IMPLANTAR CONTRATO SIMPLE
# ==========================================

log_info "Implantando contrato Simple na rede..."
bash "$BASE_DIR/scripts/deploy-simple-contract.sh"

if [ $? -ne 0 ]; then
    log_error "Falha ao implantar contrato Simple"
    log_info "Mostrando logs dos containers..."
    docker-compose logs --tail=30
    exit 1
fi

log_success "Contrato Simple implantado e networkconfig.json atualizado"

# ==========================================
# 13. EXECUTAR CALIPER
# ==========================================

log_info "Executando Caliper..."
cd "$CALIPER_DIR"

# Criar diretorios de resultados
mkdir -p "$RESULTS_HTML"
mkdir -p "$RESULTS_CSV"

# Executar benchmark Simple
log_info "Executando benchmark Simple (open, query, transfer)..."

for BENCHMARK in open query transfer; do
    log_info "  Executando: $BENCHMARK..."

    BENCHMARK_FILE="benchmarks/scenario-monitoring/Simple/config-${BENCHMARK}.yaml"

    if [ ! -f "$BENCHMARK_FILE" ]; then
        log_warning "  Benchmark $BENCHMARK_FILE nao encontrado, pulando..."
        continue
    fi

    # Executar com timeout de 10 minutos (600 segundos)
    timeout 600 npx caliper launch manager \
        --caliper-workspace ./ \
        --caliper-benchconfig "$BENCHMARK_FILE" \
        --caliper-networkconfig networks/besu/networkconfig.json \
        --caliper-bind-sut besu:latest \
        --caliper-flow-skip-install \
        > "$RESULTS_HTML/${BENCHMARK}.log" 2>&1

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 124 ]; then
        log_warning "  Benchmark $BENCHMARK atingiu timeout de 10 minutos"
    elif [ $EXIT_CODE -ne 0 ]; then
        log_warning "  Benchmark $BENCHMARK falhou com codigo $EXIT_CODE"
    else
        log_success "  Benchmark $BENCHMARK concluido"
    fi

    # Mover report.html
    if [ -f "report.html" ]; then
        mv report.html "$RESULTS_HTML/${BENCHMARK}_report.html"
        log_success "  Report HTML salvo: $RESULTS_HTML/${BENCHMARK}_report.html"
    fi

    sleep 5
done

log_success "Caliper executado"

# ==========================================
# 14. EXTRAIR CSVs
# ==========================================

log_info "Convertendo HTMLs para CSV..."
python3 extract_csv.py 2>&1 | tail -3 || log_warning "Conversao CSV falhou"

# Mover CSVs para diretorio do experimento
if [ -d "reports_csv/open" ]; then
    cp -r reports_csv/open/* "$RESULTS_CSV/" 2>/dev/null || true
    cp -r reports_csv/query/* "$RESULTS_CSV/" 2>/dev/null || true
    cp -r reports_csv/transfer/* "$RESULTS_CSV/" 2>/dev/null || true
    log_success "CSVs salvos em $RESULTS_CSV/"
fi

# ==========================================
# 15. SALVAR LOG DO EXPERIMENTO
# ==========================================

LOG_FILE="$RESULTS_HTML/experiment.log"

cat > "$LOG_FILE" <<EOF
Experimento: $EXP_NAME
Timestamp: $TIMESTAMP
Data: $(date)
=====================================
Parametros:
  Nos: $NODES
  Tempo de bloco: ${BLOCKTIME}s
  Consenso: $CONSENSUS
  Versao Besu: $VERSION

Configuracao:
  Genesis: $GENESIS_TEMPLATE
  Besu dir: $BESU_DIR

Resultados:
  HTML: $RESULTS_HTML/
  CSV: $RESULTS_CSV/

Status: CONCLUIDO
EOF

log_success "Log do experimento salvo: $LOG_FILE"

# ==========================================
# 16. FINALIZAR
# ==========================================

log_success "=========================================="
log_success "Experimento $EXP_NAME concluido!"
log_success "=========================================="
log_info "Resultados em:"
log_info "  HTML: $RESULTS_HTML/"
log_info "  CSV: $RESULTS_CSV/"
log_success "=========================================="

# Parar rede para liberar recursos
log_info "Parando rede para proximo experimento..."
cd "$BASE_DIR"
docker-compose down > /dev/null 2>&1

log_success "Rede parada. Pronto para proximo experimento."
