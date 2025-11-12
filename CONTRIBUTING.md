# Contributing to Workspaces

このプロジェクトへの貢献を歓迎します！

## 貢献の方法

### バグ報告

バグを発見した場合は、以下の情報を含めてIssueを作成してください：

- バグの詳細な説明
- 再現手順
- 期待される動作
- 実際の動作
- 環境情報（OS、ブラウザ、バージョンなど）
- エラーログ（ある場合）

### 機能リクエスト

新機能の提案は、以下を含めてIssueを作成してください：

- 機能の説明
- ユースケース
- 期待される動作

### プルリクエスト

1. このリポジトリをフォーク
2. 新しいブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add some amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. プルリクエストを作成

### コーディング規約

- **Terraform**: HashiCorp Style Guideに従う
- **Ansible**: YAML lintに合格すること
- **JavaScript**: セミコロンを使用し、2スペースインデント
- **コメント**: 複雑なロジックには日本語または英語でコメントを追加

### テスト

変更を行う場合は、以下を確認してください：

- [ ] Terraformのコードが正しくフォーマットされている (`terraform fmt`)
- [ ] Ansible playbookが構文チェックを通過する (`ansible-playbook --syntax-check`)
- [ ] 変更が既存の機能を壊していない

## 開発環境のセットアップ

1. リポジトリをクローン
2. Dev Containerで開く
3. 環境変数を設定
4. `./scripts/check-setup.sh` でセットアップを確認

## 質問やサポート

質問がある場合は、遠慮なくIssueを作成してください。

## ライセンス

このプロジェクトに貢献することで、あなたの貢献がMITライセンスの下でライセンスされることに同意したものとみなされます。
