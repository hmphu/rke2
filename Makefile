YQ = yq

.PHONY: all check-deps launch-vms destroy purge status shell update-inventory ssh-master ssh-worker create-vms

all: check-deps launch-vms update-inventory run-ansible get-kube-config

check-deps:
	@echo "🔍 Checking dependencies..."
	@if ! command -v yq >/dev/null 2>&1; then \
		echo "⚠️ yq not found."; \
		if [ "$$(uname)" = "Darwin" ]; then \
			echo "➡️ Installing yq via Homebrew..."; \
			brew install yq; \
		else \
			echo "➡️ Installing yq via apt..."; \
			sudo apt update && sudo apt install -y yq; \
		fi; \
	else \
		echo "✅ yq is installed."; \
	fi

	@if ! command -v jq >/dev/null 2>&1; then \
		echo "⚠️ jq not found."; \
		if [ "$$(uname)" = "Darwin" ]; then \
			echo "➡️ Installing jq via Homebrew..."; \
			brew install jq; \
		else \
			echo "➡️ Installing jq via apt..."; \
			sudo apt update && sudo apt install -y jq; \
		fi; \
	else \
		echo "✅ jq is installed."; \
	fi

	@if ! command -v multipass >/dev/null 2>&1; then \
		echo "⚠️ multipass not found."; \
		if [ "$$(uname)" = "Darwin" ]; then \
			echo "➡️ Installing multipass via Homebrew..."; \
			brew install --cask multipass; \
		else \
			echo "➡️ Installing multipass via apt..."; \
			sudo snap install multipass --classic; \
		fi; \
	else \
		echo "✅ multipass is installed."; \
	fi

	@if ! command -v ansible >/dev/null 2>&1; then \
		echo "⚠️ ansible not found."; \
		if [ "$$(uname)" = "Darwin" ]; then \
			echo "➡️ Installing ansible via Homebrew..."; \
			brew install ansible; \
		else \
			echo "➡️ Installing ansible via apt..."; \
			sudo apt update && sudo apt install -y ansible; \
		fi; \
	else \
		echo "✅ ansible is installed."; \
	fi
	
	@if ! command -v jinja2 >/dev/null 2>&1; then \
		echo "⚠️ jinja2 not found."; \
		if [ "$$(uname)" = "Darwin" ]; then \
			echo "➡️ Installing jinja2 via Homebrew..."; \
			brew install jinja2-cli; \
		else \
			echo "➡️ Installing jinja2 via pip..."; \
			sudo pip3 install jinja2-cli; \
		fi; \
	else \
		echo "✅ jinja2 is installed."; \
	fi

create-cloud-init-configs:
	@echo "🔨 Rendering cloud-init configs using vars.yml..."
	@if [ "$$(uname)" = "Darwin" ] || [ "$$(uname)" = "Linux" ]; then \
		./cloud-init/generate.sh > /dev/null 2>&1; \
	else \
		echo "⚠️ Windows detected. Please run cloud-init/generate.sh manually or use WSL."; \
		exit 1; \
	fi
	@echo "✅ Rendered cloud-init/k8s-master-01.yaml using vars.yml"

create-vms-configs: create-cloud-init-configs
	@echo "🔨 Rendering vms.yml from templates/vms.yml.j2 using vars.yml..."
	@if [ "$$(uname)" = "Darwin" ] || [ "$$(uname)" = "Linux" ]; then \
		jinja2 templates/vms.yml.j2 vars.yml -o vms.yml > /dev/null 2>&1; \
	else \
		echo "⚠️ Windows detected. Please run jinja2 command manually or use WSL."; \
		exit 1; \
	fi
	@echo "✅ Rendered vms.yml from templates/vms.yml.j2 using vars.yml"

