# 重要な修正: ログイン問題の解決

## 日付
2025年11月4日

## 問題の概要

`terraform destroy` → `./scripts/deploy.sh` で再構築した後、以下の症状が発生：

1. SSH接続がタイムアウト
2. PINGに応答しない
3. Webコンソールからubuntu / TempPassword123! でログインしようとすると「Login incorrect」

## 根本原因

### 1. lifecycle.ignore_changes問題

`terraform/server.tf`に以下の設定があった：

```hcl
lifecycle {
  ignore_changes = [
    disk_edit_parameter
  ]
}
```

この設定により：
- Terraform再適用時に`disk_edit_parameter`の変更が無視される
- パスワード設定が適用されない
- SSH鍵の設定も適用されない

### 2. さくらのクラウドの仕様

さくらのクラウドでは：
- `disk_edit_parameter`はディスク作成時のみ実行される
- すでに存在するディスクには適用されない
- `terraform destroy`で完全削除してから再作成する必要がある

### 3. cloud-initの不完全な設定

`terraform/cloud-init.yaml`に：
- ubuntuユーザーのパスワード設定がなかった
- `chpasswd`モジュールが使われていなかった

## 実施した修正

### 1. terraform/server.tf

#### 修正前
```hcl
lifecycle {
  ignore_changes = [
    disk_edit_parameter
  ]
}
```

#### 修正後
```hcl
# lifecycle ignore_changes を削除 - パスワード設定を確実に適用するため
# lifecycle {
#   ignore_changes = [
#     disk_edit_parameter
#   ]
# }
```

また、パケットフィルタにICMP（ping）を追加：

```hcl
# ICMP (ping)
expression {
  protocol    = "icmp"
  allow       = true
  description = "Allow ICMP (ping)"
}
```

### 2. terraform/cloud-init.yaml

#### 修正前
```yaml
#cloud-config
ssh_pwauth: true
disable_root: false
```

#### 修正後
```yaml
#cloud-config
# ユーザー設定
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, docker
    shell: /bin/bash
    lock_passwd: false

# パスワード設定（平文で指定可能）
chpasswd:
  expire: false
  users:
    - name: ubuntu
      password: TempPassword123!
      type: text

ssh_pwauth: true
disable_root: false
```

### 3. デプロイスクリプトの改善

#### scripts/full-redeploy.sh（新規作成）

完全な再デプロイを自動化するスクリプト：

- `terraform destroy`を実行
- Terraform状態をクリーンアップ
- `terraform init` & `terraform apply`
- サーバー起動待機（180秒）
- 接続テスト（ping, SSH）
- Ansibleインベントリの自動更新

#### scripts/deploy.sh（更新）

既存のデプロイスクリプトを改善：

- サーバー起動待機時間を追加（180秒）
- 自動接続テスト
- Ansibleインベントリの自動更新
- より詳細なエラーメッセージ

## 使用方法

### 新規デプロイまたは完全再構築

```bash
./scripts/full-redeploy.sh
```

このスクリプトは：
1. 既存のインフラを完全削除
2. Terraform状態をクリーンアップ
3. 新しいインフラを作成
4. サーバーが起動するまで待機
5. 接続テストを実行
6. Ansibleインベントリを自動更新

### 通常のデプロイ

```bash
./scripts/deploy.sh
```

改善された機能：
- サーバー起動を自動的に待機
- 接続テストを実行
- 問題がある場合は詳細なエラーメッセージを表示

## ログイン情報

### 一時パスワード

```
ユーザー名: ubuntu
パスワード: TempPassword123!
```

**重要**: 初回ログイン後すぐにパスワードを変更してください：

```bash
sudo passwd ubuntu
```

### SSH接続

パスワード認証とSSH鍵認証の両方が有効です：

```bash
# SSH鍵で接続（推奨）
ssh ubuntu@<IPアドレス>

# パスワードで接続（一時的）
ssh ubuntu@<IPアドレス>
# パスワードプロンプトで: TempPassword123!
```

## 接続テスト手順

### 1. Ping テスト

```bash
ping -c 3 <IPアドレス>
```

成功すれば、ネットワークは正常です。

### 2. SSH テスト

```bash
ssh -o ConnectTimeout=10 ubuntu@<IPアドレス>
```

### 3. Webコンソールテスト

1. さくらのクラウドコントロールパネルを開く
2. サーバーを選択
3. 「コンソール」をクリック
4. ログイン:
   - Username: `ubuntu`
   - Password: `TempPassword123!`

### 4. サーバー状態確認（コンソールまたはSSH経由）

```bash
# ネットワーク設定
ip addr show
ip route show

# SSHサービス
sudo systemctl status sshd

# cloud-init完了確認
sudo cloud-init status

# cloud-initログ
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log
```

## 今後の推奨事項

### 1. セキュリティ

初回ログイン後、以下を実施してください：

```bash
# パスワード変更
sudo passwd ubuntu

# パスワード認証を無効化（SSH鍵のみにする）
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

### 2. Terraform状態管理

本番環境では：
- リモートバックエンド（Terraform Cloud, S3など）を使用
- 状態ファイルのバージョン管理
- 複数人での作業時のロック機構

### 3. cloud-initの改善

より安全な方法として：
- パスワードはハッシュ化して保存
- 初回ログイン時に強制パスワード変更
- 監査ログの有効化

## トラブルシューティング参照

詳細なトラブルシューティング情報：

- [SSH接続トラブルシューティング](./SSH_CONNECTION_TROUBLESHOOTING.md)
- [README.md - トラブルシューティングセクション](../README.md#トラブルシューティング)
- [QUICKSTART.md - トラブルシューティング](../QUICKSTART.md#トラブルシューティング)

## 検証済み環境

- さくらのクラウド: 石狩第1ゾーン
- Ubuntu: 24.04 LTS (cloud-init対応)
- Terraform: v1.5.0以上
- Ansible: 2.15以上

## 変更ファイル一覧

- `terraform/server.tf` - lifecycle.ignore_changes削除、ICMP追加
- `terraform/cloud-init.yaml` - users, chpasswd追加
- `scripts/deploy.sh` - 起動待機、接続テスト、自動インベントリ更新
- `scripts/full-redeploy.sh` - 新規作成
- `docs/SSH_CONNECTION_TROUBLESHOOTING.md` - 更新
- `README.md` - トラブルシューティング追加
- `QUICKSTART.md` - トラブルシューティング追加
