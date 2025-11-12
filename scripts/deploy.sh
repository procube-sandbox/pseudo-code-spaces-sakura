#!/bin/bash
# デプロイ用ヘルパースクリプト

set -e

echo "🚀 Workspaces デプロイスクリプト"
echo "========================================"

# 環境変数チェック
check_env_vars() {
    local missing=0
    
    echo "環境変数をチェック中..."
    
    if [ -z "$TF_VAR_sakura_token" ]; then
        echo "❌ TF_VAR_sakura_token が設定されていません"
        missing=1
    fi
    
    if [ -z "$TF_VAR_sakura_secret" ]; then
        echo "❌ TF_VAR_sakura_secret が設定されていません"
        missing=1
    fi
    
    if [ -z "$TF_VAR_ssh_public_key" ]; then
        echo "❌ TF_VAR_ssh_public_key が設定されていません"
        missing=1
    fi
    
    if [ -z "$TF_VAR_domain" ]; then
        echo "❌ TF_VAR_domain が設定されていません"
        missing=1
    fi
    
    if [ -z "$TF_VAR_github_client_id" ]; then
        echo "❌ TF_VAR_github_client_id が設定されていません"
        missing=1
    fi
    
    if [ -z "$TF_VAR_github_client_secret" ]; then
        echo "❌ TF_VAR_github_client_secret が設定されていません"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        echo ""
        echo "必要な環境変数が設定されていません。"
        echo "README.mdを参照して環境変数を設定してください。"
        exit 1
    fi
    
    echo "✅ 全ての環境変数が設定されています"
}

# Terraformデプロイ
deploy_terraform() {
    echo ""
    echo "📦 Terraformでインフラをデプロイ中..."
    
    cd terraform
    
    terraform init
    
    if ! terraform plan; then
        echo ""
        echo "❌ Terraform planに失敗しました"
        echo ""
        echo "よくあるエラー:"
        echo "  - Ubuntuイメージが見つからない → docs/SAKURA_UBUNTU_IMAGE.md を参照"
        echo "  - APIキーが無効 → TF_VAR_sakura_token と TF_VAR_sakura_secret を確認"
        echo "  - SSHキーの形式が無効 → TF_VAR_ssh_public_key を確認"
        exit 1
    fi
    
    read -p "デプロイを続行しますか? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform apply -auto-approve
        
        echo ""
        echo "✅ Terraformデプロイ完了"
        echo ""
        
        # サーバーIPアドレス取得
        SERVER_IP=$(terraform output -raw server_ip)
        echo "サーバーIPアドレス: $SERVER_IP"
        echo ""
        
        # サーバー接続確認（段階的チェック）
        echo "⏳ サーバーの接続確認を開始します..."
        echo ""
        
        # ステップ1: SSHポートの確認（ncコマンド）
        echo "🔍 ステップ1: SSHポート（22番）の確認中..."
        MAX_PORT_ATTEMPTS=12  # 1分間（5秒間隔で12回）
        PORT_ATTEMPT=0
        PORT_OPEN=false
        
        while [ $PORT_ATTEMPT -lt $MAX_PORT_ATTEMPTS ]; do
            PORT_ATTEMPT=$((PORT_ATTEMPT + 1))
            ELAPSED=$((PORT_ATTEMPT * 5))
            
            # 進捗表示
            printf "\r   経過時間: %d秒 / 60秒 - ポート試行 %d/%d..." $ELAPSED $PORT_ATTEMPT $MAX_PORT_ATTEMPTS
            
            # ncコマンドでポート22の確認（タイムアウト3秒）
            if nc -z -w 3 "$SERVER_IP" 22 2>/dev/null; then
                echo ""
                echo "✅ SSHポートが開いています！（${ELAPSED}秒後）"
                PORT_OPEN=true
                break
            fi
            
            sleep 5
        done
        
        echo ""
        
        if [ "$PORT_OPEN" = false ]; then
            echo "❌ エラー: 1分経ってもSSHポートが開きません"
            echo ""
            echo "Webコンソールで確認してください:"
            echo "  https://secure.sakura.ad.jp/cloud/"
            echo ""
            echo "考えられる原因:"
            echo "  - サーバーがまだ起動処理中"
            echo "  - ネットワーク設定の問題"
            echo "  - SSHサービスが起動していない"
            echo ""
            echo "Webコンソールからログイン:"
            echo "  ユーザー名: ubuntu"
            echo "  パスワード: TempPassword123!"
            echo ""
            echo "確認コマンド:"
            echo "  sudo systemctl status sshd"
            echo "  ip a show ens3"
            exit 1
        fi
        
        # ステップ2: SSH接続とcloud-init状態確認
        echo ""
        echo "🔍 ステップ2: SSH接続とcloud-init状態の確認中..."
        MAX_CLOUD_ATTEMPTS=12  # 1分間（5秒間隔で12回）
        CLOUD_ATTEMPT=0
        CLOUD_INIT_DONE=false
        
        while [ $CLOUD_ATTEMPT -lt $MAX_CLOUD_ATTEMPTS ]; do
            CLOUD_ATTEMPT=$((CLOUD_ATTEMPT + 1))
            ELAPSED=$((CLOUD_ATTEMPT * 5))
            
            # 進捗表示
            printf "\r   経過時間: %d秒 / 60秒 - cloud-init試行 %d/%d..." $ELAPSED $CLOUD_ATTEMPT $MAX_CLOUD_ATTEMPTS
            
            # SSH接続でcloud-init状態を確認
            # 注意: スクリプト全体で `set -e` が有効なため、
            # ssh が非0終了した場合にスクリプト全体が終了しないよう
            # 一時的にエラーストップを無効化してから実行します。
            set +e
            CLOUD_STATUS=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes ubuntu@"$SERVER_IP" "sudo cloud-init status" 2>&1)
            SSH_EXIT_CODE=$?
            set -e
            
            if [ $SSH_EXIT_CODE -ne 0 ]; then
                echo ""
                echo "❌ SSH接続エラー:"
                echo "$CLOUD_STATUS"
                echo ""
                echo "Webコンソールで確認してください:"
                echo "  https://secure.sakura.ad.jp/cloud/"
                echo ""
                echo "Webコンソールからログイン:"
                echo "  ユーザー名: ubuntu"
                echo "  パスワード: TempPassword123!"
                exit 1
            fi
            
            # cloud-init status の出力に "done" が含まれているかチェック
            if echo "$CLOUD_STATUS" | grep -q "done"; then
                echo ""
                echo "✅ cloud-initが完了しました！（${ELAPSED}秒後）"
                echo "cloud-init status: $CLOUD_STATUS"
                CLOUD_INIT_DONE=true
                break
            fi
            
            sleep 5
        done
        
        echo ""
        
        if [ "$CLOUD_INIT_DONE" = false ]; then
            echo "❌ エラー: 1分経ってもcloud-initが完了しません"
            echo ""
            echo "現在のcloud-init状態: $CLOUD_STATUS"
            echo ""
            echo "Webコンソールで確認してください:"
            echo "  https://secure.sakura.ad.jp/cloud/"
            echo ""
            echo "考えられる原因:"
            echo "  - cloud-initの処理に時間がかかっている"
            echo "  - cloud-initでエラーが発生している"
            echo ""
            echo "Webコンソールからログイン:"
            echo "  ユーザー名: ubuntu"
            echo "  パスワード: TempPassword123!"
            echo ""
            echo "確認コマンド:"
            echo "  sudo cloud-init status"
            echo "  sudo cloud-init logs"
            echo "  sudo journalctl -u cloud-init"
            exit 1
        fi
        
        echo ""
        echo "✅ サーバーの接続確認が完了しました"
        
        echo ""
        echo "次のステップ:"
        echo "1. 上記のIPアドレスをドメインのAレコードに設定してください"
        echo "2. DNSの伝播を待ってください（数分〜数時間）"
        echo "3. ansible/inventory.ini が自動更新されました"
        echo "4. Ansibleを実行してください: ./scripts/deploy.sh ansible"
        
        # Ansibleインベントリの自動更新
        cd ../ansible
        cat > inventory.ini << EOF
