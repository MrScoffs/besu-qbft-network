# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Hyperledger Besu permissioned blockchain network configured with the QBFT (Quorum Byzantine Fault Tolerance) consensus protocol for production environments. The network consists of 6 validator nodes running in Docker containers with local permissioning.

**Key characteristics:**
- Chain ID: 381660001
- Consensus: QBFT with 5-second block periods
- Storage: Bonsai format (optimized for disk usage)
- Network mode: Host networking (all nodes on localhost with different ports)
- Permissioning: Local file-based (nodes-allowlist and accounts-allowlist)

## Common Commands

### Initial Setup

Generate blockchain configuration and node keys (run once):
```bash
besu operator generate-blockchain-config \
  --config-file=genesis_QBFT.json \
  --to=networkFiles \
  --private-key-file-name=key
```

Copy generated genesis file:
```bash
cp networkFiles/genesis.json ./
```

Generate node directory structure and permissions configuration:
```bash
chmod +x generate-nodes-config.sh
./generate-nodes-config.sh
```

### Docker Operations

Build the custom Besu Docker image:
```bash
docker build --no-cache -f Dockerfile -t besu-image-local:2.0 .
```

Start the network:
```bash
docker-compose up -d
```

Stop the network:
```bash
docker-compose down
```

View logs for a specific node:
```bash
docker logs -f node1  # Replace with node1-node6
```

### Management Scripts

Validate network configuration (checks consistency of all config files):
```bash
./validate-config.sh
```

Intelligent network restart (stops, validates, restarts, and monitors):
```bash
./restart-network.sh
```

Real-time network monitoring dashboard:
```bash
./monitor-network.sh
```

Quick connectivity test:
```bash
./test-connectivity.sh
```

### Network Validation

Test node RPC connectivity:
```bash
curl -X POST --data '{"jsonrpc":"2.0","method":"net_listening","params":[],"id":53}' http://127.0.0.1:8545 | jq
```

Get node information:
```bash
curl -X POST --data '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' http://127.0.0.1:8545 | jq
```

Check peer count:
```bash
curl -X POST --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' http://127.0.0.1:8545 | jq
```

View Prometheus metrics:
```bash
curl http://localhost:9545/metrics
```

Get debug metrics via RPC:
```bash
curl -X POST --data '{"jsonrpc":"2.0","method":"debug_metrics","params":[],"id":1}' http://127.0.0.1:8545 | jq
```

## Architecture

### Network Topology

The network runs 6 QBFT validator nodes, all on the same host using different ports:

| Node | HTTP RPC | WebSocket | P2P | Metrics |
|------|----------|-----------|-----|---------|
| node1 | 8545 | 8645 | 30303 | 9545 |
| node2 | 8546 | 8646 | 30304 | 9546 |
| node3 | 8547 | 8647 | 30305 | 9547 |
| node4 | 8548 | 8648 | 30306 | 9548 |
| node5 | 8549 | 8649 | 30307 | 9549 |
| node6 | 8550 | 8650 | 30308 | 9550 |

**Bootnode strategy:** Nodes 2, 4, 5, and 6 use nodes 1 and 3 as bootnodes for initial peer discovery.

### File Structure

```
Permissioned-Network/
├── genesis.json                    # Network genesis configuration
├── Node-1/
│   └── data/
│       ├── key                     # Node private key
│       ├── key.pub                 # Node public key
│       └── permissions_config.toml # Allowlist configuration
├── Node-2/ ... Node-6/             # Same structure for other nodes
```

**Important:** Each node has identical `permissions_config.toml` files containing the same allowlists for all 6 nodes and their associated accounts.

### Genesis Configuration

The `genesis.json` file contains:
- **QBFT settings:** 5-second block periods, 30000 block epochs, 10-second request timeouts
- **extraData:** Pre-sealed validator addresses (the 6 node account addresses)
- **Pre-funded accounts:** Three test accounts with balances (DO NOT use private keys in production)
- **Gas configuration:** Zero base fee enabled, unlimited gas limit

### Permissions System

Permissioning is enforced via `permissions_config.toml` in each node's data directory:
- **nodes-allowlist:** Enode URLs of all 6 validators (127.0.0.1 with respective P2P ports)
- **accounts-allowlist:** The 6 account addresses derived from node keys

Both lists must be synchronized across all nodes for proper network operation.

### Docker Configuration

**Dockerfile:** Based on Ubuntu 20.04, includes Java 21.0.9 and Besu 25.9.0. The binaries are copied into the image (not downloaded at build time).

**docker-compose.yaml:** Runs all 6 nodes with:
- Host networking mode (shared localhost networking)
- Enterprise profile enabled
- Full RPC/WebSocket APIs: WEB3, ETH, NET, TRACE, DEBUG, ADMIN, TXPOOL, PERM, QBFT
- Metrics and monitoring enabled
- Local file-based permissioning enabled

## Key Files

- `genesis_QBFT.json`: Template for generating the initial blockchain configuration (includes node count: 6)
- `genesis.json`: Finalized genesis file with extraData (validator addresses)
- `generate-nodes-config.sh`: Automates creation of node directories, copies keys, and generates permissions_config.toml
- `permissions_config.toml`: Central allowlist configuration (gets copied to each node)
- `docker-compose.yaml`: Orchestrates all 6 nodes with proper port mappings
- `Dockerfile`: Custom Besu image with bundled Java and Besu binaries

## Network Regeneration

To completely regenerate the network with new keys:

1. Remove old generated files:
   ```bash
   rm -rf networkFiles/ Permissioned-Network/ permissions_config.toml genesis.json
   ```

2. Regenerate blockchain config:
   ```bash
   besu operator generate-blockchain-config --config-file=genesis_QBFT.json --to=networkFiles --private-key-file-name=key
   ```

3. Copy new genesis:
   ```bash
   cp networkFiles/genesis.json ./
   ```

4. Generate node structure:
   ```bash
   ./generate-nodes-config.sh
   ```

5. Update docker-compose.yaml bootnodes if enode addresses changed

6. Rebuild and restart:
   ```bash
   docker-compose down
   docker build --no-cache -f Dockerfile -t besu-image-local:2.0 .
   docker-compose up -d
   ```

## Important Notes

- **Port conflicts:** All nodes use host networking. Ensure ports 8545-8550, 8645-8650, 9545-9550, and 30303-30308 are available.
- **Permissions synchronization:** When adding/removing nodes, update `permissions_config.toml` in ALL node data directories and restart affected nodes.
- **Genesis immutability:** Never modify genesis.json after network initialization. All nodes must have identical genesis files.
- **Validator set:** The 6 validators are hardcoded in genesis.json extraData. Changing validators requires network regeneration.
- **Security:** This configuration uses test private keys in genesis.json for pre-funded accounts. Remove these in production environments.
