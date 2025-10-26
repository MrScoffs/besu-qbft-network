#!/bin/bash

echo "=== TESTE DE CONECTIVIDADE DA REDE BESU ==="
echo ""

echo "Node | Porta | Listening | Peers | Bloco Atual"
echo "-----|-------|-----------|-------|-------------"

for i in {1..6}; do
    port=$((8544 + i))

    # Test listening
    listening=$(curl -s -X POST --max-time 2 --data '{"jsonrpc":"2.0","method":"net_listening","params":[],"id":1}' http://127.0.0.1:$port 2>/dev/null | jq -r '.result' 2>/dev/null || echo "N/A")

    # Test peer count
    peer_count_hex=$(curl -s -X POST --max-time 2 --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' http://127.0.0.1:$port 2>/dev/null | jq -r '.result' 2>/dev/null || echo "N/A")
    if [ "$peer_count_hex" != "N/A" ]; then
        peer_count=$((peer_count_hex))
    else
        peer_count="N/A"
    fi

    # Test block number
    block_hex=$(curl -s -X POST --max-time 2 --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://127.0.0.1:$port 2>/dev/null | jq -r '.result' 2>/dev/null || echo "N/A")
    if [ "$block_hex" != "N/A" ]; then
        block_num=$((block_hex))
    else
        block_num="N/A"
    fi

    printf "  %d  | %5d | %-9s | %5s | %s\n" "$i" "$port" "$listening" "$peer_count" "$block_num"
done

echo ""
echo "=== RESUMO ==="
running=$(docker ps -q --filter "name=node" | wc -l)
echo "Containers rodando: $running/6"
