# Provisioning Compute Resources

In this lab, you will setup the required networking infrastructure and nodes required for the cluster.

You have two options:
1. **Option A: Terraform** - Automated infrastructure provisioning
2. **Option B: AWS CLI** - Manual step-by-step provisioning for learning

---

## Option A: Terraform Approach

Using Terraform allows you to provision all infrastructure with a single command and makes it easy to tear down resources when done.

### Prerequisites

Ensure you have Terraform installed (from [Lab 02](02-client-tools.md)):
```sh
terraform version
# Terraform v1.5.0 or later
```

### Step 1: Navigate to Terraform Directory

```sh
cd terraform-kubernetes/environments/dev/k8s
```

### Step 2: Review Configuration (Optional)

The Terraform configuration is located in `terraform-kubernetes/vars/dev/k8s.tfvars`. Key settings include:

- **VPC CIDR**: `10.0.0.0/16`
- **Subnet CIDR**: `10.0.1.0/24`
- **Pod Network**: `10.200.0.0/16`
- **Controller nodes**: 3 × t3.micro (10.0.1.10, 10.0.1.11, 10.0.1.12)
- **Worker nodes**: 3 × t3.micro (10.0.1.20, 10.0.1.21, 10.0.1.22)

You can modify these values in `k8s.tfvars` if needed.

### Step 3: Initialize Terraform

```sh
terraform init
```

This downloads the AWS provider and prepares Terraform.

### Step 4: Plan Infrastructure

```sh
terraform plan -var-file=../../../vars/dev/k8s.tfvars
```

Review the plan to see what will be created:
- 1 VPC
- 1 Subnet
- 1 Internet Gateway
- 1 Route Table
- 1 Security Group
- 1 Network Load Balancer with Target Group
- 1 SSH Key Pair
- 6 EC2 Instances (3 controllers + 3 workers)

### Step 5: Apply Configuration

```sh
terraform apply -var-file=../../../vars/dev/k8s.tfvars
```

Type `yes` when prompted. This will take 2-3 minutes to provision all resources.

### Step 6: Verify Resources

```sh
# List all instances
aws ec2 describe-instances --region us-east-2 \
  --filters "Name=tag:Application,Values=k8s-training" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],InstanceId,PrivateIpAddress,PublicIpAddress,State.Name]' \
  --output table

# Get Network Load Balancer DNS
aws elbv2 describe-load-balancers --region us-east-2 \
  --names dev-k8s-training \
  --query 'LoadBalancers[0].DNSName' \
  --output text
```

### Step 7: Save Important Variables

```sh
# Get Load Balancer ARN (needed for later labs)
LOAD_BALANCER_ARN=$(aws elbv2 describe-load-balancers --region us-east-2 \
  --names dev-k8s-training \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

# Get Security Group ID (needed for Lab 13)
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region us-east-2 \
  --filters "Name=group-name,Values=dev-k8s-training-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

# Save these for later use
echo $LOAD_BALANCER_ARN
echo $SECURITY_GROUP_ID
```

### What Terraform Created

The Terraform modules created:

1. **Networking**:
   - VPC with DNS support enabled
   - Public subnet (10.0.1.0/24)
   - Internet Gateway for external connectivity
   - Route table with default route to IGW
   - Security group with rules for SSH, Kubernetes API, and inter-cluster communication

2. **Load Balancer**:
   - Network Load Balancer for HA API server access
   - Target group pointing to controller nodes (10.0.1.11-13:6443)
   - Listener on port 443 forwarding to target group

3. **Compute**:
   - 3 controller nodes (t3.micro) with `source_dest_check` disabled
   - 3 worker nodes (t3.micro) with `source_dest_check` disabled and pod CIDRs
   - SSH key pair generated and saved as `kubernetes.id_rsa`

4. **Pod CIDR Assignment**:
   - Each worker has a unique pod CIDR configured via user-data:
     - worker-0: 10.200.0.0/24
     - worker-1: 10.200.1.0/24
     - worker-2: 10.200.2.0/24
   - Note: VPC routes for these pod networks will be created in [Lab 11](11-pod-network-routes.md)

