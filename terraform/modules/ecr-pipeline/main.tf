data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "local_file" "buildspec_local" {
  filename = "${path.module}/../../build-spec/buildspec.yaml"
}

data "local_file" "oneoff_buildspec_local" {
  filename = "${path.module}/../../one-off-build-spec/buildspec.yaml"
}

// create ecr repo for EKS image discovery cronjob

resource "aws_ecr_repository" "eks_cronjob_repo" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

// create s3 bucket for storing solution files
resource "aws_s3_bucket" "s3_bucket" {
  bucket_prefix = "${var.s3_bucket_name}-"
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
      }
    ]
  })
}