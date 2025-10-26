#!/bin/bash

echo "========================================"
echo "Gerando Configuração dos Nós"
echo "========================================"

# Criar diretório principal
mkdir -p Permissioned-Network

# Copiar genesis.json
cp genesis.json Permissioned-Network/

# Obter lista de endereços (nomes das pastas em networkFiles/keys)
nodes=($(ls networkFiles/keys/ | grep "^0x"))

if [ ${#nodes[@]} -ne 6 ]; then
  echo "❌ Erro: Esperado 6 nós, encontrado ${#nodes[@]}"
  exit 1
fi

echo ""
echo "📋 Nós encontrados:"
for i in "${!nodes[@]}"; do
  echo "  Node-$((i+1)): ${nodes[$i]}"
done

echo ""
echo "🔑 Extraindo chaves públicas..."

# Array para armazenar enodes
declare -a enodes
declare -a accounts

# Extrair chaves públicas e criar enodes
for i in "${!nodes[@]}"; do
  node_num=$((i+1))
  address="${nodes[$i]}"
  pub_key=$(cat "networkFiles/keys/$address/key.pub" | sed 's/^0x//')
  
  # Portas P2P: 30303, 30304, ..., 30308
  p2p_port=$((30302 + node_num))
  
  # Criar enode (usando nomes de containers para bridge network)
  enode="enode://${pub_key}@node${node_num}:${p2p_port}"
  enodes+=("\"$enode\"")
  accounts+=("\"$address\"")
  
  echo "  ✓ Node-${node_num}: ${pub_key:0:16}...@node${node_num}:${p2p_port}"
done

echo ""
echo "📝 Criando permissions_config.toml..."

# Criar arquivo permissions_config.toml
cat > permissions_config.toml << PERM_EOF
nodes-allowlist=[$(IFS=,; echo "${enodes[*]}")]

accounts-allowlist=[$(IFS=,; echo "${accounts[*]}")]
PERM_EOF

echo "✓ Arquivo permissions_config.toml criado"

echo ""
echo "📂 Criando estrutura de diretórios..."

# Criar estrutura para cada nó
for i in "${!nodes[@]}"; do
  node_num=$((i+1))
  address="${nodes[$i]}"
  node_dir="Permissioned-Network/Node-${node_num}"
  
  echo "  Criando Node-${node_num}..."
  
  mkdir -p "$node_dir/data"
  
  # Copiar chaves
  cp "networkFiles/keys/$address/key" "$node_dir/data/"
  cp "networkFiles/keys/$address/key.pub" "$node_dir/data/"
  
  # Copiar permissions
  cp "permissions_config.toml" "$node_dir/data/"
  
  echo "    ✓ Chaves copiadas"
  echo "    ✓ Permissões configuradas"
done

echo ""
echo "✅ Configuração concluída!"
echo ""
echo "Estrutura criada:"
tree -L 3 Permissioned-Network/ 2>/dev/null || find Permissioned-Network/ -maxdepth 3

echo ""
echo "========================================"
