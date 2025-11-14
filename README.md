# Hyperledger Besu - Permissioned QBFT Network for Production Networks

Este guia descreve a configuração de uma rede permissionada utilizando o mecanismo de consenso QBFT (QBFT Consensus Protocol) do Hyperledger Besu, ideal para ambientes de produção.


## Pré-requisitos
Certifique-se de ter as seguintes ferramentas instaladas:

- Java
- Besu v25.10.0
- curl, wget, tar
- Docker
- Docker-Compose

### Instalação das Dependências

#### Besu

> [!IMPORTANT]
> <sup>Estamos utilizando a versão 25.10.0 do Besu. Para utilizar outra versão, altere a URL de download e atualize as variáveis de ambiente conforme necessário.</sup>

``` 
wget https://github.com/hyperledger/besu/releases/download/25.10.0/besu-25.10.0.tar.gz
tar -xvf besu-25.10.0.tar.gz 
rm besu-25.10.0.tar.gz 
export PATH=$(pwd)/besu-25.10.0/bin:$PATH
```

#### JAVA

> [!IMPORTANT]
> <sup>Certifique-se de que o diretório `jdk-21.0.9/` foi extraído corretamente na raiz do projeto.</sup>

```
wget https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.tar.gz 
tar -xvf jdk-21_linux-x64_bin.tar.gz
rm jdk-21_linux-x64_bin.tar.gz
export JAVA_HOME=$(pwd)/jdk-21.0.9
```

> [!NOTE]
> <sup>Se atente a versão do jdk baixada para criar a variável de ambiente corretamente.</sup>