### Terraform State

Terraform keeps track of your infrastructure in `terraform.tfstate`. **Do not delete this file** - you'll need it to modify or destroy resources later.

### Cleanup (When Done with All Labs)

To destroy all resources created by Terraform:

```sh
cd terraform-kubernetes/environments/dev/k8s
terraform destroy -var-file=../../../vars/dev/k8s.tfvars
```

This will remove all infrastructure and stop AWS charges.

---

## Option B: AWS CLI Manual Approach (For Learning)

If you want to understand each resource individually, follow the manual AWS CLI approach below.

> **Note**: If you used Terraform (Option A), skip this section and proceed to [Lab 04](04-certificate-authority.md).

> **Important**: These manual instructions create resources with the same naming convention and configuration as the Terraform approach for consistency.

### Set Region

All commands use `us-east-2` region to match the Terraform configuration:

```sh
export AWS_REGION=us-east-2
```

## Networking

### VPC

Lets create a dedicated VPC for the setup.

```sh
VPC_ID=$(aws ec2 create-vpc \
  --region ${AWS_REGION} \
  --cidr-block 10.0.0.0/16 \
  --output text --query 'Vpc.VpcId')

aws ec2 create-tags \
  --region ${AWS_REGION} \
  --resources ${VPC_ID} \
  --tags \
    Key=Name,Value=dev-k8s-training-vpc \
    Key=Environment,Value=dev \
    Key=Application,Value=k8s-training

aws ec2 modify-vpc-attribute \
  --region ${AWS_REGION} \
  --vpc-id ${VPC_ID} \
  --enable-dns-support '{"Value": true}'

aws ec2 modify-vpc-attribute \
  --region ${AWS_REGION} \
  --vpc-id ${VPC_ID} \
  --enable-dns-hostnames '{"Value": true}'
```

### Subnet

Create a subnet:

```sh
SUBNET_ID=$(aws ec2 create-subnet \
  --region ${AWS_REGION} \
  --vpc-id ${VPC_ID} \
  --cidr-block 10.0.1.0/24 \
  --output text --query 'Subnet.SubnetId')

aws ec2 create-tags \
  --region ${AWS_REGION} \
  --resources ${SUBNET_ID} \
  --tags \
    Key=Name,Value=dev-k8s-training-public-subnet \
    Key=Environment,Value=dev \
    Key=Application,Value=k8s-training
```

### Internet Gateway

Create and attach an internet gateway to the VPC:

```sh
INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway \
  --region ${AWS_REGION} \
  --output text --query 'InternetGateway.InternetGatewayId')

aws ec2 create-tags \
  --region ${AWS_REGION} \
  --resources ${INTERNET_GATEWAY_ID} \
  --tags \
    Key=Name,Value=dev-k8s-training-internet-gateway \
    Key=Environment,Value=dev \
    Key=Application,Value=k8s-training

aws ec2 attach-internet-gateway \
  --region ${AWS_REGION} \
  --internet-gateway-id ${INTERNET_GATEWAY_ID} \
  --vpc-id ${VPC_ID}
```

### Route Tables

Create a route table with internet gateway route for the subnet:

```sh
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --region ${AWS_REGION} \
  --vpc-id ${VPC_ID} \
  --output text --query 'RouteTable.RouteTableId')

aws ec2 create-tags \
  --region ${AWS_REGION} \
  --resources ${ROUTE_TABLE_ID} \
  --tags \
    Key=Name,Value=dev-k8s-training-public-route-table \
    Key=Environment,Value=dev \
    Key=Application,Value=k8s-training

aws ec2 associate-route-table \
  --region ${AWS_REGION} \
  --route-table-id ${ROUTE_TABLE_ID} \
  --subnet-id ${SUBNET_ID}

aws ec2 create-route \
  --region ${AWS_REGION} \
  --route-table-id ${ROUTE_TABLE_ID} \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id ${INTERNET_GATEWAY_ID}
```

### Security Groups (aka Firewall Rules)

Create a security group with all the required port access for the cluster:

