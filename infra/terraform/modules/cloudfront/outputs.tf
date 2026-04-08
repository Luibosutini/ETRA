output "distribution_id"       { value = aws_cloudfront_distribution.viewer.id }
output "distribution_domain"   { value = aws_cloudfront_distribution.viewer.domain_name }
output "distribution_arn"      { value = aws_cloudfront_distribution.viewer.arn }
output "waf_web_acl_arn"       { value = aws_wafv2_web_acl.viewer.arn }
