#!/bin/bash

# Script de Validação de Configuração da Rede Besu QBFT
# Valida consistência entre permissions_config.toml e docker-compose.yaml

set -e

echo "========================================="
echo "🔍 VALIDAÇÃO DE CONFIGURAÇÃO BESU QBFT"
echo "========================================="
echo ""

# Cores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

errors=0
warnings=0

# Função de validação
check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((errors++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((warnings++))
}

echo "📋 1. Verificando estrutura de diretórios..."
echo "-------------------------------------------"

for i in {1..6}; do
    node_dir="Permissioned-Network/Node-$i/data"
    if [ -d "$node_dir" ]; then
        if [ -f "$node_dir/key" ] && [ -f "$node_dir/key.pub" ] && [ -f "$node_dir/permissions_config.toml" ]; then
            check_pass "Node-$i: Estrutura completa"
        else
            check_fail "Node-$i: Arquivos faltando em $node_dir"
        fi
    else
        check_fail "Node-$i: Diretório $node_dir não encontrado"
    fi
done

echo ""
echo "🔑 2. Extraindo chaves públicas dos nós..."
echo "-------------------------------------------"

declare -A node_pubkeys
for i in {1..6}; do
    pubkey_file="Permissioned-Network/Node-$i/data/key.pub"
    if [ -f "$pubkey_file" ]; then
        pubkey=$(cat "$pubkey_file" | sed 's/^0x//')
        node_pubkeys[$i]=$pubkey
        echo "Node-$i: ${pubkey:0:16}...${pubkey: -16}"
    else
        check_fail "Node-$i: Chave pública não encontrada"
    fi
done

echo ""
echo "🔐 3. Validando permissions_config.toml dos nós..."
echo "-------------------------------------------"

# Ler o primeiro arquivo como referência
reference_file="Permissioned-Network/Node-1/data/permissions_config.toml"
if [ ! -f "$reference_file" ]; then
    check_fail "Arquivo de referência não encontrado: $reference_file"
    exit 1
fi

reference_hash=$(md5sum "$reference_file" | cut -d' ' -f1)

for i in {2..6}; do
    perm_file="Permissioned-Network/Node-$i/data/permissions_config.toml"
    if [ -f "$perm_file" ]; then
        current_hash=$(md5sum "$perm_file" | cut -d' ' -f1)
        if [ "$current_hash" == "$reference_hash" ]; then
            check_pass "Node-$i: permissions_config.toml idêntico ao Node-1"
        else
            check_fail "Node-$i: permissions_config.toml DIFERENTE do Node-1"
        fi
    else
        check_fail "Node-$i: permissions_config.toml não encontrado"
    fi
done

echo ""
echo "🌐 4. Validando enodes em permissions_config.toml..."
echo "-------------------------------------------"

# Extrair enodes do arquivo de permissões
perm_enodes=$(grep -oP 'enode://[^"]+' "$reference_file" | sort)
expected_count=6

actual_count=$(echo "$perm_enodes" | wc -l)
if [ "$actual_count" -eq "$expected_count" ]; then
    check_pass "Quantidade de enodes: $actual_count (esperado: $expected_count)"
else
    check_fail "Quantidade de enodes: $actual_count (esperado: $expected_count)"
fi

# Validar que as chaves públicas nos enodes correspondem aos arquivos key.pub
echo ""
echo "Validando correspondência de chaves públicas..."
while IFS= read -r enode; do
    pubkey=$(echo "$enode" | sed 's/enode:\/\/\([^@]*\).*/\1/')
    host=$(echo "$enode" | sed 's/.*@\([^:]*\):.*/\1/')
    port=$(echo "$enode" | sed 's/.*:\([0-9]*\)$/\1/')

    # Verificar se é 127.0.0.1
    if [ "$host" == "127.0.0.1" ]; then
        check_pass "Enode usa 127.0.0.1 (porta $port)"
    else
        check_fail "Enode usa $host em vez de 127.0.0.1 (porta $port)"
    fi

    # Verificar se a chave pública existe nos arquivos
    found=false
    for i in {1..6}; do
        if [ "${node_pubkeys[$i]}" == "$pubkey" ]; then
            found=true
            expected_port=$((30302 + i))
            if [ "$port" -eq "$expected_port" ]; then
                check_pass "Chave Node-$i encontrada com porta correta ($port)"
            else
                check_warn "Chave Node-$i encontrada mas porta incorreta (esperado: $expected_port, atual: $port)"
            fi
            break
        fi
    done

    if [ "$found" == false ]; then
        check_fail "Chave pública $pubkey não encontrada nos arquivos key.pub"
    fi
done <<< "$perm_enodes"

echo ""
echo "🐳 5. Validando bootnodes em docker-compose.yaml..."
echo "-------------------------------------------"

if [ ! -f "docker-compose.yaml" ]; then
    check_fail "docker-compose.yaml não encontrado"
else
    # Extrair bootnodes do docker-compose
    compose_bootnodes=$(grep -oP 'bootnodes=enode://[^"]+' docker-compose.yaml | sed 's/bootnodes=//' | head -1)

    if [ -z "$compose_bootnodes" ]; then
        check_warn "Nenhum bootnode encontrado em docker-compose.yaml"
    else
        # Verificar bootnode 1 (Node-1, porta 30303)
        bootnode1="enode://${node_pubkeys[1]}@127.0.0.1:30303"
        if echo "$compose_bootnodes" | grep -q "${node_pubkeys[1]}@127.0.0.1:30303"; then
            check_pass "Bootnode Node-1 correto no docker-compose.yaml"
        else
            check_fail "Bootnode Node-1 INCORRETO no docker-compose.yaml"
            echo "    Esperado: $bootnode1"
        fi

        # Verificar bootnode 3 (Node-3, porta 30305)
        bootnode3="enode://${node_pubkeys[3]}@127.0.0.1:30305"
        if echo "$compose_bootnodes" | grep -q "${node_pubkeys[3]}@127.0.0.1:30305"; then
            check_pass "Bootnode Node-3 correto no docker-compose.yaml"
        else
            check_fail "Bootnode Node-3 INCORRETO no docker-compose.yaml"
            echo "    Esperado: $bootnode3"
        fi
    fi
fi

echo ""
echo "📊 6. Validando accounts-allowlist..."
echo "-------------------------------------------"

accounts=$(grep -oP 'accounts-allowlist=\[\K[^\]]+' "$reference_file" | tr -d '"' | tr ',' '\n' | sort)
account_count=$(echo "$accounts" | wc -l)

if [ "$account_count" -eq 6 ]; then
    check_pass "Quantidade de accounts: $account_count (esperado: 6)"
else
    check_fail "Quantidade de accounts: $account_count (esperado: 6)"
fi

# Verificar formato dos endereços
echo "$accounts" | while read -r account; do
    if [[ $account =~ ^0x[0-9a-fA-F]{40}$ ]]; then
        check_pass "Account válido: $account"
    else
        check_fail "Account inválido: $account"
    fi
done

echo ""
echo "🔧 7. Validando configuração de rede Docker..."
echo "-------------------------------------------"

# Verificar network_mode
network_mode_count=$(grep -c 'network_mode: "host"' docker-compose.yaml)
if [ "$network_mode_count" -eq 6 ]; then
    check_pass "Todos os 6 nós usam network_mode: host"
else
    check_warn "Network mode host encontrado em $network_mode_count nós (esperado: 6)"
fi

# Verificar portas únicas
echo ""
echo "Verificando portas HTTP RPC..."
for port in 8545 8546 8547 8548 8549 8550; do
    if grep -q "rpc-http-port=$port" docker-compose.yaml; then
        check_pass "Porta HTTP RPC $port configurada"
    else
        check_warn "Porta HTTP RPC $port não encontrada"
    fi
done

echo ""
echo "========================================="
echo "📈 RESUMO DA VALIDAÇÃO"
echo "========================================="
echo ""

if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
    echo -e "${GREEN}✓ CONFIGURAÇÃO VÁLIDA!${NC}"
    echo "  Todos os testes passaram com sucesso."
    exit 0
elif [ $errors -eq 0 ]; then
    echo -e "${YELLOW}⚠ CONFIGURAÇÃO VÁLIDA COM AVISOS${NC}"
    echo "  Erros: $errors"
    echo "  Avisos: $warnings"
    exit 0
else
    echo -e "${RED}✗ CONFIGURAÇÃO INVÁLIDA!${NC}"
    echo "  Erros: $errors"
    echo "  Avisos: $warnings"
    echo ""
    echo "Por favor, corrija os erros antes de iniciar a rede."
    exit 1
fi