launch-vms: create-vms-configs
	@$(YQ) -r '.vms[] | .name' vms.yml | while read name; do \
		cpus=$$($(YQ) -r ".vms[] | select(.name==\"$$name\") | .cpus" vms.yml); \
		mem=$$($(YQ) -r ".vms[] | select(.name==\"$$name\") | .memory" vms.yml); \
		disk=$$($(YQ) -r ".vms[] | select(.name==\"$$name\") | .disk" vms.yml); \
		cloud_init=$$($(YQ) -r ".vms[] | select(.name==\"$$name\") | .cloud_init" vms.yml); \
		network=$$($(YQ) -r ".vms[] | select(.name==\"$$name\") | .network // \"\"" vms.yml); \
		if multipass info "$$name" >/dev/null 2>&1; then \
			echo "⚠️ VM $$name already exists. Skipping launch for $$name."; \
			continue; \
		fi; \
		echo "🚀 Launching $$name with $$cpus CPU, $$mem RAM, $$disk disk"; \
		if [ -n "$$network" ]; then \
			echo "🌐 Using network interface: $$network"; \
			multipass launch --name "$$name" --cpus "$$cpus" --memory "$$mem" --disk "$$disk" --cloud-init "$$cloud_init" --network "$$network"; \
		else \
			multipass launch --name "$$name" --cpus "$$cpus" --memory "$$mem" --disk "$$disk" --cloud-init "$$cloud_init"; \
		fi; \
	done

destroy: check-deps
	@$(YQ) -r '.vms[] | .name' vms.yml | while read name; do \
		echo "🗑️ Attempting to delete $$name..."; \
		if multipass delete $$name 2>/dev/null; then \
			echo "✅ Deleted $$name"; \
		else \
			echo "ℹ️ $$name was already deleted or doesn't exist."; \
		fi; \
	done

purge: destroy
	@multipass purge > /dev/null 2>&1 || true
	@echo "🧹 Purge completed: all deleted instances have been cleaned up."

status:
	multipass list

shell:
	@echo "🔎 Available instances:"
	@multipass list | awk 'NR>1 {print $$1}'
	@read -p "Enter instance name to shell into: " name; \
	multipass shell $$name

create-inventory-file:
	@echo "🔨 Rendering inventory.yml from templates/inventory.yml.j2 using vars.yml..."
	@if [ "$$(uname)" = "Darwin" ] || [ "$$(uname)" = "Linux" ]; then \
		jinja2 templates/inventory.yml.j2 vars.yml -o inventory.yml > /dev/null 2>&1; \
	else \
		echo "⚠️ Windows detected. Please run jinja2 command manually or use WSL."; \
		exit 1; \
	fi
	@echo "✅ Rendered inventory.yml from templates/inventory.yml.j2 using vars.yml"

update-inventory: create-inventory-file
	@echo "🛠️ Updating inventory.yml using VM's preferred network IPs..."
	@$(YQ) -r '.vms[] | .name' vms.yml | while read name; do \
		net="$$( $(YQ) -r ".vms[] | select(.name==\"$$name\") | .network" vms.yml )"; \
		if [ "$$(uname)" = "Darwin" ]; then \
			host_if_ip="$$(ipconfig getifaddr $$net || true)"; \
			host_if_broadcast="$$(ipconfig getoption $$net subnet_mask || true)"; \
		else \
			host_if_ip="$$(ip -f inet addr show $$net | grep -Po 'inet \K[\d.]+' | head -n 1 || true)"; \
			host_if_broadcast="$$(ip -f inet addr show $$net | grep -Po 'brd \K[\d.]+' | head -n 1 || true)"; \
		fi; \
		if [ -z "$$host_if_ip" ] || [ -z "$$host_if_broadcast" ]; then echo "❌ Could not find IP for interface $$net on host."; continue; fi; \
		subnet="$$(python3 -c "import ipaddress; import sys; ip = sys.argv[1]; mask = sys.argv[2]; net = ipaddress.IPv4Network(f'{ip}/{mask}', strict=False); print(net)" "$$host_if_ip" "$$host_if_broadcast" 2>/dev/null || echo '')"; \
		allips="$$(multipass info $$name --format json | jq -r ".info.\"$$name\".ipv4[]")"; \
		selected_ip=""; \
		for ip in $$allips; do \
			if python3 -c "import ipaddress; import sys; ip = ipaddress.IPv4Address(sys.argv[1]); subnet = ipaddress.IPv4Network(sys.argv[2], strict=False); exit(0 if ip in subnet else 1)" "$$ip" "$$subnet" 2>/dev/null; then selected_ip="$$ip"; break; fi; \
		done; \
		if [ -n "$$selected_ip" ]; then \
			echo "🔄 Setting $$name IP to $$selected_ip"; \
			if $(YQ) -e ".all.children.masters.hosts.\"$$name\"" inventory.yml >/dev/null 2>&1; then \
				$(YQ) -i ".all.children.masters.hosts.\"$$name\".ansible_host = \"$$selected_ip\"" inventory.yml; \
			fi; \
			if $(YQ) -e ".all.children.workers.hosts.\"$$name\"" inventory.yml >/dev/null 2>&1; then \
				$(YQ) -i ".all.children.workers.hosts.\"$$name\".ansible_host = \"$$selected_ip\"" inventory.yml; \
			fi; \
		else \
			echo "⚠️ No matching IP for $$name in subnet $$subnet.x"; \
		fi; \
	done
	@echo "✅ inventory.yml has been updated."
	@echo "💾 Verifying inventory.yml changes have been saved properly..."
	@sync
	@sleep 1

