output "workspace_bucket_name" {
  value = aws_s3_bucket.workspace.bucket
}

output "workspace_bucket_arn" {
  value = aws_s3_bucket.workspace.arn
}

output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend.bucket
}

output "frontend_bucket_arn" {
  value = aws_s3_bucket.frontend.arn
}

output "logs_bucket_name" {
  value = aws_s3_bucket.logs.bucket
}
