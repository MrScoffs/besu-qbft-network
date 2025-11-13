#!/bin/bash
set -e

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

echo "=========================================="
echo "Download de versoes Besu para experimentos"
echo "=========================================="

VERSIONS=("24.7.0" "25.9.0")

for VERSION in "${VERSIONS[@]}"; do
    TARGET_DIR="besu-${VERSION}"

    if [ -d "$TARGET_DIR" ]; then
        echo "[OK] besu-${VERSION} ja existe. Pulando..."
        continue
    fi

    echo ""
    echo "Baixando Besu ${VERSION}..."
    DOWNLOAD_URL="https://github.com/hyperledger/besu/releases/download/${VERSION}/besu-${VERSION}.tar.gz"

    wget --show-progress "$DOWNLOAD_URL" -O "besu-${VERSION}.tar.gz"

    echo "Descompactando besu-${VERSION}.tar.gz..."
    tar -xzf "besu-${VERSION}.tar.gz"

    echo "Removendo arquivo tar.gz..."
    rm "besu-${VERSION}.tar.gz"

    echo "[OK] besu-${VERSION} instalado"
done

echo ""
echo "=========================================="
echo "Versoes Besu disponiveis:"
ls -d besu-* | sed 's/^/  - /'
echo "=========================================="
