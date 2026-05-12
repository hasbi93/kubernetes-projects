resource "aws_security_group" "main_sg" {
  name        = "${var.environment}-${var.application}-sg"
  description = "Kubernetes security group"
  vpc_id      = aws_vpc.main_vpc.id

  dynamic "ingress" {
    for_each = var.ingress_rules

    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  # Allow all outbound traffic
  # Required for nodes to:
  # - Download Kubernetes binaries (kubectl, kubelet, kube-proxy, etc.) from dl.k8s.io
  # - Download etcd, containerd, CNI plugins from GitHub releases
  # - Pull container images from Docker Hub, gcr.io, registry.k8s.io
  # - Access AWS metadata service and APIs
  # - Perform DNS lookups and forward external DNS queries (CoreDNS)
  # - Allow pods to access external services and APIs
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    {
      Name        = "${var.environment}-${var.application}-security-group"
      Environment = var.environment
      Owner       = var.owner
      CostCenter  = var.cost_center
      Application = var.application
    },
    var.tags
  )
}