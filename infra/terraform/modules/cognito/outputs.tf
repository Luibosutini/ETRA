output "user_pool_id"            { value = aws_cognito_user_pool.this.id }
output "user_pool_arn"           { value = aws_cognito_user_pool.this.arn }
output "client_id"               { value = aws_cognito_user_pool_client.this.id }
output "auth_domain"             { value = aws_cognito_user_pool_domain.this.domain }
output "pre_signup_function_arn"         { value = aws_lambda_function.pre_signup.arn }
output "pre_signup_function_name"        { value = aws_lambda_function.pre_signup.function_name }
output "post_confirmation_function_name" { value = aws_lambda_function.post_confirmation.function_name }
