output "trail_arn"            { value = aws_cloudtrail.this.arn }
output "trail_bucket_name"   { value = aws_s3_bucket.trail.bucket }
