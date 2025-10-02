# Hyperledger Besu - Permissioned QBFT Network for Production Networks

Este guia descreve a configuração de uma rede permissionada utilizando o mecanismo de consenso QBFT (QBFT Consensus Protocol) do Hyperledger Besu, ideal para ambientes de produção.

## Pré-requisitos
Certifique-se de ter as seguintes ferramentas instaladas:

- Java 21 (ou superior)
- Besu v24.7.0
- cURL, wget, tar
- Docker
- Docker-Compose

## Instalação Completa (Passo a Passo)

### 1. Preparação do Ambiente

#### 1.1 Atualizar o sistema (Ubuntu/WSL)
```bash
sudo apt update && sudo apt upgrade -y
```

#### 1.2 Instalar Docker e Docker Compose
```bash
# Instalar Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Adicionar seu usuário ao grupo docker
sudo usermod -aG docker $USER

# Instalar Docker Compose
sudo apt install docker-compose -y

# Iniciar o serviço Docker
sudo service docker start

# Aplicar as permissões (logout/login ou execute o comando abaixo)
newgrp docker
```

#### 1.3 Criar rede Docker
```bash
docker network create besu-network
```

### 2. Clonar o Repositório
```bash
cd ~
git clone -b develop https://github.com/jeffsonsousa/besu-production-docker.git
cd besu-production-docker
```

### 3. Instalar Java e Besu

#### 3.1 Baixar e extrair Java 21
```bash
wget https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.tar.gz
tar -xvf jdk-21_linux-x64_bin.tar.gz
rm jdk-21_linux-x64_bin.tar.gz
```

#### 3.2 Baixar e extrair Besu 24.7.0
```bash
wget https://github.com/hyperledger/besu/releases/download/24.7.0/besu-24.7.0.tar.gz
tar -xvf besu-24.7.0.tar.gz
rm besu-24.7.0.tar.gz
```

#### 3.3 Configurar variáveis de ambiente

**Para Bash:**
```bash
nano ~/.bashrc
```

**Para Zsh:**
```bash
nano ~/.zshrc
```

Adicione no final do arquivo:
```bash
# Besu Production Environment
export JAVA_HOME=~/besu-production-docker/jdk-21.0.X  # Substitua X pela versão baixada
export PATH="$JAVA_HOME/bin:$PATH"
export PATH="~/besu-production-docker/besu-24.7.0/bin:$PATH"
```

Salve (Ctrl+O, Enter, Ctrl+X) e recarregue:
```bash
source ~/.bashrc  # ou source ~/.zshrc
```

#### 3.4 Verificar instalação
```bash
java -version
besu --version
```

### 4. Corrigir o Dockerfile

O Dockerfile precisa apontar para a versão correta do JDK que você baixou:

```bash
# Verificar qual versão do JDK foi baixada
ls -la | grep jdk

# Atualizar o Dockerfile
nano Dockerfile
```

Localize a linha `COPY jdk-21.0.6 /opt/jdk` e altere para a versão correta (ex: `COPY jdk-21.0.8 /opt/jdk`).

Ou use o comando automatizado:
```bash
# Substitua 21.0.X pela versão que você baixou
JDK_VERSION=$(ls -d jdk-* | head -n1)
sed -i "s/jdk-21.0.6/$JDK_VERSION/g" Dockerfile
```

### 5. Gerar Configuração da Blockchain

#### 5.1 Gerar chaves e arquivos de configuração
```bash
besu operator generate-blockchain-config \
  --config-file=genesis_QBFT.json \
  --to=networkFiles \
  --private-key-file-name=key
```

#### 5.2 Copiar o genesis.json
```bash
cp networkFiles/genesis.json ./
```

#### 5.3 Extrair as chaves públicas dos nós
```bash
cat > extract-enodes.sh << 'EOF'
#!/bin/bash

echo "Extraindo chaves públicas dos nós..."
echo ""

for dir in networkFiles/keys/0x*/; do
  address=$(basename "$dir")
  pub_key=$(cat "${dir}key.pub")
  echo "$address: $pub_key"
done
EOF

chmod +x extract-enodes.sh
./extract-enodes.sh > node-keys.txt
cat node-keys.txt
```

### 6. Criar Arquivo de Permissões

**IMPORTANTE:** Substitua as chaves públicas abaixo pelas que foram geradas no passo anterior.

