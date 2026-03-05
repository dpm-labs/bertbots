data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_key_pair" "deploy" {
  count = var.ssh_public_key != "" ? 1 : 0

  key_name_prefix = "${var.project_name}-"
  public_key      = var.ssh_public_key
}

resource "aws_ebs_volume" "openclaw_data" {
  for_each = var.instances

  availability_zone = "${var.aws_region}a"
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${var.project_name}-${each.key}-data"
    Bot  = each.key
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_instance" "openclaw" {
  for_each = var.instances

  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.openclaw.id]
  iam_instance_profile   = aws_iam_instance_profile.openclaw.name
  key_name               = length(aws_key_pair.deploy) > 0 ? aws_key_pair.deploy[0].key_name : null

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    openclaw_config = templatefile("${path.module}/templates/openclaw_config.json5.tftpl", {
      telegram_dm_policy  = each.value.telegram_dm_policy
      telegram_allow_from = each.value.telegram_allow_from
      model               = var.default_model
    })
    env_file = join("\n", [for k, v in merge(var.secrets, {
      TELEGRAM_BOT_TOKEN = each.value.telegram_bot_token
    }) : "${k}=${v}"])
    workspace_repo       = var.workspace_repo
    workspace_repo_path  = var.workspace_repo_path
    workspace_repo_token = var.workspace_repo_token
    docker_compose = templatefile("${path.module}/templates/docker-compose.yml.tftpl", {
      openclaw_image = var.openclaw_image
      aws_region     = var.aws_region
      log_group      = aws_cloudwatch_log_group.openclaw.name
      instance_name  = each.key
    })
    data_volume_id = aws_ebs_volume.openclaw_data[each.key].id
  })

  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-${each.key}"
    Bot  = each.key
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
}

resource "aws_volume_attachment" "openclaw_data" {
  for_each = var.instances

  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.openclaw_data[each.key].id
  instance_id = aws_instance.openclaw[each.key].id
}
