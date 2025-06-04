#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEMPLATE="$SCRIPT_DIR/template.yml.j2"
VARS="$SCRIPT_DIR/../vars.yml"
OUTDIR="$SCRIPT_DIR/../cloud-init"

# Ensure output directory exists
mkdir -p "$OUTDIR"

# Extract global values
network_interface=$(yq -r '.network_interface' "$VARS")
ansible_user=$(yq -r '.ansible_user' "$VARS")

# Join all ssh_key lines into a single string (for multi-line keys)
ssh_key=$(yq -r '.ssh_key | join("\n")' "$VARS")

render_vm_group() {
  local group_name=$1
  local vm_count=$(yq -r ".${group_name} | length" "$VARS")
  for ((i=0; i<vm_count; i++)); do
    name=$(yq -r ".${group_name}[${i}].name" "$VARS")
    cpus=$(yq -r ".${group_name}[${i}].cpus" "$VARS")
    memory=$(yq -r ".${group_name}[${i}].memory" "$VARS")
    disk=$(yq -r ".${group_name}[${i}].disk" "$VARS")

    # Create a temporary yml file for this VM
    tmpfile=$(mktemp /tmp/cloudinit.XXXXXX.yml)
    cat > "$tmpfile" <<EOF
hostname: $name
user: $ansible_user
ssh_key: $ssh_key
cpus: $cpus
memory: $memory
disk: $disk
network_interface: $network_interface
EOF

    # Render the template for this VM
    jinja2 "$TEMPLATE" "$tmpfile" -o "$OUTDIR/$name.yml"
    rm -f "$tmpfile"

    echo "Rendered $OUTDIR/$name.yml"
  done
}

# Process both master_vms and worker_vms
declare -a vm_groups=("master_vms" "worker_vms")
for group in "${vm_groups[@]}"; do
  render_vm_group "$group"
done 