variable "ecr_repo_name" {
  description = "Name of ECR repo for cronjob to list running images on EKS cluster"
  default     = "eks-image-discovery"
}

variable "codebuild_project_name" {
  description = "Name of codebuild project for generating SBOM"
  default     = "sbom-codebuild-project"
}

variable "s3_bucket_name" {
  description = "S3 bucket for storing SBOM file and list of container images running on EKS"
  default     = "sbom-bucket"
}

variable "one_off_scan_repo_settings" {
  description = "Settings for what repos to scan on the one-off solution "
  default     = "ALL"
}
