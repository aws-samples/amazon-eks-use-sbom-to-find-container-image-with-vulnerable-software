variable "s3_bucket_name" {
  description = "S3 bucket for storing SBOM file and list of container images running on EKS"
}

variable "s3_kms_key" {
  description = "The ARN of the S3 KMS key"
  type        = string
}