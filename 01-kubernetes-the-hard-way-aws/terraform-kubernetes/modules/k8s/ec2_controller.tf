resource "aws_instance" "controller_instance" {
  count = var.controller_instance_count  

  associate_public_ip_address = var.controller_associate_public_ip 
  ami                         = var.controller_image_id
  key_name                    = var.controller_key_name
  security_groups             = [aws_security_group.main_sg.id]
  instance_type               = var.controller_instance_type
  private_ip                  = "${var.controller_private_ip_prefix}${count.index + 1}"
  user_data                   = "name=dev-k8s-training-controller-${count.index}"
  subnet_id                   = aws_subnet.main_subnet.id
  source_dest_check           = false
  # Disable source/destination check to allow controllers to route traffic for pod IPs (10.200.x.0/24)
  # and service IPs (10.32.0.0/24) that don't belong to the instance itself. Required for kube-proxy
  # iptables rules to work correctly when redirecting service traffic to pod endpoints.

  root_block_device {
    volume_size = var.controller_ebs_block_volume_size
  }

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(
    {
      Name        = "${var.environment}-${var.application}-controller-${count.index}",
      Environment = var.environment,
      Owner       = var.owner,
      CostCenter  = var.cost_center,
      Application = var.application
    },
    var.tags
  )
}
