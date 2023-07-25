output "s3_bucket_name_unique" {
  value = aws_s3_bucket.s3_bucket.id
}

output "eks_irsa_policy" {
  value = aws_iam_policy.eks_irsa_policy.arn
}