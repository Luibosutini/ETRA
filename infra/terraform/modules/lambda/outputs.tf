output "function_arns" {
  value = { for k, v in aws_lambda_function.this : k => v.arn }
}

output "function_names" {
  value = { for k, v in aws_lambda_function.this : k => v.function_name }
}