[workspaces]
${SERVER_IP} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa

[workspaces:vars]
ansible_python_interpreter=/usr/bin/python3
EOF
        echo ""
        echo "✅ Ansible inventory.ini を更新しました"
        cd ../terraform
    else
        echo "デプロイをキャンセルしました"
        exit 0
    fi
    
    cd ..
}

# Ansibleデプロイ
deploy_ansible() {
    echo ""
    echo "🔧 Ansibleでサーバーを構築中..."
    
    cd ansible
    
    # インベントリファイルのチェック
    if ! grep -q "ansible_user=ubuntu" inventory.ini; then
        echo "⚠️  inventory.ini にサーバー情報が設定されていないようです"
        echo "terraform outputからIPアドレスをコピーしてinventory.iniを編集してください"
        exit 1
    fi
    
    # Ansibleコレクションのインストール
    echo "Ansibleコレクションをインストール中..."
    ansible-galaxy collection install -r requirements.yml
    
    # Ansibleの実行（明示的にインベントリと設定ファイルを指定）
    echo "Ansibleを実行中..."
    ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventory.ini playbook.yml
    
    echo ""
    echo "✅ Ansibleデプロイ完了"
    echo ""
    echo "サービスが起動しました！"
    echo "https://$TF_VAR_domain にアクセスしてください"
    
    cd ..
}

# メイン処理
main() {
    check_env_vars
    
    case "${1:-all}" in
        terraform)
            deploy_terraform
            ;;
        ansible)
            deploy_ansible
            ;;
        all)
            deploy_terraform
            echo ""
            read -p "Ansibleデプロイを続行しますか? DNSの伝播を待ってください。(y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                deploy_ansible
            fi
            ;;
        *)
            echo "使用方法: $0 [terraform|ansible|all]"
            exit 1
            ;;
    esac
}

main "$@"
