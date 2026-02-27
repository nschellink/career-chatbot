# Instance profile: SSM GetParameter (for secrets), S3 read (context bucket), and
# AmazonSSMManagedInstanceCore so Session Manager can connect to the instance.
resource "aws_iam_role" "app" {
  name_prefix = "${var.app_name}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "app" {
  name_prefix = "${var.app_name}-"
  role        = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSM"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = concat(
          [aws_ssm_parameter.openai_key.arn],
          var.pushover_token != "" ? [aws_ssm_parameter.pushover_token[0].arn] : [],
          var.pushover_user != "" ? [aws_ssm_parameter.pushover_user[0].arn] : []
        )
      },
      {
        Sid    = "S3Context"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.context.arn,
          "${aws_s3_bucket.context.arn}/*"
        ]
      }
    ]
  })
}

# Required for SSM Session Manager: instance registers with Systems Manager and accepts connections.
resource "aws_iam_role_policy_attachment" "app_ssm_managed" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name_prefix = "${var.app_name}-"
  role        = aws_iam_role.app.name
}
