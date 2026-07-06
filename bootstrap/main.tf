# 1. 상태 파일을 저장할 S3 버킷
resource "aws_s3_bucket" "terraform_state" {
  bucket = "usb-terraform-state-2026" # 버킷 이름은 유니크해야 하므로 적절히 수정하세요

  lifecycle {
    prevent_destroy = true # 실수로 삭제되는 것 방지
  }
}

resource "aws_s3_bucket_versioning" "enabled" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 2. 동시성 제어를 위한 DynamoDB 테이블
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}