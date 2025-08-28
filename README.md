# dify-aws-terraform

AWS上にDifyアプリケーションをセキュアにデプロイするためのTerraformモジュールです。

## 主要なセキュリティ機能

- **EFS暗号化**: 保存時および転送時の暗号化を強制
- **ElastiCache認証**: パスワード保護されたデフォルトユーザー
- **VPCエンドポイント**: プライベート通信によるAWSサービスアクセス
- **セキュリティグループ**: 最小権限の原則に基づくアクセス制御
- **Cognito認証**: SAML IdP統合による企業認証

## セットアップ手順

### 1. パブリックイメージをプライベートECRにプッシュ

Difyが使用するパブリックDockerイメージをプライベートECRリポジトリにプッシュする必要があります。

#### 必要なイメージ

```bash
# Dify API/Worker用
langgenius/dify-api:1.7.2

# Dify Web用  
langgenius/dify-web:1.7.2

# Dify Sandbox用
langgenius/dify-sandbox:0.2.12

# Dify Plugin Daemon用
langgenius/dify-plugin-daemon:0.0.2
```

#### プッシュ手順

**注意**: このTerraformモジュールではFargateのARM64アーキテクチャを使用しているため、イメージをプルする際は `--platform linux/arm64` を指定する必要があります。

**環境変数の設定**
効率化のため、以下の環境変数を事前に設定してください：

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=ap-northeast-1
export BASE_NAME=dify-test-001      # 使用するbase_nameに置き換え
```

1. **ECRにログイン**
```bash
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
```

2. **パブリックイメージをプル**
```bash
# ARM64プラットフォームを指定してプル（Fargateで使用するため）
docker pull --platform linux/arm64 langgenius/dify-api:1.7.2
docker pull --platform linux/arm64 langgenius/dify-web:1.7.2  
docker pull --platform linux/arm64 langgenius/dify-sandbox:0.2.12
docker pull --platform linux/arm64 langgenius/dify-plugin-daemon:0.0.2
```

3. **ECRリポジトリ用にタグ付け**
```bash
# API/Worker用
docker tag langgenius/dify-api:1.7.2 ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BASE_NAME}/dify-api:latest

# Web用
docker tag langgenius/dify-web:1.7.2 ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BASE_NAME}/dify-web:latest

# Sandbox用
docker tag langgenius/dify-sandbox:0.2.12 ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BASE_NAME}/dify-sandbox:latest

# Plugin Daemon用
docker tag langgenius/dify-plugin-daemon:0.0.2 ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BASE_NAME}/dify-plugin_daemon:latest
```

4. **ECRにプッシュ**
```bash
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BASE_NAME}/dify-api:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BASE_NAME}/dify-web:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BASE_NAME}/dify-sandbox:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${BASE_NAME}/dify-plugin_daemon:latest
```

### 2. EFSにRDS CA証明書を設置

RDS Aurora PostgreSQLへのSSL接続のため、CA証明書をEFSに配置する必要があります。

#### 証明書設置手順

1. **CA証明書をダウンロード**
```bash
# RDS CA証明書をダウンロード
wget https://truststore.pki.rds.amazonaws.com/ap-northeast-1/ap-northeast-1-bundle.pem -O rds-ca-bundle.pem
```

2. **EFSマウントポイントを作成**
```bash
# EFSをマウントするディレクトリを作成
sudo mkdir -p /mnt/efs

# EFSをマウント（EFS_IDは実際のEFSファイルシステムIDに置き換え）
# セキュリティ向上のため TLS暗号化を必須で使用
sudo mount -t efs -o tls <EFS_ID>:/ /mnt/efs
```

3. **証明書をEFSにコピー**
```bash
# EFS内にcertsディレクトリを作成
sudo mkdir -p /mnt/efs/certs

# 証明書をコピー
sudo cp rds-ca-bundle.pem /mnt/efs/certs/

# 権限を設定
sudo chmod 644 /mnt/efs/certs/rds-ca-bundle.pem
sudo chown root:root /mnt/efs/certs/rds-ca-bundle.pem
```

4. **設置確認**
```bash
# 証明書が正しく配置されているか確認
ls -la /mnt/efs/certs/
cat /mnt/efs/certs/rds-ca-bundle.pem | head -5
```

#### セキュリティに関する重要な注意事項

- **TLS暗号化必須**: EFSマウント時は必ず `-o tls` オプションを使用してください
- **EFSファイルシステムポリシー**: SSL/TLS通信以外の接続は自動的にブロックされます
- **IAM権限**: EFSアクセスには適切なIAM権限が必要です
- **証明書設置**: EFSアクセスポイントが作成された後に証明書を設置してください
- **コンテナマウント**: コンテナ内では `/app/certs/rds-ca-bundle.pem` としてマウントされます

### 3. 必要な設定情報の準備

Terraformの実行前に、以下の設定情報を準備してください：

#### AWS DNS設定 (Route53)
- **ドメイン名**: `example.com`
- **Route53ホストゾーンID**: `Z1D633PJN98FT9`
- **サブドメイン**: 
  - Dify: `dify.example.com`
  - 認証: `auth.example.com`

#### Cognito SAML IdP設定
- **IdP名**: 企業のSAML IdP名
- **メタデータURL**: またはメタデータファイルパス
- **メール属性マッピング**: SAML属性名

#### ECS タスクロールARN
EFSアクセス用のタスクロールARNを指定：
- `dify_api_task_role_arn`
- `dify_worker_task_role_arn` 
- `dify_plugin_daemon_task_role_arn`

### 4. Terraform実行

```bash
# example ディレクトリに移動
cd example

# 変数ファイルを設定
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集して上記の設定値を記入

# Terraformを実行
terraform init
terraform plan
terraform apply
```

### 5. デプロイ後の確認

デプロイ完了後、以下を確認してください：

1. **EFS暗号化**: 転送時暗号化が有効化されている
2. **ALBヘルスチェック**: 全てのターゲットがHealthy状態
3. **DNS解決**: Difyアプリケーションにアクセス可能
4. **認証フロー**: Cognito経由のSAMLログインが動作

## アーキテクチャ

```
Internet Gateway
    ↓
Application Load Balancer (Public Subnet)
    ↓
ECS Fargate Tasks (Private Subnet)
    ↓
- Aurora PostgreSQL (Multi-AZ)
- ElastiCache (Valkey)
- EFS (暗号化済み)
    ↓
VPC Endpoints (AWS Services)
```