```sh
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --region ${AWS_REGION} \
  --group-name dev-k8s-training-sg \
  --description "Kubernetes security group" \
  --vpc-id ${VPC_ID} \
  --output text --query 'GroupId')

aws ec2 create-tags \
  --region ${AWS_REGION} \
  --resources ${SECURITY_GROUP_ID} \
  --tags \
    Key=Name,Value=dev-k8s-training-security-group \
    Key=Environment,Value=dev \
    Key=Application,Value=k8s-training

# Allow all traffic within VPC and pod network
aws ec2 authorize-security-group-ingress \
  --region ${AWS_REGION} \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol all \
  --cidr 10.0.0.0/16

aws ec2 authorize-security-group-ingress \
  --region ${AWS_REGION} \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol all \
  --cidr 10.200.0.0/16

# SSH access
aws ec2 authorize-security-group-ingress \
  --region ${AWS_REGION} \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# Kubernetes API server
aws ec2 authorize-security-group-ingress \
  --region ${AWS_REGION} \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol tcp \
  --port 6443 \
  --cidr 0.0.0.0/0

# HTTPS
aws ec2 authorize-security-group-ingress \
  --region ${AWS_REGION} \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0

# ICMP (ping)
aws ec2 authorize-security-group-ingress \
  --region ${AWS_REGION} \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol icmp \
  --port -1 \
  --cidr 0.0.0.0/0
```

### Kubernetes Public Access - Create a Network Load Balancer

Create a load balancer that will be used as a control plane endpoint:

```sh
LOAD_BALANCER_ARN=$(aws elbv2 create-load-balancer \
  --region ${AWS_REGION} \
  --name dev-k8s-training \
  --subnets ${SUBNET_ID} \
  --scheme internet-facing \
  --type network \
  --tags \
    Key=Name,Value=dev-k8s-training-network-lb \
    Key=Environment,Value=dev \
    Key=Application,Value=k8s-training \
  --output text --query 'LoadBalancers[].LoadBalancerArn')

TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
  --region ${AWS_REGION} \
  --name dev-k8s-training \
  --protocol TCP \
  --port 6443 \
  --vpc-id ${VPC_ID} \
  --target-type ip \
  --tags \
    Key=Name,Value=dev-k8s-training-target-group \
    Key=Environment,Value=dev \
    Key=Application,Value=k8s-training \
  --output text --query 'TargetGroups[].TargetGroupArn')

# Register controller nodes (10.0.1.10, 10.0.1.11, 10.0.1.12)
aws elbv2 register-targets \
  --region ${AWS_REGION} \
  --target-group-arn ${TARGET_GROUP_ARN} \
  --targets Id=10.0.1.10 Id=10.0.1.11 Id=10.0.1.12

aws elbv2 create-listener \
  --region ${AWS_REGION} \
  --load-balancer-arn ${LOAD_BALANCER_ARN} \
  --protocol TCP \
  --port 443 \
  --default-actions Type=forward,TargetGroupArn=${TARGET_GROUP_ARN} \
  --tags \
    Key=Name,Value=dev-k8s-training-lb-listener \
    Key=Environment,Value=dev \
    Key=Application,Value=k8s-training \
  --output text --query 'Listeners[].ListenerArn'
```

Get the load balancer DNS name:

```sh
KUBERNETES_PUBLIC_ADDRESS=$(aws elbv2 describe-load-balancers \
  --region ${AWS_REGION} \
  --load-balancer-arns ${LOAD_BALANCER_ARN} \
  --output text --query 'LoadBalancers[].DNSName')

echo "Kubernetes API endpoint: ${KUBERNETES_PUBLIC_ADDRESS}"
```

## Compute Instances

### Instance Image

Find the latest Ubuntu 20.04 AMI:

```sh
IMAGE_ID=$(aws ec2 describe-images \
  --region ${AWS_REGION} \
  --owners 099720109477 \
  --output json \
  --filters \
    'Name=root-device-type,Values=ebs' \
    'Name=architecture,Values=x86_64' \
    'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server*' \
  | jq -r '.Images|sort_by(.Name)[-1]|.ImageId')

echo "Using AMI: ${IMAGE_ID}"
```