```bash
cat > permissions_config.toml << 'EOF'
nodes-allowlist=[
  "enode://CHAVE_PUBLICA_NODE1@127.0.0.1:30303",
  "enode://CHAVE_PUBLICA_NODE2@127.0.0.1:30304",
  "enode://CHAVE_PUBLICA_NODE3@127.0.0.1:30305",
  "enode://CHAVE_PUBLICA_NODE4@127.0.0.1:30306",
  "enode://CHAVE_PUBLICA_NODE5@127.0.0.1:30307",
  "enode://CHAVE_PUBLICA_NODE6@127.0.0.1:30308"
]

accounts-allowlist=[
  "0xENDERECO_NODE1",
  "0xENDERECO_NODE2",
  "0xENDERECO_NODE3",
  "0xENDERECO_NODE4",
  "0xENDERECO_NODE5",
  "0xENDERECO_NODE6"
]
EOF
```

### 7. Atualizar Bootnodes no docker-compose.yaml

Os bootnodes no `docker-compose.yaml` precisam ser atualizados com as chaves públicas corretas do Node-1 e Node-3:

```bash
nano docker-compose.yaml
```

Localize todas as linhas `--bootnodes=` e substitua pelos enodes corretos:

```
--bootnodes=enode://CHAVE_PUBLICA_NODE1@127.0.0.1:30303,enode://CHAVE_PUBLICA_NODE3@127.0.0.1:30305
```

Ou use o comando automatizado (após criar o permissions_config.toml corretamente):
```bash
# Extrair as chaves públicas do Node-1 e Node-3
NODE1_PUBKEY=$(grep "30303" permissions_config.toml | sed 's/.*enode:\/\/\([^@]*\).*/\1/')
NODE3_PUBKEY=$(grep "30305" permissions_config.toml | sed 's/.*enode:\/\/\([^@]*\).*/\1/')

# Substituir no docker-compose.yaml
sed -i "s|--bootnodes=enode://[^@]*@[^,]*:30303,enode://[^@]*@[^,]*:30305|--bootnodes=enode://${NODE1_PUBKEY}@127.0.0.1:30303,enode://${NODE3_PUBKEY}@127.0.0.1:30305|g" docker-compose.yaml
```

### 8. Criar Estrutura de Diretórios

```bash
# Criar diretório principal
mkdir -p Permissioned-Network

# Obter lista de endereços dos nós
nodes=($(ls networkFiles/keys/ | grep "^0x"))

# Criar estrutura para cada nó
for i in {1..6}; do
  NODE_DIR="Permissioned-Network/Node-$i"
  NODE_ADDRESS="${nodes[$i-1]}"
  
  echo "Criando $NODE_DIR para endereço $NODE_ADDRESS..."
  
  mkdir -p "$NODE_DIR/data"
  
  # Copiar chaves
  cp "networkFiles/keys/$NODE_ADDRESS/key" "$NODE_DIR/data/"
  cp "networkFiles/keys/$NODE_ADDRESS/key.pub" "$NODE_DIR/data/"
  
  # Copiar permissions_config.toml
  cp "permissions_config.toml" "$NODE_DIR/data/"
  
  echo "✓ $NODE_DIR criado com sucesso!"
done
```

Verifique a estrutura:
```bash
ls -la Permissioned-Network/
ls -la Permissioned-Network/Node-1/data/
```

A estrutura esperada é:
```
Permissioned-Network/
├── Node-1/
│   └── data/
│       ├── key
│       ├── key.pub
│       └── permissions_config.toml
├── Node-2/
│   └── data/
│       └── ...
├── ...
└── Node-6/
    └── data/
```

### 9. Construir a Imagem Docker

```bash
# Construir a imagem
docker build --no-cache -f Dockerfile -t besu-image-local:1.0 .

# Criar tag adicional (necessária para o node1)
docker tag besu-image-local:1.0 besu-image-local:2.0

# Verificar imagens criadas
docker images | grep besu
```

### 10. Iniciar a Rede

```bash
# Iniciar todos os nós
docker-compose up -d

# Verificar status dos containers
docker-compose ps
```

Todos os 6 nós devem estar com status **Up**.

### 11. Validar a Rede

#### 11.1 Verificar conectividade
```bash
# Aguardar alguns segundos para os nós se conectarem
sleep 15

# Verificar se está escutando
curl -X POST --data '{"jsonrpc":"2.0","method":"net_listening","params":[],"id":53}' http://127.0.0.1:8545 | jq

# Verificar número de peers (deve retornar 5)
curl -X POST --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' http://127.0.0.1:8545 | jq
```

