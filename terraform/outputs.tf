output "instance_details" {
  description = "Details for each OpenClaw instance"
  value = {
    for name, instance in aws_instance.openclaw : name => {
      instance_id = instance.id
      public_ip   = instance.public_ip
      ssh_command = instance.public_ip != null ? "ssh ec2-user@${instance.public_ip}" : null
      ssm_command = "aws ssm start-session --target ${instance.id} --region ${var.aws_region}"
    }
  }
}

output "cloudwatch_logs_command" {
  description = "Command to tail CloudWatch logs"
  value       = "aws logs tail ${aws_cloudwatch_log_group.openclaw.name} --follow --region ${var.aws_region}"
}