> **Note**: The Terraform configuration uses a specific AMI ID (`ami-0e83be366243f524a`). You can use that directly or find the latest with the command above.

### SSH Key Pair

Create an SSH key pair for instance access:

```sh
aws ec2 create-key-pair \
  --region ${AWS_REGION} \
  --key-name kubernetes \
  --tag-specifications \
    "ResourceType=key-pair,Tags=[{Key=Name,Value=dev-k8s-training-kubernetes-key},{Key=Environment,Value=dev},{Key=Application,Value=k8s-training}]" \
  --output text --query 'KeyMaterial' > kubernetes.id_rsa

chmod 600 kubernetes.id_rsa
```

### Kubernetes Controllers

Create 3 controller nodes using `t3.micro` instances.

> **Important**: Controller IPs are `10.0.1.10`, `10.0.1.11`, `10.0.1.12` (not `10.0.1.10-12`) to match Terraform.

```sh
for i in 0 1 2; do
  # Calculate IP (10.0.1.10, 10.0.1.11, 10.0.1.12)
  ip_suffix=$((10 + i))
  
  instance_id=$(aws ec2 run-instances \
    --region ${AWS_REGION} \
    --associate-public-ip-address \
    --image-id ${IMAGE_ID} \
    --count 1 \
    --key-name kubernetes \
    --security-group-ids ${SECURITY_GROUP_ID} \
    --instance-type t3.micro \
    --private-ip-address 10.0.1.${ip_suffix} \
    --user-data "name=controller-${i}" \
    --subnet-id ${SUBNET_ID} \
    --block-device-mappings='[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":50},"NoDevice":""}]' \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=dev-k8s-training-controller-${i}},{Key=Environment,Value=dev},{Key=Application,Value=k8s-training}]" \
    --output text --query 'Instances[].InstanceId')
  
  # Disable source/destination check (required for pod networking)
  aws ec2 modify-instance-attribute \
    --region ${AWS_REGION} \
    --instance-id ${instance_id} \
    --no-source-dest-check
  
  echo "controller-${i} created (${instance_id}) at 10.0.1.${ip_suffix}"
done
```

### Kubernetes Workers

Create 3 worker nodes using `t3.micro` instances.

> **Important**: Worker IPs are `10.0.1.20`, `10.0.1.21`, `10.0.1.22` (not `10.0.1.20-22`) to match Terraform.

```sh
for i in 0 1 2; do
  # Calculate IP (10.0.1.20, 10.0.1.21, 10.0.1.22)
  ip_suffix=$((20 + i))
  
  instance_id=$(aws ec2 run-instances \
    --region ${AWS_REGION} \
    --associate-public-ip-address \
    --image-id ${IMAGE_ID} \
    --count 1 \
    --key-name kubernetes \
    --security-group-ids ${SECURITY_GROUP_ID} \
    --instance-type t3.micro \
    --private-ip-address 10.0.1.${ip_suffix} \
    --user-data "name=worker-${i}|pod-cidr=10.200.${i}.0/24" \
    --subnet-id ${SUBNET_ID} \
    --block-device-mappings='[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":50},"NoDevice":""}]' \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=dev-k8s-training-worker-${i}},{Key=Environment,Value=dev},{Key=Application,Value=k8s-training}]" \
    --output text --query 'Instances[].InstanceId')
  
  # Disable source/destination check (required for pod networking)
  aws ec2 modify-instance-attribute \
    --region ${AWS_REGION} \
    --instance-id ${instance_id} \
    --no-source-dest-check
  
  echo "worker-${i} created (${instance_id}) at 10.0.1.${ip_suffix}"
done
```

---

## Summary

Whether you chose Terraform or AWS CLI, you now have:

- ✅ VPC with subnet and internet gateway
- ✅ Security group with appropriate firewall rules
- ✅ Network Load Balancer for HA control plane access
- ✅ SSH key pair for instance access
- ✅ 3 controller nodes (t3.micro)
- ✅ 3 worker nodes (t3.micro) with pod network CIDRs
- ✅ Source/destination check disabled on all nodes (required for pod networking)

Next: [Certificate Authority](04-certificate-authority.md)
