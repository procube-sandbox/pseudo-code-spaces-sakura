# さくらのクラウド SSH接続トラブルシューティング

## 問題: IPアドレスが付与されない、SSH接続タイムアウト

### 症状

```bash
ssh ubuntu@<IPアドレス>
# ssh: connect to host <IP> port 22: Connection timed out

ping <IPアドレス>
# Request timeout
```

- Webコンソールでログイン可能
- `ip a show` でIPv4アドレスが表示されない
- 名前解決ができない（`ping google.com` が失敗）

### 根本原因

**さくらのクラウドのcloud-init対応Ubuntuイメージでは、起動時にパケットフィルタが設定されているとIPアドレスが付与されない**

重要な発見：
1. cloud-initイメージでサーバー作成時にパケットフィルタを設定するとIPアドレスが付与されない
2. 起動後にWebコンソールからパケットフィルタを設定するとIPアドレスは維持される
3. ただし、その状態で再起動すると再びIPアドレスが付与されなくなる
4. **起動時にパケットフィルタが設定されていることが問題**

### 解決策

**パケットフィルタを使用せず、iptablesでファイアウォールを制御する**

1. **Terraform設定の修正** (`terraform/server.tf`)
   - `sakuracloud_packet_filter`リソースを削除
   - `network_interface`からパケットフィルタの参照を削除

2. **cloud-init設定の修正** (`terraform/cloud-init.yaml`)
   - `iptables`と`iptables-persistent`パッケージをインストール
   - `runcmd`でiptablesルールを設定
   - 必要なポート（SSH, HTTP, HTTPS, ICMP）を許可

3. **その他の問題**
   - Ubuntu 24.04ではpipでのシステムワイドインストールが禁止（PEP 668）
   - Ansibleは`apt`でインストールする必要がある

## 解決手順（修正済みの設定を使用）

### 手順1: 完全な再デプロイ

パケットフィルタを削除し、iptablesを使用する設定で再構築します：

```bash
# 完全再デプロイスクリプトを使用
./scripts/full-redeploy.sh
```

または手動で：

```bash
# 1. 既存のインフラを削除（パケットフィルタリソースも削除される）
cd terraform
terraform destroy -auto-approve

# 2. 再デプロイ（パケットフィルタなし、iptablesで制御）
terraform apply -auto-approve

# 3. サーバー起動を待つ（5-10分）
# IPアドレスが正常に付与されるはず

# 4. SSH接続テスト
ssh ubuntu@$(terraform output -raw server_ip)
# パスワード: TempPassword123!
```

### 手順2: IPアドレスの確認

SSH接続後、IPアドレスとネットワーク設定を確認：

```bash
# IPv4アドレスが付与されているか確認
ip -4 a show ens3

# ルーティングテーブルの確認
ip route show

# 名前解決のテスト
ping -c 3 google.com

# iptablesルールの確認
sudo iptables -L -n -v
```

### 手順3: iptablesファイアウォールの確認

cloud-initで設定されたiptablesルールを確認：

```bash
# 現在のルールを表示
sudo iptables -L INPUT -n -v

# 保存されたルールを確認
sudo cat /etc/iptables/rules.v4
```

期待される設定：
- ループバック: 許可
- 確立済み接続: 許可
- ICMP (ping): 許可
- SSH (22): 許可
- HTTP (80): 許可
- HTTPS (443): 許可
- その他: 拒否

### 手順4: SSH設定の確認

```bash
# SSH設定ファイルを確認
sudo cat /etc/ssh/sshd_config | grep -E "PermitRootLogin|PasswordAuthentication|PubkeyAuthentication"

# SSH鍵の確認
cat ~/.ssh/authorized_keys

# SSHサービスの再起動
sudo systemctl restart sshd
```

### 手順5: cloud-initのログ確認

```bash
# cloud-initのステータス
sudo cloud-init status

# cloud-initのログ
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log

# エラーがあるか確認
sudo journalctl -u cloud-init
```

## 恒久的な解決策

### 1. パケットフィルタを使用しない（重要）

**さくらのクラウドのcloud-init Ubuntuイメージでは、パケットフィルタを使用してはいけません。**

理由：
- サーバー起動時にパケットフィルタが設定されているとIPアドレスが付与されない
- 再起動のたびに同じ問題が発生する
- ファイアウォールはiptablesで制御する

### 2. iptablesでファイアウォールを設定

cloud-init.yamlで以下を設定：

```yaml
packages:
  - iptables
  - iptables-persistent

runcmd:
  # iptablesルールを設定
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
```

### 3. cloud-init設定のベストプラクティス

1. **user_dataを使用**: `disk_edit_parameter`はcloud-initイメージで非対応
2. **ネットワーク設定は不要**: Ubuntuのデフォルトdhcpに任せる
3. **パッケージはaptで**: Ubuntu 24.04ではpipのシステムワイドインストール禁止
4. **iptablesでファイアウォール**: パケットフィルタは使用しない

## 推奨される手順（新規デプロイ）

```bash
# 1. Terraform適用
cd terraform
terraform apply

# 2. 出力からIPアドレスを取得
terraform output server_ip

# 3. さくらのクラウドのコントロールパネルを開く
# https://secure.sakura.ad.jp/cloud/

# 4. サーバーが「停止中」の場合は「起動」をクリック

# 5. 2-3分待つ

# 6. SSH接続テスト
ssh ubuntu@<IPアドレス>
# 初回パスワード: TempPassword123!

# 7. ログイン後、パスワードを変更
passwd

# 8. SSH鍵が機能するか確認
exit
ssh -i ~/.ssh/id_rsa ubuntu@<IPアドレス>

# 9. Ansible実行
cd ../ansible
ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventory.ini playbook.yml
```

## よくある質問

### Q: なぜIPアドレスが付与されないのか？

A: **起動時にパケットフィルタが設定されているため**です。さくらのクラウドのcloud-init Ubuntuイメージでは、サーバー作成時にパケットフィルタを設定するとIPアドレスが付与されません。解決策：
1. パケットフィルタリソースを削除
2. iptablesでファイアウォールを制御

### Q: なぜpingが返ってこないのか？

A: 以下のいずれかの原因：
1. IPアドレスが付与されていない（パケットフィルタの問題）
2. iptablesでICMPが拒否されている
3. Dev Container内からの外部pingは通らない（正常）

SSH接続で確認してください。

### Q: パケットフィルタを使いたい場合は？

A: cloud-initイメージでは**起動時にパケットフィルタを使用できません**。代替案：
1. **iptablesを使用**（推奨）: cloud-initで設定
2. **起動後に手動設定**: Webコンソールから設定（ただし再起動で問題再発）
3. **通常のUbuntuイメージを使用**: cloud-initではない標準イメージなら可能

### Q: Ubuntu 24.04でpip install ansibleが失敗する

A: PEP 668により、システムワイドのpipインストールが禁止されています。解決策：
- `apt install ansible`を使用
- または`pip3 install --break-system-packages ansible`（非推奨）

## 参考リンク

- [さくらのクラウド ドキュメント](https://manual.sakura.ad.jp/cloud/)
- [cloud-init ドキュメント](https://cloudinit.readthedocs.io/)
