# さくらのクラウド Ubuntu イメージ選択ガイド

## 問題: Ubuntu イメージが見つからない場合

Terraformで以下のようなエラーが出る場合：

```
Error: Your query returned no results. Please change your search criteria and try again.
```

## 原因

さくらのクラウドで利用可能なUbuntuイメージの名前が変更されている可能性があります。

## 解決方法

### 1. 利用可能なイメージを確認

以下のTerraformコードで利用可能なUbuntuイメージを確認できます：

```hcl
# debug.tf として一時的に作成
data "sakuracloud_archive" "all_ubuntu" {
  filter {
    condition {
      name   = "Name"
      values = ["Ubuntu"]
    }
  }
}

output "available_ubuntu_images" {
  value = data.sakuracloud_archive.all_ubuntu
}
```

実行：

```bash
cd terraform
terraform apply
```

### 2. さくらのクラウドAPIで確認

`sacloud`コマンドラインツールを使用する場合：

```bash
# さくらのクラウドCLIをインストール
# https://github.com/sacloud/usacloud

# アーカイブ一覧を取得
sacloud archive ls --filter-search Ubuntu
```

### 3. 現在の設定

`terraform/server.tf`の現在の設定：

```hcl
data "sakuracloud_archive" "ubuntu" {
  filter {
    names = ["Ubuntu 24.04"]
  }
}
```

### 4. 代替設定（イメージが見つからない場合）

#### オプションA: タグで検索

```hcl
data "sakuracloud_archive" "ubuntu" {
  filter {
    tags = ["distro-ubuntu"]
  }
}
```

#### オプションB: 条件検索

```hcl
data "sakuracloud_archive" "ubuntu" {
  filter {
    condition {
      name   = "Name"
      values = ["Ubuntu"]
    }
    condition {
      name   = "Tags.Name"
      values = ["current-stable"]
    }
  }
}
```

#### オプションC: 特定のIDを指定

```hcl
# IDが分かっている場合
data "sakuracloud_archive" "ubuntu" {
  filter {
    id = "123456789012"  # 実際のアーカイブID
  }
}
```

### 5. よくあるイメージ名

さくらのクラウドで使用される一般的なUbuntuイメージ名：

- `Ubuntu 24.04 LTS (Noble Numbat)`
- `Ubuntu 24.04`
- `Ubuntu Server 24.04 LTS`
- `ubuntu-24.04-amd64`

### 6. Cloud-init対応の確認

Cloud-init対応版を使用するには、イメージ名またはタグに以下が含まれているか確認：

- `cloud-init`
- `cloudimg`

**注意**: さくらのクラウドには以下の2種類があります：

1. **Cloud-init対応版**: 推奨。自動設定が可能
2. **Cloud-init非対応版**: ユーザー名が`ubuntu`固定

このプロジェクトではCloud-init対応版を使用することを推奨します。

## トラブルシューティング

### イメージが複数ヒットする場合

```hcl
data "sakuracloud_archive" "ubuntu" {
  filter {
    names = ["Ubuntu 24.04"]
  }
  
  # 最新のものを取得（複数ある場合）
  # または最初のものを使用
}

# リソースで最初のイメージを使用
resource "sakuracloud_disk" "main" {
  source_archive_id = data.sakuracloud_archive.ubuntu.id
  # ...
}
```

### 検索結果が0件の場合

1. さくらのクラウドのコントロールパネルでアーカイブ一覧を確認
2. 正確な名前をコピー
3. `server.tf`を更新

### ゾーンによる違い

ゾーン（is1a, is1b, tk1a等）によって利用可能なイメージが異なる場合があります。

```hcl
# variables.tfでゾーンを確認
variable "zone" {
  type    = string
  default = "is1a"  # または is1b, tk1a, tk1v
}
```

## 推奨設定

シンプルで確実な設定：

```hcl
data "sakuracloud_archive" "ubuntu" {
  filter {
    names = ["Ubuntu 24.04"]
  }
}
```

これでイメージが見つからない場合は、さくらのクラウドのコントロールパネルで正確な名前を確認してください。

## 参考リンク

- [Terraform Sakura Cloud Provider Documentation](https://registry.terraform.io/providers/sacloud/sakuracloud/latest/docs)
- [さくらのクラウド パブリックアーカイブ](https://manual.sakura.ad.jp/cloud/server/archive.html)