#### 11.2 Verificar portas abertas
```bash
sudo netstat -tulpn | grep -E ':(30303|30304|30305|30306|30307|30308)'
```

Devem aparecer todas as 6 portas P2P (30303-30308).

#### 11.3 Verificar logs
```bash
# Ver logs do node1
docker-compose logs --tail=50 node1

# Ver logs de todos os nós
docker-compose logs -f
```

Procure por mensagens como:
- `Peers: 5`
- `Imported #X`
- `Produced #X`

## Testes de Conectividade e Estado da Rede

```bash
# Informações do nó
curl -X POST --data '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' http://127.0.0.1:8545 | jq

# Enode do nó
curl -X POST --data '{"jsonrpc":"2.0","method":"net_enode","params":[],"id":1}' http://127.0.0.1:8545 | jq

# Lista de peers conectados
curl -X POST --data '{"jsonrpc":"2.0","method":"admin_peers","params":[],"id":1}' http://127.0.0.1:8545 | jq

# Número do último bloco
curl -X POST --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:8545 | jq

# Informações do último bloco
curl -X POST --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' http://127.0.0.1:8545 | jq

# Métricas Prometheus
curl http://localhost:9545/metrics
```

## Gerenciamento da Rede

```bash
# Parar a rede
docker-compose down

# Iniciar a rede
docker-compose up -d

# Reiniciar a rede
docker-compose restart

# Ver logs em tempo real
docker-compose logs -f

# Ver logs de um nó específico
docker-compose logs -f node1

# Ver status dos containers
docker-compose ps

# Remover tudo (incluindo volumes)
docker-compose down -v
```

## Portas dos Nós

| Nó | RPC HTTP | RPC WebSocket | P2P | Métricas |
|----|----------|---------------|-----|----------|
| Node-1 | 8545 | 8645 | 30303 | 9545 |
| Node-2 | 8546 | 8646 | 30304 | 9546 |
| Node-3 | 8547 | 8647 | 30305 | 9547 |
| Node-4 | 8548 | 8648 | 30306 | 9548 |
| Node-5 | 8549 | 8649 | 30307 | 9549 |
| Node-6 | 8550 | 8650 | 30308 | 9550 |

## Troubleshooting

### Problema: Containers com status "Exit 2"
**Causa:** Bootnodes não estão na lista de permissões ou IPs incorretos no `permissions_config.toml`

**Solução:** 
1. Verificar se os bootnodes no `docker-compose.yaml` correspondem às chaves públicas corretas
2. Garantir que o `permissions_config.toml` use `127.0.0.1` em todos os enodes
3. Recriar o arquivo de permissões e copiá-lo para todos os nós

### Problema: net_peerCount retorna 0
**Causa:** Nós não estão conseguindo se descobrir

**Solução:**
1. Verificar se todas as portas P2P estão abertas: `sudo netstat -tulpn | grep 3030`
2. Verificar logs dos nós: `docker-compose logs node2`
3. Garantir que o `permissions_config.toml` está correto em todos os nós

### Problema: Dockerfile falha ao copiar JDK
**Causa:** Versão do JDK no Dockerfile não corresponde à versão baixada

**Solução:**
1. Verificar versão instalada: `ls -la | grep jdk`
2. Atualizar linha `COPY jdk-X.X.X /opt/jdk` no Dockerfile

### Problema: Containers não aparecem no Docker Desktop
**Causa:** Uso de `network_mode: host` tem limitações no WSL

**Solução:** Isso não afeta o funcionamento. Use CLI para gerenciar: `docker ps` e `docker-compose ps`

## Notas Importantes

- A rede utiliza `network_mode: host`, o que significa que todos os containers compartilham a pilha de rede do host
- Todos os nós precisam ter o mesmo arquivo `permissions_config.toml`
- Os bootnodes (Node-1 e Node-3) devem iniciar primeiro para os outros nós se conectarem
- A blockchain produz blocos a cada 5 segundos com o consenso QBFT
- Cada nó deve ver exatamente 5 peers conectados (os outros 5 nós da rede)

## Referências

- [Hyperledger Besu Documentation](https://besu.hyperledger.org/)
- [QBFT Consensus Tutorial](https://besu.hyperledger.org/private-networks/tutorials/qbft)
- [Permissioning Tutorial](https://besu.hyperledger.org/private-networks/tutorials/permissioning)