# RKE2 Kubernetes Cluster Automation

This project is for deploying RKE2 (Rancher Kubernetes Engine 2) clusters on local virtual machines using Multipass, cloud-init, and Ansible.

## 🚀 Overview

This project automates the deployment of a complete Kubernetes cluster using RKE2, with one master node and multiple worker nodes. It utilizes:

- **Multipass**: For lightweight VM management on macOS/Linux
- **cloud-init**: For initial VM configuration and setup
- **Ansible**: For orchestrating the RKE2 installation and configuration
- **Make**: For simplifying common operations

## 📋 Prerequisites

The project will check and install these dependencies if needed:
- Multipass
- Ansible
- yq
- jq
- jinja2

## 📁 Project Structure

```
├── Makefile                # Automation commands
├── playbook.yml            # Main Ansible playbook
├── README.md               # This documentation(main)
├── vars.yml.example        # Example variables file
├── cloud-init/             # Folder contain VM specs *.yml files (auto-generated)
│   ├── generate.sh         # Script to generate VM specs files
├── templates/              # Jinja2 templates for dynamic config
│   ├── inventory.yml.j2    # Inventory template
│   ├── cloud-init.yml.j2   # Cloud-init template
│   └── vms.yml.j2          # VM specs template
└── roles/                  # Ansible roles
    ├── rke2-master/        # Master node setup
    │   └── tasks/
    │       ├── main.yml
    │       └── addons/
    │           └── *.yml   # RKE2 addons
    └── rke2-worker/        # Worker node setup
        └── tasks/
            └── main.yml
```

These files will be _auto-generated_ by Make with values from `vars.yml` and from `multipass` VMs

```
├── inventory.yml           # Ansible inventory for cluster nodes
├── vms.yml                 # VM specifications
├── cloud-init/             # Initial node configurations and scripts
|   └── *.yml               # Master node cloud-init config
└── kube-config             # Kubeconfig for cluster access
```

## 🔧 Sample Cluster Configuration

- **Master Node**: 
  - 4 CPUs, 4GB RAM, 20GB storage
  - Hosts the Kubernetes control plane
  - Configured with proper TLS SAN settings
  
- **Worker Nodes (3)**:
  - Each with 2 CPUs, 2GB RAM, 15GB storage
  - Run containerized applications
  - Automatically join the cluster

## 🛠️ Usage

### Setting Up the Variables

Copy the `vars.yml.example` file to `vars.yml` and edit with your own values

- `network_interface`: Adjust the network interface as needed, this must be the interface that [configured as local bridged network in Multipass](https://documentation.ubuntu.com/multipass/en/latest/reference/settings/local-bridged-network/)
- `ansible_user`: Adjust the user as needed
- `ansible_ssh_private_key_file`: Adjust the private key file path
- `authorized_keys`: Adjust with public key content, which match the private key configured above

### Setting Up the Cluster

After create the `vars.yml` file you are now ready to create VMs with Multipass and setup RKE2 cluster

```bash
# Deploy the complete cluster
make all

# Check VM status
make status

# Access a VM shell
make shell
```

The deployment process will:
1. Check and install dependencies if needed
2. Create (`vms.yml`, `cloud-init/*.yml`) config files
3. Launch the virtual machines with Multipass
4. Configure networking and host connections
5. Create `inventory.yml` file
6. Install RKE2 on master and worker nodes
7. Verify node status with well-formatted output

### Managing the Cluster

```bash
# Update the inventory with current IPs
make update-inventory

# Run Ansible playbook separately
make run-ansible

# Connect to master node via SSH (interactive selection)
make ssh-master

# Connect to a worker node via SSH (interactive selection)
make ssh-worker

# Destroy all VMs
make destroy

# Purge deleted VMs
make purge
```

## 📊 Cluster Details

- Uses SSH key authentication for all nodes
- Automatically configures networking between nodes
- Sets up kubeconfig for easy cluster management
- Configures proper node labels for workload distribution
- Performs automatic node health checks after deployment
- Displays well-formatted cluster status after setup completes

## 🔒 Security Features

- Swap disabled on all nodes for Kubernetes compatibility
- User `ansible_user` with sudo privileges for management
- SSH key-based authentication

## 💡 How It Works

1. **Multipass VMs**: Created with defined resources via cloud-init configuration
2. **Networking**: Automatically configured to use the same network interface
3. **RKE2 Installation**: Master node first, then workers join using node token
4. **Kubeconfig**: Generated and configured for remote access
5. **Health Checks**: Automatic verification of node readiness
6. **TLS Configuration**: Master node properly configured with correct TLS SAN entries for secure access
7. **Output Formatting**: Clear, well-organized status displays with proper column alignment
8. **System Summary**: Consolidated metrics about nodes and pods

## 🔍 Cluster Health Checks

After deployment, the system automatically verifies that all nodes reach the `Ready` state. The verification process:

- Checks node status every 10 seconds for up to 5 minutes
- Provides a detailed status report of all nodes with clear formatting
- Shows warnings if any nodes fail to reach the `Ready` state
- Displays overall cluster status including system pods

The output is formatted for better readability with clear columns and alignment:

```
NODE                STATUS    ROLES           INTERNAL-IP     VERSION          
----                ------    -----           -----------     -------          
k8s-master-01       Ready     control-plane   192.168.50.xxx  v1.32.5+rke2r1
k8s-worker-01       Ready     worker          192.168.50.xxx  v1.32.5+rke2r1
k8s-worker-02       Ready     worker          192.168.50.xxx  v1.32.5+rke2r1  
k8s-worker-03       Ready     worker          192.168.50.xxx  v1.32.5+rke2r1  
```

This ensures your cluster is fully functional before you start using it.

## 💡 For Cloud Server Setup

If you already have VMs running on cloud providers (AWS, GCP, Azure, etc.) with public IP addresses and SSH key authentication configured, you can skip the Multipass VM creation and directly set up RKE2 on your existing infrastructure.

### Prerequisites for Cloud Setup

- VMs with Ubuntu 22.04 or later
- SSH key authentication configured
- Public IP addresses accessible from your machine
- User with sudo privileges on all VMs

### Manual Setup Steps

1. Create `inventory.yml` manually with correct value for:
    - masters, workers ip addresses
    - ansible username
    - private key file path
2. Execute one of the following command to set up RKE2 on your VMs:
    - Using Make: `make run-ansible`
    - Directy run ansible: `ansible-playbook -i inventory.yml playbook.yml` 
