#!/bin/bash
# サーバーの起動を待つユーティリティスクリプト

set -e

if [ -z "$1" ]; then
    echo "使用方法: $0 <サーバーIPアドレス> [最大待機秒数]"
    echo "例: $0 133.125.84.224 600"
    exit 1
fi

SERVER_IP="$1"
MAX_WAIT="${2:-600}"  # デフォルト10分
INTERVAL=5

echo "========================================="
echo "サーバー起動待機スクリプト"
echo "========================================="
echo "サーバーIP: $SERVER_IP"
echo "最大待機時間: ${MAX_WAIT}秒"
echo "チェック間隔: ${INTERVAL}秒"
echo ""
echo "SSH接続で確認中..."
echo ""

MAX_ATTEMPTS=$((MAX_WAIT / INTERVAL))
ATTEMPT=0
SERVER_UP=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    ELAPSED=$((ATTEMPT * INTERVAL))
    
    # 進捗表示
    PERCENTAGE=$((ELAPSED * 100 / MAX_WAIT))
    printf "\r[%3d%%] 経過: %3d秒 / %3d秒 - SSH試行 %d/%d " \
        $PERCENTAGE $ELAPSED $MAX_WAIT $ATTEMPT $MAX_ATTEMPTS
    
    # SSH接続テスト（タイムアウト5秒、StrictHostKeyChecking無効）
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "$SERVER_IP" exit 2>/dev/null; then
        echo ""
        echo ""
        echo "✅ サーバーが起動しました！"
        echo "   経過時間: ${ELAPSED}秒"
        SERVER_UP=true
        break
    fi
    
    sleep $INTERVAL
done

echo ""
echo ""

if [ "$SERVER_UP" = false ]; then
    echo "❌ タイムアウト: ${MAX_WAIT}秒経ってもサーバーが応答しません"
    echo ""
    echo "トラブルシューティング:"
    echo "1. Webコンソールでサーバーの状態を確認"
    echo "   https://secure.sakura.ad.jp/cloud/"
    echo ""
    echo "2. SSH接続を手動で試す"
    echo "   ssh ubuntu@${SERVER_IP}"
    echo ""
    echo "3. サーバーのコンソールログを確認"
    echo "   - サーバーが起動しているか"
    echo "   - cloud-initが完了しているか"
    exit 1
else
    echo "✅ サーバーは正常に起動しています"
    echo ""
    echo "次のステップ:"
    echo "1. SSH接続テスト: ssh ubuntu@${SERVER_IP}"
    echo "2. cloud-init完了確認: sudo cloud-init status"
    exit 0
fi
