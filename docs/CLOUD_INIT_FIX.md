# cloud-init設定の修正（最終版）

## 問題

1. さくらのクラウドの公式cloud-init Ubuntuイメージは`disk_edit_parameter`非対応
2. 起動時にパケットフィルタが設定されているとIPアドレスが付与されない
3. Ubuntu 24.04ではpipでのシステムワイドインストールが禁止（PEP 668）

## さくらのクラウドの制約

### 重要な制約

1. **cloud-init Ubuntuイメージは`disk_edit_parameter`非対応**
   - 公式ドキュメント: https://manual.sakura.ad.jp/cloud/storage/modifydisk/about.html
   - 「パブリックアーカイブとして提供しているUbuntuなどのcloud-imgは、cloud-init専用のアーカイブとなりますので、ディスク修正は非対応」
   - `user_data`を使用する必要がある

2. **起動時のパケットフィルタでIPアドレス付与失敗**
   - サーバー作成時にパケットフィルタを設定するとIPアドレスが付与されない
   - 起動後に手動で設定しても、再起動すると再びIPアドレスが付与されなくなる
   - **解決策**: パケットフィルタを使わず、iptablesで制御

3. **Ubuntu 24.04のPEP 668制限**
   - `pip3 install ansible`がエラーになる
   - `apt install ansible`を使用する必要がある

4. **ネットワーク設定**
   - cloud-initでネットワーク設定を明示すると逆に問題が発生
   - Ubuntuのデフォルトdhcp設定に任せるのが最適

## 最終的な解決策

### アーキテクチャ

```
Terraform templatefile() で変数展開
         ↓
user_data (展開済みのcloud-init YAML)
         ↓
Server (cloud-init実行、iptablesでファイアウォール設定)
```

### 実装

#### terraform/server.tf

```hcl
# SSH Key resource
resource "sakuracloud_ssh_key" "main" {
  name       = "${var.server_name}-key"
  public_key = var.ssh_public_key
}

# Disk
resource "sakuracloud_disk" "main" {
  name              = "${var.server_name}-disk"
  source_archive_id = data.sakuracloud_archive.ubuntu.id
  size              = var.disk_size
}

# Server
resource "sakuracloud_server" "main" {
  name        = var.server_name
  core        = var.server_core
  memory      = var.server_memory
  description = "Pseudo CodeSpaces Server"

  disks = [sakuracloud_disk.main.id]

  # ✅ パケットフィルタは使用しない（IPアドレス付与の問題を回避）
  network_interface {
    upstream = "shared"
  }

  # ✅ user_dataでcloud-initを設定（disk_edit_parameterは非対応）
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    domain               = var.domain
    github_client_id     = var.github_client_id
    github_client_secret = var.github_client_secret
    ssh_public_key       = var.ssh_public_key
  })
}
```

#### terraform/cloud-init.yaml

```yaml
#cloud-config
# ✅ ネットワーク設定は不要（Ubuntuのデフォルトdhcpに任せる）

users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, docker
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - ${ssh_public_key}

chpasswd:
  expire: false
  users:
    - name: ubuntu
      password: TempPassword123!
      type: text

ssh_pwauth: true
disable_root: false

package_update: true
package_upgrade: true

packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - git
  - openssh-server
  - ansible              # ✅ aptでインストール（pipは使わない）
  - iputils-ping
  - iptables
  - iptables-persistent  # ✅ iptablesルール永続化

write_files:
  - path: /etc/environment
    content: |
      DOMAIN="${domain}"
      GITHUB_CLIENT_ID="${github_client_id}"
      GITHUB_CLIENT_SECRET="${github_client_secret}"
    append: true

runcmd:
  # ネットワーク待機
  - sleep 10
  - timeout 60 bash -c 'until ping -c 1 8.8.8.8 >/dev/null 2>&1; do sleep 2; done'
  
  - systemctl restart sshd
  
  # ✅ iptablesでファイアウォール設定
  - iptables -F
  - iptables -X
  - iptables -A INPUT -i lo -j ACCEPT
  - iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
  - iptables -A INPUT -p icmp -j ACCEPT
  - iptables -A INPUT -p tcp --dport 22 -j ACCEPT
  - iptables -A INPUT -p tcp --dport 80 -j ACCEPT
  - iptables -A INPUT -p tcp --dport 443 -j ACCEPT
  - iptables -A INPUT -j DROP
  - netfilter-persistent save
  
  # Docker installation...
```

## 変数展開の仕組み

### ステップ1: Terraform apply時

```
cloud-init.yaml (template)
    ↓
templatefile() 関数が ${domain} などを展開
    ↓
sakuracloud_note.cloud_init.content (展開済みのYAML)
```

### ステップ2: サーバー作成時

```
sakuracloud_note (ID: 12345, content: 展開済み)
    ↓
disk_edit_parameter.note.id = 12345
    ↓
ディスク編集時にcloud-initスクリプトが適用される
    ↓
サーバー起動時にcloud-init実行
```

## デプロイ手順

### 完全な再構築（必須）

`disk_edit_parameter`の変更は既存サーバーに適用されないため、完全な再構築が必要です：

