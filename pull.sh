#!/bin/bash

# Here is what problems will arise for this
# * Rounding errors. Bash math can't into floating point math. bc isn't available
# * mysql seperate queries. This can lead to things changing between queiries. It is not worth the time to fix this IMO
# * TODO: Currently all the disk stats break if they are in the negatives 

function initial_query () {
	arr_hostname=($(mysql -BNne "select hypervisor_hostname from compute_nodes where deleted = 0" nova))
	arr_total_ram=($(mysql -BNne "select memory_mb from compute_nodes where deleted = 0" nova))
	arr_free_ram=($(mysql -BNne "select free_ram_mb from compute_nodes where deleted = 0" nova))
	arr_total_cpu=($(mysql -BNne "select vcpus from compute_nodes where deleted = 0" nova))
	arr_used_vcpu=($(mysql -BNne "select vcpus_used from compute_nodes where deleted = 0" nova))
	arr_total_disk=($(mysql -BNne "select local_gb from compute_nodes where deleted = 0" nova))
	arr_used_disk=($(mysql -BNne "select local_gb_used from compute_nodes where deleted = 0" nova))
	arr_allocated_disk=($(mysql -BNne "select free_disk_gb from compute_nodes where deleted = 0" nova))
	arr_total_vms=($(mysql -BNne "select running_vms from compute_nodes where deleted = 0" nova))
}

function set_totals () {
	compute_nodes=${#arr_hostname[@]}

	total_ram_gb=$(($(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_total_ram[@]}") / 1024))
	used_ram_gb=$((total_ram_gb - $(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_free_ram[@]}") / 1024))
	average_ram_gb=$((used_ram_gb / compute_nodes))
	perc_ram=$((used_ram_gb * 100 / total_ram_gb))

	total_disk_gb=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_total_disk[@]}")
	used_disk_gb=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_used_disk[@]}")
	allocated_disk_gb=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_allocated_disk[@]}")
	average_used_disk_gb=$((used_disk_gb / compute_nodes))
	perc_disk=$((used_disk_gb * 100 / total_disk_gb))
	disk_allocation_ratio=$(awk -F= '/^disk_allocation_ratio/ {print $2}' /etc/nova/nova.conf | cut -f1 -d.)
	[[ -z $disk_allocation_ratio ]] && disk_allocation_ratio=1
	available_disk_gb=$((total_disk_gb - allocated_disk_gb / disk_allocation_ratio))

	total_cpu=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_total_cpu[@]}")
	cpu_overcommit_ratio=$(awk -F= '/^cpu_allocation_ratio/ {print $2}' /etc/nova/nova.conf | cut -f1 -d.)
	[[ -z $cpu_overcommit_ratio ]] && cpu_overcommit_ratio=1
	total_vcpu=$((total_cpu * cpu_overcommit_ratio))
	used_vcpu=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_used_vcpu[@]}")
	average_vcpu=$((used_vcpu / compute_nodes))
	perc_cpu=$((used_vcpu * 100 / total_vcpu))

	total_vms=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_total_vms[@]}")
	average_vms=$((total_vms / compute_nodes))
}

function set_node_totals () {
	node_name=${arr_hostname[$i]}

	node_ram_gb=$((arr_total_ram[i] / 1024))
	node_used_ram_gb=$((node_ram_gb - arr_free_ram[i] / 1024))
	node_perc_ram=$((node_used_ram_gb * 100 / node_ram_gb))

	node_disk_gb="${arr_total_disk[$i]}"
	node_used_disk_gb="${arr_used_disk[$i]}"
	node_allocated_disk_gb="${arr_allocated_disk[$i]}"
	node_perc_disk=$((node_used_disk_gb * 100 / node_disk_gb))
	disk_allocation_ratio=$(awk -F= '/^disk_allocation_ratio/ {print $2}' /etc/nova/nova.conf | cut -f1 -d.)
	[[ -z $disk_allocation_ratio ]] && disk_allocation_ratio=1
	node_available_disk_gb=$((node_disk_gb - node_allocated_disk_gb / disk_allocation_ratio))

	node_cpu="${arr_total_cpu[$i]}"
	cpu_overcommit_ratio=$(awk -F= '/^cpu_allocation_ratio/ {print $2}' /etc/nova/nova.conf | cut -f1 -d.)
	[[ -z $cpu_overcommit_ratio ]] && cpu_overcommit_ratio=1
	node_vcpu=$((node_cpu * cpu_overcommit_ratio))
	node_used_vcpu="${arr_used_vcpu[$i]}"
	node_perc_cpu=$((node_used_vcpu * 100 / node_vcpu))

	node_vms=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_total_vms[$i]}")
}

function print_node () {
        cat << EOF
=====Compute Summary=====

Hostname:      ${node_name}

RAM:
  Ammount:     ${node_ram_gb}GB
  Used:        ${node_used_ram_gb}GB
  Used %:      ${node_perc_ram}%

Disk:
  Size:        ${node_disk_gb}GB
  Used:        ${node_used_disk_gb}GB
  Used %:      ${node_perc_disk}%
  Allocated:   ${node_allocated_disk_gb}GB
  Available:   ${node_available_disk_gb}GB

CPU:
  Phy Threads: ${node_cpu}
  Total vcpus: ${node_vcpu}
  Used vpus:   ${node_used_vcpu}
  Used %:      ${node_perc_cpu}%

Instances:     ${node_vms}

EOF
}

function print_summary () {
	cat << EOF
=====Summary=====

Total Compute Nodes: ${compute_nodes}

RAM:
  Total:       ${total_ram_gb}GB
  Used:        ${used_ram_gb}GB
  Used %:      ${perc_ram}%
  Avg on Host: ${average_ram_gb}GB

Disk:
  Total:       ${total_disk_gb}GB  
  Used:        ${used_disk_gb}GB
  Used %:      ${perc_disk}%
  Avg on Host: ${average_used_disk_gb}GB
  Allocated:   ${allocated_disk_gb}GB
  Available:   ${available_disk_gb}GB

CPU:
  Phy Threads: ${total_cpu}
  Total vcpus: ${total_vcpu}
  Used vpus:   ${used_vcpu}
  Used %:      ${perc_cpu}%
  Avg on Host: ${average_vcpu}

Instances:
  Total:       ${total_vms}
  Avg on Host: ${average_vms}
EOF
}

function print_nodes () {
	for i in $(seq 0 $((${#arr_hostname[@]} - 1))); do
		set_node_totals
		print_node
	done
}

function print_totals () {
	set_totals
	print_summary
}

initial_query
print_nodes
print_totals

exit 0
