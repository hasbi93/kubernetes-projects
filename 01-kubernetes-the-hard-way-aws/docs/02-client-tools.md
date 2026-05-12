# Installing the Client Tools

In this lab you will install the command line utilities required to complete this tutorial: [cfssl](https://github.com/cloudflare/cfssl), [cfssljson](https://github.com/cloudflare/cfssl), [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl), and optionally [Terraform](https://www.terraform.io/) if you plan to use Infrastructure as Code for provisioning.


## Install CFSSL

The `cfssl` and `cfssljson` command line utilities will be used to provision a [PKI Infrastructure](https://en.wikipedia.org/wiki/Public_key_infrastructure) and generate TLS certificates.

Download and install `cfssl` and `cfssljson`:


### Linux

```
curl -L https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssl_1.6.4_linux_amd64 -o cfssl
curl -L https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssljson_1.6.4_linux_amd64 -o cfssljson
curl -L https://github.com/cloudflare/cfssl/releases/download/v1.6.4/cfssl-certinfo_1.6.4_linux_amd64 -o cfssl-certinfo
```

```
chmod +x cfssl*
```

```
sudo mv cfssl cfssljson /usr/local/bin/
```

### MAC

```
brew install cfssl
```

### Verification

Verify `cfssl` and `cfssljson` version 1.6.4 or higher is installed:

```
../cfssl version
```

> output

```
Version: 1.6.4
Runtime: go1.18
```

## Install kubectl

The `kubectl` command line utility is used to interact with the Kubernetes API Server. Download and install `kubectl` from the official release binaries:

### Linux

```
curl -LO https://dl.k8s.io/release/v1.28.3/bin/linux/amd64/kubectl
```

```
chmod +x kubectl
```

```
sudo mv kubectl /usr/local/bin/
```

### Verification

Verify `kubectl` version 1.28.3 is installed:

```
kubectl version --client
```

> output

```
Client Version: v1.28.3
Kustomize Version: v5.0.4-0.20230601165947-6ce0bf390ce3
```

## Install Terraform (Optional)

If you plan to use Terraform to automate infrastructure provisioning in [Lab 03](03-compute-resources.md), install Terraform:

### Linux

```sh
# Download Terraform
curl -LO https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip

# Unzip and install
unzip terraform_1.7.0_linux_amd64.zip
chmod +x terraform
sudo mv terraform /usr/local/bin/

# Clean up
rm terraform_1.7.0_linux_amd64.zip
```

### macOS

```sh
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

### Verification

Verify Terraform 1.5.0 or higher is installed:

```sh
terraform version
```

> output

```
Terraform v1.7.0
on linux_amd64
```

> **Note**: If you skip Terraform installation, you can still complete the tutorial using the manual AWS CLI approach in Lab 03.

Next: [Provisioning Compute Resources](03-compute-resources.md)
