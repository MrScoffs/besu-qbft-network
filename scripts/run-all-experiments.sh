#!/bin/bash
set -e

# ==========================================
# Script para executar todos os experimentos
# Le experiments-list.txt e executa cada um
# ==========================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

log_section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Diretórios
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXPERIMENTS_FILE="$SCRIPT_DIR/experiments-list.txt"
RUN_EXPERIMENT="$SCRIPT_DIR/run-experiment.sh"

# Verificar arquivos
if [ ! -f "$EXPERIMENTS_FILE" ]; then
    log_error "Arquivo experiments-list.txt nao encontrado: $EXPERIMENTS_FILE"
    exit 1
fi

if [ ! -x "$RUN_EXPERIMENT" ]; then
    log_error "Script run-experiment.sh nao encontrado ou nao executavel: $RUN_EXPERIMENT"
    exit 1
fi

# ==========================================
# LER EXPERIMENTOS
# ==========================================

log_section "EXECUCAO EM LOTE DE EXPERIMENTOS"

# Contar experimentos (ignorar linhas vazias e comentarios)
TOTAL=$(grep -v "^#" "$EXPERIMENTS_FILE" | grep -v "^$" | wc -l)

log_info "Total de experimentos a executar: $TOTAL"
log_info "Arquivo: $EXPERIMENTS_FILE"
log_info ""

# Confirmar execução
read -p "Deseja continuar? (s/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    log_warning "Execucao cancelada pelo usuario"
    exit 0
fi

# ==========================================
# EXECUTAR EXPERIMENTOS
# ==========================================

CURRENT=0
SUCCESS=0
FAILED=0
START_TIME=$(date +%s)

log_section "INICIANDO EXPERIMENTOS"

while IFS= read -r line; do
    # Ignorar comentários e linhas vazias
    if [[ "$line" =~ ^#.*$ ]] || [[ -z "$line" ]]; then
        continue
    fi

    CURRENT=$((CURRENT + 1))

    # Parsear linha
    read -r NODES BLOCKTIME CONSENSUS VERSION <<< "$line"

    EXP_NAME="${NODES}n-${BLOCKTIME}s-${CONSENSUS}-v${VERSION}"

    log_section "EXPERIMENTO $CURRENT/$TOTAL: $EXP_NAME"
    log_info "Parametros: nodes=$NODES blocktime=${BLOCKTIME}s consensus=$CONSENSUS version=$VERSION"

    # Executar experimento
    if "$RUN_EXPERIMENT" "$NODES" "$BLOCKTIME" "$CONSENSUS" "$VERSION"; then
        SUCCESS=$((SUCCESS + 1))
        log_success "Experimento $EXP_NAME concluido com sucesso"
    else
        FAILED=$((FAILED + 1))
        log_error "Experimento $EXP_NAME FALHOU"
        log_warning "Continuando para proximo experimento..."
    fi

    # Aguardar entre experimentos
    if [ $CURRENT -lt $TOTAL ]; then
        log_info "Aguardando 10 segundos antes do proximo experimento..."
        sleep 10
    fi

done < "$EXPERIMENTS_FILE"

# ==========================================
# RELATORIO FINAL
# ==========================================

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$((DURATION / 60))
DURATION_SEC=$((DURATION % 60))

log_section "RELATORIO FINAL"
log_info "Total de experimentos: $TOTAL"
log_success "Sucesso: $SUCCESS"

if [ $FAILED -gt 0 ]; then
    log_error "Falhas: $FAILED"
fi

log_info "Tempo total: ${DURATION_MIN}m ${DURATION_SEC}s"
log_section "FIM DA EXECUCAO EM LOTE"

# Sugerir analise
log_info ""
log_info "Proximos passos:"
log_info "  1. Analisar resultados: cd ../Hyperleadger-Caliper && python3 analyze-all-experiments.py"
log_info "  2. Verificar logs individuais em: reports_htmls/experiments/<exp_name>/experiment.log"
log_info ""

if [ $FAILED -eq 0 ]; then
    log_success "Todos os experimentos foram concluidos com sucesso!"
    exit 0
else
    log_warning "Alguns experimentos falharam. Verifique os logs."
    exit 1
fi
