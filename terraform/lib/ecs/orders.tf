module "orders_service" {
  source = "./service"

  environment_name                = var.environment_name
  service_name                    = "orders"
  cluster_arn                     = aws_ecs_cluster.cluster.arn
  vpc_id                          = var.vpc_id
  subnet_ids                      = var.subnet_ids
  tags                            = var.tags
  container_image                 = module.container_images.result.orders.url
  service_discovery_namespace_arn = aws_service_discovery_private_dns_namespace.this.arn
  cloudwatch_logs_group_id        = var.cloudwatch_logs_enabled ? aws_cloudwatch_log_group.retail_store[0].id : null
  healthcheck_path                = "/actuator/health"

  environment_variables = merge(
    local.default_container_environment,
    {
      RETAIL_ORDERS_MESSAGING_PROVIDER   = "rabbitmq"
      RETAIL_ORDERS_PERSISTENCE_PROVIDER = "postgres"
      RETAIL_ORDERS_PERSISTENCE_NAME     = var.orders_db_name
    }
  )

  secrets = {
    RETAIL_ORDERS_MESSAGING_RABBITMQ_ADDRESSES = "${aws_secretsmanager_secret_version.mq.arn}:host::"
    RETAIL_ORDERS_MESSAGING_RABBITMQ_USERNAME  = "${aws_secretsmanager_secret_version.mq.arn}:username::"
    RETAIL_ORDERS_MESSAGING_RABBITMQ_PASSWORD  = "${aws_secretsmanager_secret_version.mq.arn}:password::"
    RETAIL_ORDERS_PERSISTENCE_ENDPOINT         = "${aws_secretsmanager_secret_version.orders_db.arn}:host::"
    RETAIL_ORDERS_PERSISTENCE_USERNAME         = "${aws_secretsmanager_secret_version.orders_db.arn}:username::"
    RETAIL_ORDERS_PERSISTENCE_PASSWORD         = "${aws_secretsmanager_secret_version.orders_db.arn}:password::"
  }

  additional_task_execution_role_iam_policy_arns = [
    aws_iam_policy.orders_policy.arn
  ]

  # Add Datadog configuration
  enable_datadog        = var.enable_datadog
  datadog_container_def = local.datadog_container_definition
  datadog_api_key_arn   = var.datadog_api_key_arn
  datadog_agent_image   = var.datadog_agent_image

  # Add default container configuration
  default_container_def = local.default_container_definitions

  # Add CloudWatch Logs configuration
  cloudwatch_logs_enabled = var.cloudwatch_logs_enabled
  cloudwatch_logs_region  = var.cloudwatch_logs_region
  log_group_name         = var.log_group_name
}

data "aws_iam_policy_document" "orders_db_secret" {
  statement {
    sid = ""
    actions = [
      "secretsmanager:GetSecretValue",
      "kms:Decrypt*"
    ]
    effect = "Allow"
    resources = [
      aws_secretsmanager_secret.orders_db.arn,
      aws_secretsmanager_secret.mq.arn,
      aws_kms_key.cmk.arn
    ]
  }
}

resource "aws_iam_policy" "orders_policy" {
  name        = "${var.environment_name}-orders"
  path        = "/"
  description = "Policy for orders"

  policy = data.aws_iam_policy_document.orders_db_secret.json
}

resource "random_string" "random_orders_secret" {
  length  = 4
  special = false
}

resource "aws_secretsmanager_secret" "orders_db" {
  name = "${var.environment_name}-orders-db-${random_string.random_orders_secret.result}"
}

resource "aws_secretsmanager_secret_version" "orders_db" {
  secret_id = aws_secretsmanager_secret.orders_db.id

  secret_string = jsonencode(
    {
      username = var.orders_db_username
      password = var.orders_db_password
      host     = "${var.orders_db_endpoint}:${var.orders_db_port}"
    }
  )
}

