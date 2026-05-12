resource "aws_instance" "worker_instance" {
  count                       = var.worker_instance_count
  ami                         = var.worker_image_id
  instance_type               = var.worker_instance_type
  key_name                    = var.worker_key_name
  security_groups             = [aws_security_group.main_sg.id]
  associate_public_ip_address = var.worker_associate_public_ip
  subnet_id                   = aws_subnet.main_subnet.id
  private_ip                  = "${var.worker_private_ip_prefix}${count.index}"
  user_data                   = "name=worker-${count.index}|pod-cidr=10.200.${count.index}.0/24"
  source_dest_check           = false
  # Disable source/destination check to allow workers to route traffic for pod IPs (10.200.x.0/24)
  # and service IPs (10.32.0.0/24) that don't belong to the instance itself. Required for kube-proxy
  # iptables rules to work correctly when redirecting service traffic to pod endpoints.

  ebs_block_device {
    device_name = var.worker_ebs_block_device_name
    volume_size = var.worker_ebs_block_volume_size
  }

  tags = merge(
    {
      Name        = "${var.environment}-${var.application}-worker-${count.index}",
      Environment = var.environment,
      Owner       = var.owner,
      CostCenter  = var.cost_center,
      Application = var.application
    },
    var.tags
  )
}
