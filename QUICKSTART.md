# Pseudo CodeSpaces - クイックスタートガイド

## 概要

このガイドでは、最短でPseudo CodeSpacesをデプロイする手順を説明します。

## 前提条件チェックリスト

- [ ] さくらのクラウドアカウント
- [ ] GitHubアカウント
- [ ] ドメイン（DNSレコードを設定可能なもの）
- [ ] SSH鍵ペア（~/.ssh/id_rsa と ~/.ssh/id_rsa.pub）

## ステップ1: GitHub OAuth Appの作成

1. https://github.com/settings/developers にアクセス
2. "OAuth Apps" → "New OAuth App" をクリック
3. 以下を入力：
   ```
   Application name: Pseudo CodeSpaces
   Homepage URL: https://your-domain.com
   Authorization callback URL: https://your-domain.com/auth/github/callback
   ```
4. "Register application" をクリック
5. **Client ID** と **Client Secret** を控える

## ステップ2: さくらのクラウドAPIキーの取得

1. https://secure.sakura.ad.jp/cloud/ にログイン
2. 右上のアカウント → APIキー
3. "追加" をクリック
4. **トークン** と **シークレット** を控える

## ステップ3: 環境変数の設定

### GitHub CodeSpacesの場合

1. リポジトリの Settings → Secrets and variables → Codespaces
2. "New repository secret" で以下を追加：

**重要**: GitHub CodeSpacesのSecretsは自動的に大文字に変換されるため、以下の大文字の変数名で登録してください。

```
TF_VAR_SAKURA_TOKEN=<さくらのクラウドのトークン>
TF_VAR_SAKURA_SECRET=<さくらのクラウドのシークレット>
TF_VAR_SSH_PUBLIC_KEY=<~/.ssh/id_rsa.pubの内容>
TF_VAR_DOMAIN=<あなたのドメイン>
TF_VAR_GITHUB_CLIENT_ID=<GitHub OAuth AppのClient ID>
TF_VAR_GITHUB_CLIENT_SECRET=<GitHub OAuth AppのClient Secret>
```

Dev Containerが起動すると、これらは自動的に小文字混じりの形式（`TF_VAR_sakura_token`等）に変換されます。

📘 **詳細**: [CodeSpaces Secrets設定ガイド](docs/CODESPACES_SECRETS.md)を参照してください。

### ローカルまたはDev Containerの場合

```bash
# .env.exampleをコピー
cp .env.example .env

# .envを編集して環境変数を設定
nano .env

# 環境変数を読み込む
source .env
```

## ステップ4: セットアップチェック

```bash
./scripts/check-setup.sh
```

全てのチェックに合格することを確認してください。

## ステップ5: デプロイ

### 方法1: 自動デプロイスクリプトを使用（推奨）

```bash
./scripts/deploy.sh
```

このスクリプトは以下を実行します：
1. 環境変数のチェック
2. Terraformでインフラをデプロイ
3. サーバーIPアドレスの表示
4. （DNSレコード設定後）Ansibleでサーバーを構築

### 方法2: 手動でステップ実行

#### 5-1. Terraformでインフラをデプロイ

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

出力されたIPアドレスを控える。

#### 5-2. DNSレコードの設定

ドメインのDNS設定で、Aレコードを追加：

```
タイプ: A
名前: @ (またはサブドメイン)
値: <terraformで取得したIPアドレス>
TTL: 3600
```

DNSの伝播を確認：

```bash
nslookup your-domain.com
# または
dig your-domain.com
```

#### 5-3. Ansibleインベントリの設定

```bash
cd ../ansible
nano inventory.ini
```

以下のように編集：

```ini
[pseudo_codespaces]
<IPアドレス> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
```

#### 5-4. Ansibleでサーバーを構築

```bash
# 必要なAnsibleコレクションをインストール
ansible-galaxy collection install -r requirements.yml

# Playbookを実行
ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventory.ini playbook.yml
```

## ステップ6: アクセス確認

ブラウザで `https://your-domain.com` にアクセス。

### 期待される動作

1. ランディングページが表示される
2. 「GitHubでログイン」ボタンが表示される
3. クリックするとGitHubの認証ページにリダイレクトされる
4. 認証後、ダッシュボードが表示される

## トラブルシューティング

### 🚨 サーバーにログインできない（最も一般的な問題）

**症状**: SSH接続タイムアウト、Webコンソールで「Login incorrect」

**原因**: 古い設定でデプロイした場合、パスワードが正しく設定されていない

**解決策**: 最新のコードで完全再デプロイ

```bash
# 最新のコードを取得
git pull

# 完全再デプロイ
./scripts/full-redeploy.sh
```

**一時パスワード**: `TempPassword123!`（ログイン後すぐに変更してください）

📘 詳細: [docs/SSH_CONNECTION_TROUBLESHOOTING.md](docs/SSH_CONNECTION_TROUBLESHOOTING.md)

### SSL証明書エラー

**原因**: DNSレコードが正しく設定されていないか、伝播が完了していない

**解決策**:
```bash
# DNSを確認
nslookup your-domain.com

# 証明書を再取得
ssh ubuntu@your-server
sudo certbot certonly --standalone -d your-domain.com
```

### サービスにアクセスできない

**原因**: ファイアウォールまたはDockerが起動していない

**解決策**:
```bash
ssh ubuntu@your-server
sudo systemctl status docker
docker ps
docker logs nginx
docker logs pseudo-codespaces-app
```

### GitHub OAuth認証が失敗する

**原因**: GitHub OAuth Appの設定が間違っている

**解決策**:
1. GitHub OAuth Appの設定を確認
2. Callback URLが `https://your-domain.com/auth/github/callback` であることを確認
3. Client IDとClient Secretが正しいことを確認

## 次のステップ

サービスが正常に起動したら：

1. ダッシュボードで新しいワークスペースを作成
2. GitリポジトリのURLを入力
3. ワークスペースが起動するのを待つ
4. 「開く」をクリックしてcode-serverにアクセス

## サポート

問題が解決しない場合は、以下を確認してください：

- README.mdの詳細なドキュメント
- GitHubのIssues
- サーバーのログ: `/var/log/` および `docker logs`

## デプロイ時間の目安

- Terraform: 約5-10分
- DNS伝播: 数分〜数時間（プロバイダによる）
- Ansible: 約10-15分
- **合計**: 約30分〜2時間
