# Ansible冪等性の改善

## 変更内容

Ansibleの`command`モジュールによる警告を解消し、冪等性を確保するために以下の変更を実施しました。

## 修正前の問題

```yaml
- name: Build and start Docker containers
  ansible.builtin.command:
    cmd: docker compose up -d --build
    chdir: "{{ app_dir }}"
```

**問題点:**
- `command`モジュールは冪等性がない
- 実行のたびにchangedになる
- Ansible lintで警告が発生

## 修正後

```yaml
- name: Build and start Docker containers
  community.docker.docker_compose_v2:
    project_src: "{{ app_dir }}"
    build: always
    state: present
```

**改善点:**
- ✅ 冪等性が確保される
- ✅ 変更がない場合はchangedにならない
- ✅ Ansible lintの警告が解消
- ✅ より宣言的で読みやすいコード

## 追加ファイル

### `ansible/requirements.yml`

必要なAnsibleコレクションを定義：

```yaml
---
collections:
  - name: community.docker
    version: ">=3.4.0"
```

### インストール方法

```bash
ansible-galaxy collection install -r requirements.yml
```

## 自動化

以下のファイルで自動的にコレクションがインストールされます：

1. **`.devcontainer/post-create.sh`**
   - Dev Container起動時に自動インストール

2. **`scripts/deploy.sh`**
   - デプロイスクリプト実行時に自動インストール

## メリット

1. **冪等性の確保**
   - 同じplaybookを複数回実行しても安全
   - 変更がない場合は何もしない

2. **より正確な状態管理**
   - Dockerコンテナの状態を正確に把握
   - 必要な場合のみビルド・再起動

3. **ベストプラクティス準拠**
   - Ansible公式推奨の方法
   - コミュニティ標準に準拠

## 注意事項

- 初回実行時は`community.docker`コレクションのインストールが必要
- Dev Containerまたはデプロイスクリプトを使用する場合は自動的にインストールされる
- 手動実行の場合は `ansible-galaxy collection install -r requirements.yml` を実行

## 参考リンク

- [community.docker.docker_compose_v2 モジュール](https://docs.ansible.com/ansible/latest/collections/community/docker/docker_compose_v2_module.html)
- [Ansible Collections](https://docs.ansible.com/ansible/latest/user_guide/collections_using.html)
