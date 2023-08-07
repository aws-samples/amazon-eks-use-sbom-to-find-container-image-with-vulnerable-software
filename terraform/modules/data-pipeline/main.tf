data "aws_caller_identity" "current" {}

resource "aws_kms_key" "kms_key" {
  description             = "KMS key for glue crawler"
  deletion_window_in_days = 10
  enable_key_rotation = true
}

resource "aws_kms_key_policy" "kms_key_policy" {
  key_id = aws_kms_key.kms_key.key_id

  policy = jsonencode({
    Version = "2012-10-17",
    Id = "Enable Logs to use the key",
    Statement = [
      {
        "Sid": "Enable IAM User Permissions",
        "Effect": "Allow",
        "Principal": {
            "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        "Action": "kms:*",
        "Resource": "*"
      },
      {
        Sid    = "Allow use Logs for the use of key",
        Effect = "Allow",
        Principal = {
          Service = "logs.us-east-1.amazonaws.com"
        },
        Action   = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      }
    ]
  })
}


resource "aws_glue_catalog_database" "sbom_db" {
  name = "sbom_db"
}

resource "aws_glue_crawler" "sbom_crawler" {
  name          = "sbom_crawler"
  database_name = aws_glue_catalog_database.sbom_db.name
  role          = aws_iam_role.glue_crawler_role.arn
  security_configuration = aws_glue_security_configuration.sbom_crawler.name

  s3_target {
    path = "s3://${var.s3_bucket_name}/sbom"
  }

  s3_target {
    path = "s3://${var.s3_bucket_name}/eks-running-images"
  }
}

resource "aws_glue_security_configuration" "sbom_crawler" {
  name = "sbom_crawler"
	
  encryption_configuration {
    cloudwatch_encryption {
      cloudwatch_encryption_mode = "SSE-KMS"
      kms_key_arn        = aws_kms_key.kms_key.arn
    }

    job_bookmarks_encryption {
      job_bookmarks_encryption_mode = "CSE-KMS"
      kms_key_arn        = aws_kms_key.kms_key.arn
    }

    s3_encryption {
      kms_key_arn        = aws_kms_key.kms_key.arn
      s3_encryption_mode = "SSE-KMS"
    }
  }
}

resource "aws_iam_role" "glue_crawler_role" {
  name_prefix = "glue_crawler_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_policy" {
  name = "glue_s3_policy"
  role = aws_iam_role.glue_crawler_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:s3:::${var.s3_bucket_name}*"
      },
      {
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Effect = "Allow"
        Resource = [
          "${var.s3_kms_key}"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "glue_logs_kms_policy" {
  name = "glue_logs_kms_policy"
  role = aws_iam_role.glue_crawler_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:AssociateKmsKey"
        ]
        Effect = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_kms_key.kms_key.arn}"
        ]
      }
    ]
  })
}
