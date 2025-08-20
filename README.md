# dify-aws-terraform
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
```

#### プッシュ手順

**注意**: このTerraformモジュールではFargateのARM64アーキテクチャを使用しているため、イメージをプルする際は `--platform linux/arm64` を指定する必要があります。

1. **ECRにログイン**
```bash
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin <YOUR_ACCOUNT_ID>.dkr.ecr.ap-northeast-1.amazonaws.com
```

2. **パブリックイメージをプル**
```bash
# ARM64プラットフォームを指定してプル（Fargateで使用するため）
docker pull --platform linux/arm64 langgenius/dify-api:1.7.2
docker pull --platform linux/arm64 langgenius/dify-web:1.7.2  
docker pull --platform linux/arm64 langgenius/dify-sandbox:0.2.12
```

3. **ECRリポジトリ用にタグ付け**
```bash
# API/Worker用
docker tag langgenius/dify-api:1.7.2 <YOUR_ACCOUNT_ID>.dkr.ecr.ap-northeast-1.amazonaws.com/dify-api:latest

# Web用
docker tag langgenius/dify-web:1.7.2 <YOUR_ACCOUNT_ID>.dkr.ecr.ap-northeast-1.amazonaws.com/dify-web:latest

# Sandbox用
docker tag langgenius/dify-sandbox:0.2.12 <YOUR_ACCOUNT_ID>.dkr.ecr.ap-northeast-1.amazonaws.com/dify-sandbox:latest
```

4. **ECRにプッシュ**
```bash
docker push <YOUR_ACCOUNT_ID>.dkr.ecr.ap-northeast-1.amazonaws.com/dify-api:latest
docker push <YOUR_ACCOUNT_ID>.dkr.ecr.ap-northeast-1.amazonaws.com/dify-web:latest
docker push <YOUR_ACCOUNT_ID>.dkr.ecr.ap-northeast-1.amazonaws.com/dify-sandbox:latest
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
sudo mount -t efs <EFS_ID>:/ /mnt/efs

# または EFS Utilsを使用する場合
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

#### 注意事項

- EFSアクセスポイントが作成された後に証明書を設置してください
- EFSマウント時にはIAM権限が必要な場合があります
- コンテナ内では `/app/certs/rds-ca-bundle.pem` としてマウントされます

### 3. Terraform実行

```bash
# example ディレクトリに移動
cd example

# 変数ファイルを設定
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集して適切な値を設定

# Terraformを実行
terraform init
terraform plan
terraform apply
```