```bash
cd terraform

# 1. 既存インフラを完全削除
terraform destroy -auto-approve

# 2. 新規作成
terraform apply -auto-approve

# 3. サーバー起動とcloud-init完了を待つ（重要！）
echo "Waiting for server boot and cloud-init..."
sleep 180

# 4. IPアドレス取得
SERVER_IP=$(terraform output -raw server_ip)
echo "Server IP: $SERVER_IP"
```

## 確認方法

### 1. Terraform状態確認

```bash
cd terraform

# noteリソースが作成されているか
terraform state show sakuracloud_note.cloud_init

# サーバーのdisk_edit_parameterを確認
terraform state show sakuracloud_server.main | grep -A 20 disk_edit_parameter
```

### 2. サーバーログイン

```bash
# SSH接続（3-5分待ってから）
ssh ubuntu@<IPアドレス>
# パスワード: TempPassword123!
```

### 3. cloud-init確認

```bash
# cloud-init実行状態
sudo cloud-init status
# 期待: status: done

# cloud-initログ
sudo cat /var/log/cloud-init-output.log

# 環境変数が設定されているか
cat /etc/environment
# 期待:
# DOMAIN="your-domain.com"
# GITHUB_CLIENT_ID="Ov..."
# GITHUB_CLIENT_SECRET="..."

# パスワード認証が有効か
sudo grep "^ubuntu:" /etc/shadow
# 期待: ubuntu:$6$... (ハッシュ化されたパスワード)

# SSHサービス
sudo systemctl status sshd
# 期待: active (running)

# Docker
docker --version
sudo systemctl status docker
```

## トラブルシューティング

### cloud-initが実行されていない場合

```bash
# cloud-init を手動で再実行
sudo cloud-init clean
sudo cloud-init init
sudo cloud-init modules --mode=config
sudo cloud-init modules --mode=final
```

### パスワードログインできない場合

```bash
# パスワードが設定されているか確認
sudo grep "^ubuntu:" /etc/shadow

# パスワードを手動設定
sudo passwd ubuntu
```

### 環境変数が設定されていない場合

```bash
# cloud-initログで確認
sudo cat /var/log/cloud-init-output.log | grep -A 5 "write_files"

# 手動で設定
sudo tee -a /etc/environment <<EOF
DOMAIN="your-domain.com"
GITHUB_CLIENT_ID="your-client-id"
GITHUB_CLIENT_SECRET="your-client-secret"
EOF
```

## 重要なポイント

### ✅ 正しい構成

1. **`user_data`でcloud-init設定**
   - cloud-init Ubuntuイメージでは`disk_edit_parameter`非対応
   - `templatefile()`を使用してTerraform側で変数展開
   - SSH公開鍵もテンプレート変数として渡す

2. **パケットフィルタは使用しない**
   - 起動時にパケットフィルタがあるとIPアドレスが付与されない
   - ファイアウォールはiptablesで制御
   - `iptables-persistent`で再起動後も維持

3. **パッケージはaptでインストール**
   - Ubuntu 24.04では`pip3 install ansible`が失敗（PEP 668）
   - `packages`セクションに`ansible`を追加

4. **ネットワーク設定は不要**
   - cloud-initでネットワーク設定を明示すると問題が発生
   - Ubuntuのデフォルトdhcp設定に任せる

### ❌ 避けるべき構成

1. **`disk_edit_parameter`の使用**
   ```hcl
   # ❌ cloud-init Ubuntuイメージでは非対応
   disk_edit_parameter {
     note { ... }
   }
   ```

2. **パケットフィルタの使用**
   ```hcl
   # ❌ IPアドレスが付与されない
   network_interface {
     upstream         = "shared"
     packet_filter_id = sakuracloud_packet_filter.main.id
   }
   ```

3. **cloud-initでネットワーク設定**
   ```yaml
   # ❌ 逆に問題が発生する
   network:
     version: 2
     ethernets:
       ens3:
         dhcp4: true
   ```

4. **pipでAnsibleインストール**
   ```yaml
   # ❌ Ubuntu 24.04ではエラー
   runcmd:
     - pip3 install ansible
   ```

## まとめ

最終的な構成：
- ✅ `user_data`でcloud-init設定（`disk_edit_parameter`は使わない）
- ✅ `templatefile()`でcloud-initスクリプトの変数を展開
- ✅ パケットフィルタは使わず、iptablesでファイアウォール制御
- ✅ パッケージは`apt`でインストール（pipは使わない）
- ✅ ネットワーク設定はUbuntuのデフォルトdhcpに任せる
- ✅ SSH鍵はテンプレート変数として渡す

この構成により：
- cloud-initスクリプトが確実にサーバーに適用される
- IPアドレスが正常に付与される
- 環境変数が正しく展開される
- パスワードとSSH鍵の両方が機能する
- ファイアウォールが正しく動作する
- 再起動後も設定が維持される

## 参考リンク

- [さくらのクラウド - ディスク修正について](https://manual.sakura.ad.jp/cloud/storage/modifydisk/about.html)
- [Qiita - さくらのクラウドでcloud-initを使う](https://qiita.com/kamaya-yuki/items/d86f0d288fed16bb0840)
- [Terraform Sakura Cloud Provider - Server](https://registry.terraform.io/providers/sacloud/sakuracloud/latest/docs/resources/server)
- [cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [PEP 668 – Marking Python base environments as "externally managed"](https://peps.python.org/pep-0668/)
