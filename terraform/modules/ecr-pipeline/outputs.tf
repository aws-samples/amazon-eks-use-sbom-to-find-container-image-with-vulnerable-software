output "s3_bucket_name_unique" {
  value = aws_s3_bucket.s3_bucket.id
}

output "eks_irsa_policy" {
  value = aws_iam_policy.eks_irsa_policy.arn
}

output "s3_kms_key_arn" {
  description = "The ARN of the KMS key for S3"
  value = aws_kms_key.kms_key_s3.arn
}