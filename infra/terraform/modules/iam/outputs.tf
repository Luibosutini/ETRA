output "lambda_start_compute_role_arn"  { value = aws_iam_role.lambda_start_compute.arn }
output "lambda_stop_compute_role_arn"   { value = aws_iam_role.lambda_stop_compute.arn }
output "lambda_status_compute_role_arn" { value = aws_iam_role.lambda_status_compute.arn }
output "lambda_workspace_api_role_arn"  { value = aws_iam_role.lambda_workspace_api.arn }
output "lambda_notify_status_role_arn"  { value = aws_iam_role.lambda_notify_status.arn }
output "ec2_analysis_instance_profile"  { value = aws_iam_instance_profile.ec2_analysis.name }