Verifique a versão da besu instalada:
```
besu --version
```
> [!NOTE]
> <sup>Este tutorial foi baseado na doc oficial da Besu [Hyperledger Besu Tutorial QBFT](https://besu.hyperledger.org/private-networks/tutorials/qbft) e [Hyperledger Besu Tutorial Permissioning](https://besu.hyperledger.org/private-networks/tutorials/permissioning)</sup>

## Etapa 1: Geração das Chaves Criptográficas e Arquivos de Configuração

### 1. Geração dos arquivos da blockchain e chaves privadas
> [!IMPORTANT]
> <sup>Estamos criando uma rede com 12 nós, o que pode ser um pouco grande. Para criar uma rede com um número menor de nós edite o arquivo genesis_QBFT.json diminuindo o valor de count, ou subindo apenas os nós necessários utilizando o docker</sup>

```
"blockchain": {
    "nodes": {
      "generate": true,
      "count": 12 // ---> Edite o números de nós da rede aqui
    }
}
```

```
besu operator generate-blockchain-config \
  --config-file=genesis_QBFT.json \
  --to=networkFiles \
  --private-key-file-name=key
```

### 2. Geração do arquivo permissions_config.toml
Certifique-se de que o script de geração está com permissão de execução:

```
chmod +x generate-nodes-config.sh
./generate-nodes-config.sh
```
Formato esperado do arquivo permissions_config.toml:

```
nodes-allowlist=[
  "enode://<public-key-1>@<ip-node-1>:30303",
  ...
  "enode://<public-key-2>@<ip-node-12>:30308"
]
accounts-allowlist=[
  "0x<account-id-node-1>",
  ...
  "0x<account-id-node-12>"
]
```
> [!NOTE]
> <sup>Os account-ids são os nomes das pastas geradas automaticamente em networkFiles/.</sup>

### 3. Copiar o arquivo genesis.json com extraData
```
cp networkFiles/genesis.json ./Permissioned-Network/
```

### 4. Verifique a estrutura de diretórios para os Nodes
Organize os arquivos conforme a estrutura:

```
Permissioned-Network/
├── genesis.json
├── Node-1/
│   └── data/
│       ├── key
│       ├── key.pub
│       └── permissions_config.toml
├── Node-2/
│   └── data/
│       ├── ...
├── ...
├── Node-6/
│   └── data/
```
> [!IMPORTANT]
> <sup>Certifique-se de verficar se os arquivos corretos foram copiados para cada um dos nós da rede (config.toml, key ...).</sup>

## Etapa 2: Execução da Rede

### 1. Construção da Imagem Docker
Crie a imagem Docker personalizada do Besu:

```
docker build --no-cache -f Dockerfile -t besu-image-local:25.10.0 .
```

### 2. Crie o arquivo docker-compose.yml
```
chmod +x generate-docker-compose.sh
./generate-docker-compose.sh
```

### Para Docker Desktop
### 3. Inicialização dos Nós
Suba os nós da rede:
```
docker-compose up -d
```

### 4. Finalização da Rede
Para derrubar todos os containers:

```
docker-compose down
```

### Para Docker CE
Suba os nós da rede:
```
docker compose up -d
```

Ver os logs
```
docker compose logs -f
```

Containers ativos:
```
docker ps
```

Containers ativos e parados:
```
docker ps -a
```

Ver as imagens
```
docker images
```

Apagar container
```
docker rm -f <container_id_ou_nome>
```

Apagar todos containers:
```
docker compose down -v
```
Limpar a blockchain (recomendado para benchmarks limpos):
  docker-compose down -v && docker-compose up -d

Apagar imagens:
```
docker rmi <image_id_ou_nome>
```

Informações:
```
docker system df
```
```
docker stats 
```

> [!NOTE]
> <sup>Para realizar deploy de contratos é necessário dar permissão para a conta que fizer a transação, para isso edite o arquivo add-account-permission.sh adicionando sua chave pública e rode o script</sup>
```
chmod +x add-account-permission.sh
./add-account-permission.sh
```

## Etapa 3: Testes de Conectividade e Estado da Rede 
Utilize os comandos abaixo para validar o estado da rede:

> [!NOTE]
> <sup>
```
# Métricas Prometheus
curl http://localhost:9545/metrics

# Métricas internas (via RPC)
curl -X POST --data '{"jsonrpc":"2.0","method":"debug_metrics","params":[],"id":1}' http://127.0.0.1:8545 | jq

# Informações do nó
curl -X POST --data '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' http://127.0.0.1:8545 | jq

# Escuta de rede
curl -X POST --data '{"jsonrpc":"2.0","method":"net_listening","params":[],"id":53}' http://127.0.0.1:8545 | jq

# Enode do nó
curl -X POST --data '{"jsonrpc":"2.0","method":"net_enode","params":[],"id":1}' http://127.0.0.1:8545 | jq

# Serviços de rede
curl -X POST --data '{"jsonrpc":"2.0","method":"net_services","params":[],"id":1}' http://127.0.0.1:8545 | jq

# Contagem de peers
curl -X POST --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' http://127.0.0.1:8545 | jq
```
</sup>

## Etapa 4: Experimentos Automatizados

Este projeto inclui um sistema de automacao para executar experimentos com diferentes configuracoes de rede e avaliar o desempenho.

### Parametros Variaveis

O sistema permite variar os seguintes parametros:
- **Numero de nos**: 4, 6, 8, 10
- **Tempo de bloco**: 2s, 5s, 10s
- **Algoritmo de consenso**: QBFT, IBFT2
- **Versao do Besu**: 24.7.0, 25.9.0, 25.10.0

### Estrutura de Scripts

```
scripts/
├── download-besu-versions.sh    # Baixa versoes adicionais do Besu
├── run-experiment.sh            # Executa um experimento individual
├── run-all-experiments.sh       # Executa todos os experimentos em lote
└── experiments-list.txt         # Lista de experimentos a executar
```

### Preparacao Inicial

1. Baixar versoes adicionais do Besu (se necessario):
```bash
cd scripts/
./download-besu-versions.sh
```

2. Verificar a lista de experimentos:
```bash
cat scripts/experiments-list.txt
```

Edite o arquivo para adicionar ou remover experimentos conforme necessario.

### Executar Experimentos

#### Experimento Individual

Execute um experimento especifico:

```bash
cd scripts/
./run-experiment.sh <nodes> <blocktime> <consensus> <version>

# Exemplo: 6 nos, 5s de bloco, QBFT, versao 25.10.0
./run-experiment.sh 6 5 qbft 25.10.0
```

O script run-experiment.sh realiza automaticamente:
1. Limpeza completa da rede anterior 
2. Geracao de novo genesis com parametros especificados
3. Configuracao e inicializacao dos nos
4. Aguardo de 90 segundos para estabilizacao da rede 
5. Implantacao automatica do contrato Simple
6. Atualizacao do networkconfig.json com endereco do novo contrato
7. Execucao dos benchmarks do Caliper
8. Geracao de relatorios HTML e CSV

#### Todos os Experimentos em Lote

Execute todos os experimentos da lista:

```bash
cd scripts/
./run-all-experiments.sh
```

O script ira:
1. Ler experiments-list.txt
2. Executar cada experimento sequencialmente
3. Limpar completamente a rede entre experimentos 
4. Salvar resultados em diretorios organizados

### Resultados

Os resultados sao salvos em diretorios com timestamp para evitar sobrescrita:

```
../Hyperleadger-Caliper/reports_htmls/experiments/<exp_name>_<timestamp>/
../Hyperleadger-Caliper/reports_csv/experiments/<exp_name>_<timestamp>/
```

Formato do nome do experimento: `<nodes>n-<blocktime>s-<consensus>-v<version>_<timestamp>`

Exemplos:
- `6n-5s-qbft-v25.10.0_20251112_133845`
- `4n-2s-ibft-v24.7.0_20251112_140530`

O timestamp segue o formato: YYYYMMDD_HHMMSS

#### Vantagens do Sistema de Timestamp

- Cada execucao cria um diretorio unico
- Nao ha sobrescrita de resultados anteriores
- Historico completo preservado para comparacao e auditoria
- Possibilita executar o mesmo experimento multiplas vezes

### Analise de Resultados

Apos executar os experimentos, analise os resultados consolidados:

```bash
cd ../Hyperleadger-Caliper
python3 analyze-all-experiments.py
```

Este script ira:
1. Consolidar resultados de todos os experimentos (incluindo diferentes timestamps)
2. Gerar tabela comparativa
3. Identificar a melhor configuracao (por throughput)
4. Salvar relatorios com timestamp e versao "latest":
   - `reports_csv/experiments/CONSOLIDATED_RESULTS_<timestamp>.csv`
   - `reports_csv/experiments/CONSOLIDATED_RESULTS.csv` (latest)
   - `reports_csv/experiments/ANALYSIS_REPORT_<timestamp>.txt`
   - `reports_csv/experiments/ANALYSIS_REPORT.txt` (latest)

Os arquivos "latest" sao sempre atualizados com a analise mais recente, enquanto as versoes com timestamp mantem o historico completo.

### Metricas Analisadas

- **Throughput (TPS)**: Transacoes por segundo
- **Latencia**: Tempo medio de processamento
- **Taxa de Sucesso**: Porcentagem de transacoes bem-sucedidas
- **CPU**: Uso medio de CPU
- **Memoria**: Uso medio de memoria

### Observacoes Importantes

- O sistema realiza limpeza completa entre experimentos (containers, volumes, chaves)
- Cada experimento leva aproximadamente 5-10 minutos
- Os resultados sao determinados principalmente pelo throughput
- Recomenda-se executar em ambiente dedicado para resultados consistentes
- O contrato Simple e reimplantado automaticamente em cada experimento, resolvendo o problema de contratos ausentes apos reset do genesis
- O tempo de estabilizacao de 60 segundos reduz o vies relacionado ao poder computacional

### Gerenciamento de Historico

Com o tempo, o historico de experimentos pode ocupar espaco significativo. Para gerenciar:

#### Verificar espaco utilizado
```bash
du -sh ../Hyperleadger-Caliper/reports_csv/experiments/
du -sh ../Hyperleadger-Caliper/reports_htmls/experiments/
```

#### Limpar experimentos antigos (opcional)
```bash
# Remover experimentos com mais de 30 dias
find ../Hyperleadger-Caliper/reports_csv/experiments/ \
  -type d -mtime +30 -regex '.*_[0-9]{8}_[0-9]{6}$' -exec rm -rf {} +

find ../Hyperleadger-Caliper/reports_htmls/experiments/ \
  -type d -mtime +30 -regex '.*_[0-9]{8}_[0-9]{6}$' -exec rm -rf {} +
```

#### Limpar analises consolidadas antigas (manter ultimas 10)
```bash
cd ../Hyperleadger-Caliper/reports_csv/experiments/
ls -t CONSOLIDATED_RESULTS_*.csv | tail -n +11 | xargs rm -f
ls -t ANALYSIS_REPORT_*.txt | tail -n +11 | xargs rm -f
```

#### Listar experimentos por data
```bash
ls -lht ../Hyperleadger-Caliper/reports_csv/experiments/ | grep "_2025"
```

