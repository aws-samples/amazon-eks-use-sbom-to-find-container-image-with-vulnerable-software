data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "local_file" "buildspec_local" {
  filename = "${path.module}/../../build-spec/buildspec.yaml"
}

data "local_file" "oneoff_buildspec_local" {
  filename = "${path.module}/../../one-off-build-spec/buildspec.yaml"
}

//create kms key for s3 bucket
resource "aws_kms_key" "kms_key_s3" {
  #checkov:skip=CKV2_AWS_64:Using default KMS policy
  description             = "KMS key for s3"
  deletion_window_in_days = 10
  enable_key_rotation = true
}

// create ecr repo for EKS image discovery cronjob

resource "aws_ecr_repository" "eks_cronjob_repo" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.kms_key_s3.arn
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

// create s3 bucket for storing solution files
resource "aws_s3_bucket" "s3_bucket" {
  #checkov:skip=CKV2_AWS_61:lifecycle rule is not required
  #checkov:skip=CKV2_AWS_62:event notification does not need to be enabled but can be
  #checkov:skip=CKV_AWS_144:cross region replication is not required
  #checkov:skip=CKV2_AWS_6:public access block is not required
  #checkov:skip=CKV_AWS_18:access logging is not required for this example
  #checkov:skip=CKV_AWS_21:versioning is not required as the files on S3 can be easily recreated from ECR and EKS. Also it would incur high costs due to generating new files every 5 mins.
  bucket_prefix = "${var.s3_bucket_name}-"
}


resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  bucket = aws_s3_bucket.s3_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.kms_key_s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

// create folder for storing sbom files for container images
resource "aws_s3_object" "sbom-files" {
  bucket = aws_s3_bucket.s3_bucket.id
  key    = "sbom/"
}

// create folder for storing file with list of images running on EKS cluster
resource "aws_s3_object" "eks-running-images" {
  bucket = aws_s3_bucket.s3_bucket.id
  key    = "eks-running-images/"
}

# Set up CodeBuild project to generate SBoM file
resource "aws_codebuild_project" "codebuild_project" {
  #checkov:skip=CKV_AWS_314:logging is not required for this sample
  #checkov:skip=CKV_AWS_316:codebuild needs previlige mode to build containers
  name          = var.codebuild_project_name
  description   = "generate sbom for new images"
  build_timeout = "5"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type            = "LINUX_CONTAINER"
    #checkov:skip=CKV_AWS_316:codebuild needs previlige mode to build containers
    privileged_mode = true

    environment_variable {
      name  = "S3_BUCKET_NAME"
      value = aws_s3_bucket.s3_bucket.id
    }

    environment_variable {
      name  = "ECR_PUSH"
      value = "false"
    }

  }

  logs_config {
    cloudwatch_logs {
      group_name  = "log-group"
      stream_name = "log-stream"
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = data.local_file.buildspec_local.content
  }

}

# Set up CodeBuild project to generate SBoM file - oneoff
resource "aws_codebuild_project" "codebuild_project_oneoff" {
  name          = "${var.codebuild_project_name}-one-off"
  description   = "generate SBOM for existing images"
  build_timeout = "5"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type            = "LINUX_CONTAINER"
    #checkov:skip=CKV_AWS_316:codebuild needs previlige mode to build containers
    privileged_mode = true

    environment_variable {
      name  = "S3_BUCKET_NAME"
      value = aws_s3_bucket.s3_bucket.id
    }

    environment_variable {
      name  = "ECR_PUSH"
      value = "false"
    }

    environment_variable {
       name = "ONE_OFF_SCAN_SETTINGS"
       value = var.one_off_scan_repo_settings
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "log-group"
      stream_name = "log-stream"
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = data.local_file.oneoff_buildspec_local.content
  }

}

# Create EventBridge rule to trigger CodeBuild project when image is pushed to ECR repo
resource "aws_cloudwatch_event_rule" "ecr_push_rule" {
  name        = "ecr-push-rule"
  description = "Event rule for CodeBuild project when image is pushed to ECR repo"
  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Action"]
    detail = {
      action-type = ["PUSH"]
      result      = ["SUCCESS"]
    }
  })
}

# Create IAM role for Eventbridge
resource "aws_iam_role" "eventbridge_role" {
  name_prefix = "sbom-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

# Grant permissions to eventbridge role
resource "aws_iam_role_policy" "eventbridge_role_policy" {
  name = "sbom_eventbridge_policy"
  role = aws_iam_role.eventbridge_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "codebuild:StartBuild"
        ]
        Effect   = "Allow"
        Resource = "${aws_codebuild_project.codebuild_project.arn}"
      }
    ]
  })
}

# Create EventBridge rule target to trigger CodeBuild project
resource "aws_cloudwatch_event_target" "ecr_push_target" {
  target_id = "ecr-push-target"
  arn       = aws_codebuild_project.codebuild_project.arn
  role_arn  = aws_iam_role.eventbridge_role.arn
  rule      = aws_cloudwatch_event_rule.ecr_push_rule.name
  input_transformer {
    input_paths = {
      account         = "$.account",
      hash            = "$.detail.image-digest",
      image-tag       = "$.detail.image-tag",
      repository-name = "$.detail.repository-name"
    }
    input_template = <<EOF
    {"environmentVariablesOverride": [
      {"name":"ACCOUNT","type":"PLAINTEXT","value":<account>},
      {"name":"HASH","type":"PLAINTEXT","value":<hash>},
      {"name":"REPOSITORY_NAME","type":"PLAINTEXT","value":<repository-name>},
      {"name":"IMAGE_TAG","type":"PLAINTEXT","value":<image-tag>}
    ]}
    EOF
  }
}

# Create IAM role for CodeBuild project
resource "aws_iam_role" "codebuild_role" {
  name_prefix = "sbom-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_role_policy" {
  #checkov:skip=CKV_AWS_355:Required "*" for resoucres on ECR since the solution needs to go through ALL ECR repositories in the account
  name = "sbom_codebuild_policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:DescribeRepositories"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchDeleteImage",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:DescribeImages"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/*"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"
      },
      {
        Action = [
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.s3_bucket.id}",
          "arn:aws:s3:::${aws_s3_bucket.s3_bucket.id}/*"
        ]
      },
      {
        Action = [
          "kms:GenerateDataKey"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_kms_key.kms_key_s3.arn}"
        ]
      }
    ]
  })
}

# create IAM policy which can be attached to IAM role for service account (IRSA)
# Policy will provide EKS job permission to write file to S3 with list of container images
resource "aws_iam_policy" "eks_irsa_policy" {
  name_prefix = "eks_irsa_policy"
  description = "Policy to allow EKS job to write list of images to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:s3:::${aws_s3_bucket.s3_bucket.id}*"
      },
      {
        Action = [
          "kms:GenerateDataKey"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_kms_key.kms_key_s3.arn}"
        ]
      }
    ]
  })
}