module "dns" {
  source  = "mergermarket/route53-dns/acuris"
  version = "2.0.0"

  domain = var.dns_domain
  name   = var.dns_name != "" ? var.dns_name : replace(var.release["component"], "/-service$/", "")
  env    = var.env
  target = var.alb_dns_name
}

module "listener_rule_home" {
  source  = "mergermarket/alb-listener-rules/acuris"
  version = "2.0.0"

  alb_listener_arn = var.alb_listener_arn
  target_group_arn = module.service.target_group_arn

  host_condition    = module.dns.fqdn
  starting_priority = var.alb_listener_rule_priority
}

module "ecs_update_monitor" {
  source  = "mergermarket/ecs-update-monitor/acuris"
  version = "2.0.0"

  cluster = var.ecs_cluster
  service = module.service.name
  taskdef = module.taskdef.arn
}

module "service" {
  source  = "mergermarket/load-balanced-ecs-service/acuris"
  version = "2.0.0"

  name                             = "${var.env}-${var.release["component"]}"
  cluster                          = var.ecs_cluster
  task_definition                  = module.taskdef.arn
  vpc_id                           = var.platform_config["vpc"]
  container_name                   = var.release["component"]
  container_port                   = var.port
  desired_count                    = var.desired_count
  deregistration_delay             = var.deregistration_delay
  health_check_interval            = var.health_check_interval
  health_check_path                = var.health_check_path
  health_check_timeout             = var.health_check_timeout
  health_check_healthy_threshold   = var.health_check_healthy_threshold
  health_check_unhealthy_threshold = var.health_check_unhealthy_threshold
  health_check_matcher             = var.health_check_matcher
}

module "taskdef" {
  source  = "mergermarket/ecs-task-definition/acuris"
  version = "2.0.0"

  family                = "${var.env}-${var.release["component"]}"
  container_definitions = [module.service_container_definition.rendered]
}

module "service_container_definition" {
  source  = "mergermarket/ecs-container-definition-no-secrets/acuris"
  version = "2.0.0"

  name           = var.release["component"]
  image          = var.release["image_id"]
  cpu            = var.cpu
  memory         = var.memory
  container_port = var.port

  container_env = merge(
    {
      "LOGSPOUT_CLOUDWATCHLOGS_LOG_GROUP_STDOUT" = "${var.env}-${var.release["component"]}-stdout"
      "LOGSPOUT_CLOUDWATCHLOGS_LOG_GROUP_STDERR" = "${var.env}-${var.release["component"]}-stderr"
      "STATSD_HOST"                              = "172.17.42.1"
      "STATSD_PORT"                              = "8125"
      "STATSD_ENABLED"                           = "true"
      "ENV_NAME"                                 = var.env
      "COMPONENT_NAME"                           = var.release["component"]
      "VERSION"                                  = var.release["version"]
    },
    var.common_application_environment,
    var.application_environment,
    var.secrets,
  )

  labels = {
    component          = var.release["component"]
    env                = var.env
    team               = var.release["team"]
    version            = var.release["version"]
    "logentries.token" = var.logentries_token
  }
}

resource "aws_cloudwatch_log_group" "stdout" {
  name              = "${var.env}-${var.release["component"]}-stdout"
  retention_in_days = "7"
}

resource "aws_cloudwatch_log_group" "stderr" {
  name              = "${var.env}-${var.release["component"]}-stderr"
  retention_in_days = "7"
}

