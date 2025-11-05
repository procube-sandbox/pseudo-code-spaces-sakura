# Get the latest Ubuntu 24.04 image (cloud-init enabled)
data "sakuracloud_archive" "ubuntu" {
  filter {
    # Ubuntuディストリビューションで、かつ cloud-init対応のタグを持つアーカイブを検索
    id = "113701786672"
  }
}

# SSH Key resource
resource "sakuracloud_ssh_key" "main" {
  name       = "${var.server_name}-key"
  public_key = var.ssh_public_key
}

# Disk - cloud-init対応アーカイブを使用
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

  # パケットフィルタは使用しない（cloud-init起動時にIPアドレスが付与されない問題があるため）
  # ファイアウォールはiptablesで制御
  network_interface {
    upstream = "shared"
  }

  # cloud-init対応アーカイブの場合、user_dataを使用（disk_edit_parameterは非対応）
  # 参考: https://manual.sakura.ad.jp/cloud/storage/modifydisk/about.html
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    domain               = var.domain
    github_client_id     = var.github_client_id
    github_client_secret = var.github_client_secret
    ssh_public_key       = var.ssh_public_key
  })
}