list-interfaces:
	multipass networks

run-ansible:
	@echo "🔄 Running Ansible playbook..."
	ansible-playbook -i inventory.yml playbook.yml
	@echo "✅ Ansible playbook execution completed."

ssh-master:
	@echo "🔎 Available master nodes:"
	@$(YQ) -r '.all.children.masters.hosts | keys | .[]' inventory.yml | nl
	@read -p "Enter the master number to connect to: " master_num; \
	master_name=$$($(YQ) -r '.all.children.masters.hosts | keys | .['$$((master_num-1))']' inventory.yml); \
	master_ip=$$($(YQ) -r '.all.children.masters.hosts."'$$master_name'".ansible_host' inventory.yml); \
	ssh_key=$$($(YQ) -r '.all.vars.ansible_ssh_private_key_file' inventory.yml); \
	ssh_user=$$($(YQ) -r '.all.vars.ansible_user' inventory.yml); \
	echo "📝 SSH Command: ssh -i $$ssh_key $$ssh_user@$$master_ip"; \
	ssh -i $$ssh_key $$ssh_user@$$master_ip

ssh-worker:
	@echo "🔎 Available worker nodes:"
	@$(YQ) -r '.all.children.workers.hosts | keys | .[]' inventory.yml | nl
	@read -p "Enter the worker number to connect to: " worker_num; \
	worker_name=$$($(YQ) -r '.all.children.workers.hosts | keys | .['$$((worker_num-1))']' inventory.yml); \
	worker_ip=$$($(YQ) -r '.all.children.workers.hosts."'$$worker_name'".ansible_host' inventory.yml); \
	ssh_key=$$($(YQ) -r '.all.vars.ansible_ssh_private_key_file' inventory.yml); \
	ssh_user=$$($(YQ) -r '.all.vars.ansible_user' inventory.yml); \
	echo "📝 SSH Command: ssh -i $$ssh_key $$ssh_user@$$worker_ip"; \
	ssh -i $$ssh_key $$ssh_user@$$worker_ip

get-kube-config:
	@echo "🔄 Getting kube-config from first master..."
	@master_name=$$($(YQ) -r '.all.children.masters.hosts | keys | .[0]' inventory.yml); \
	master_ip=$$($(YQ) -r '.all.children.masters.hosts."'$$master_name'".ansible_host' inventory.yml); \
	ssh_key=$$($(YQ) -r '.all.vars.ansible_ssh_private_key_file' inventory.yml); \
	ssh_user=$$($(YQ) -r '.all.vars.ansible_user' inventory.yml); \
	echo "📝 Copying kube-config from $$ssh_user@$$master_ip:/home/$$ssh_user/.kube/config"; \
	if [ "$$(uname)" = "Darwin" ] || [ "$$(uname)" = "Linux" ]; then \
		scp -i $$ssh_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $$ssh_user@$$master_ip:/home/$$ssh_user/.kube/config ./kube-config; \
	else \
		echo "⚠️ Windows detected. Please use WSL or manually run:"; \
		echo "    scp -i $$ssh_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $$ssh_user@$$master_ip:/home/$$ssh_user/.kube/config ./kube-config"; \
		exit 1; \
	fi; \
	echo "✅ Kube-config saved to ./kube-config"

