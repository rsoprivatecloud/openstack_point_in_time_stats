#!/bin/bash
#
#  https://github.com/rsoprivatecloud/openstack_point_in_time_stats/
#
#  A Sam Yaple joint (feat. The Reverend)
# 
#
# Here is what problems will arise for this
# * REQUIRES package 'dc'
# * Defaults to overcommit ratios of 1.0 without warning if actual value cannot be found
# * mysql seperate queries. This can lead to things changing between queiries. It is not worth the time to fix this IMO
#

function initial_query () {
	arr_hostname=($(mysql -BNne "select hypervisor_hostname from compute_nodes where deleted = 0" nova))
	arr_total_ram=($(mysql -BNne "select memory_mb from compute_nodes where deleted = 0" nova))
	arr_used_ram=($(mysql -BNne "select memory_mb_used from compute_nodes where deleted = 0" nova))
	arr_total_cpu=($(mysql -BNne "select vcpus from compute_nodes where deleted = 0" nova))
	arr_used_vcpu=($(mysql -BNne "select vcpus_used from compute_nodes where deleted = 0" nova))
	arr_total_disk=($(mysql -BNne "select local_gb from compute_nodes where deleted = 0" nova))
	arr_used_disk=($(mysql -BNne "select local_gb_used from compute_nodes where deleted = 0" nova))
	arr_total_vms=($(mysql -BNne "select running_vms from compute_nodes where deleted = 0" nova))
}

function get_ratio () {
	TYPE=$1
	RET=$(grep ^${TYPE}_allocation_ratio /etc/nova/nova.conf 2>/dev/null | cut -d= -f2)

	if [ ! "$RET"]; then
		RET=$( lxc-attach -n `lxc-ls | grep nova_scheduler 2> /dev/null| tail -1` -- grep ^${TYPE}_allocation_ratio /etc/nova/nova.conf 2> /dev/null | cut -d= -f2)
		if [ ! "$RET" ]; then
			echo 1.0
		fi
	fi
	echo $RET
}

function set_totals () {
	compute_nodes=${#arr_hostname[@]}

	phys_ram_gb=$(($(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_total_ram[@]}") / 1024))
	virt_ram_gb=$( echo $phys_ram_gb $ram_alloc_ratio \* p | dc | cut -d. -f1)
	used_ram_gb=$(($(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_used_ram[@]}") / 1024))
	free_ram_gb=$( echo $virt_ram_gb $used_ram_gb - p | dc )
	average_ram_gb=$((used_ram_gb / compute_nodes))
	perc_ram=$((used_ram_gb * 100 / phys_ram_gb))

	total_disk_gb=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_total_disk[@]}")
	virt_disk_gb=$( echo $total_disk_gb $disk_alloc_ratio \* p | dc | cut -d. -f1 )
	used_disk_gb=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_used_disk[@]}")
	average_used_disk_gb=$((used_disk_gb / compute_nodes))
	perc_disk=$((used_disk_gb * 100 / virt_disk_gb))
	available_disk_gb=$(echo 1 k $total_disk_gb $disk_alloc_ratio \* $used_disk_gb - p | dc | cut -d. -f1)

	total_cpu=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_total_cpu[@]}")
	total_vcpu=$(echo $total_cpu $cpu_alloc_ratio \* p | dc )
	used_vcpu=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_used_vcpu[@]}")
	average_vcpu=$((used_vcpu / compute_nodes))
	perc_cpu=$(echo 1 k $used_vcpu $total_vcpu \/ 100 \* p | dc | cut -d. -f1)

	total_vms=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_total_vms[@]}")
	average_vms=$((total_vms / compute_nodes))
}

function set_node_totals () {
	node_name=${arr_hostname[$i]}

	node_phys_ram_gb=$((arr_total_ram[i] / 1024))
	node_virt_ram_gb=$( echo $node_phys_ram_gb $ram_alloc_ratio \* p | dc | cut -d. -f1)
	node_used_ram_gb=$(( arr_used_ram[i] / 1024))
	node_free_ram_gb=$(( node_virt_ram_gb - node_used_ram_gb ))
	node_perc_ram=$((node_used_ram_gb * 100 / node_virt_ram_gb ))

	node_phys_disk_gb="${arr_total_disk[$i]}"
	node_virt_disk_gb=$( echo $node_phys_disk_gb $disk_alloc_ratio \* p | dc | cut -d. -f1)

	node_used_disk_gb="${arr_used_disk[$i]}"
	node_perc_disk=$(echo 2 k $node_used_disk_gb $node_virt_disk_gb \/ 100 \* 0 k p | dc | cut -d. -f1)
	node_available_disk_gb=$( echo $node_virt_disk_gb $node_used_disk_gb - p | dc | cut -d. -f1)

	node_cpu="${arr_total_cpu[$i]}"

	node_vcpu=$(echo 1 k $node_cpu $cpu_alloc_ratio \* p | dc | cut -d. -f1)
	node_used_vcpu="${arr_used_vcpu[$i]}"
	node_perc_cpu=$( echo $node_used_vcpu 100 \* $node_vcpu \/ p | dc | cut -d. -f1 )

	node_vms=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_total_vms[$i]}")
}

function print_node () {
        cat << EOF
=====Compute Summary=====

Hostname       : ${node_name}

RAM:
  Phys Size    : ${node_phys_ram_gb}GB
  Virt Size    : ${node_virt_ram_gb}GB ($ram_alloc_ratio ratio)
  Used         : ${node_used_ram_gb}GB (${node_perc_ram}%)
  Free         : ${node_free_ram_gb}GB

Disk:
  Phys Size    : ${node_phys_disk_gb}GB
  Virt Size    : ${node_virt_disk_gb}GB ($disk_alloc_ratio ratio)
  Allocated    : ${node_used_disk_gb}GB ($node_perc_disk%)
  Available    : ${node_available_disk_gb}GB  

CPU:
  Phys Threads : ${node_cpu}
  Virt CPUs    : ${node_vcpu} ($cpu_alloc_ratio ratio)
  Used vCPUs   : ${node_used_vcpu} (${node_perc_cpu}%)
  Free vCPUs   : $( echo $node_vcpu $node_used_vcpu - p | dc | cut -d. -f1 )

Instances      : ${node_vms}

EOF
}

function print_summary () {
	cat << EOF
=====Summary=====

Total Compute Nodes: ${compute_nodes}

RAM:
  Phys Total   : ${phys_ram_gb}GB
  Virt Total   : ${virt_ram_gb}GB ($ram_alloc_ratio ratio)
  Allocated    : ${used_ram_gb}GB (${perc_ram}%)
  Avg per Host : ${average_ram_gb}GB
  Available    : ${free_ram_gb}GB

Disk:
  Phys Total   : ${total_disk_gb}GB  
  Virt Total   : ${virt_disk_gb}GB ($disk_alloc_ratio ratio)
  Allocated    : ${used_disk_gb}GB (${perc_disk}%)
  Avg per Host : ${average_used_disk_gb}GB
  Available    : ${available_disk_gb}GB 

CPU:
  Phys Threads : ${total_cpu}
  Total vCPUs  : ${total_vcpu} ($cpu_alloc_ratio ratio)
  Used vCPUs   : ${used_vcpu} (${perc_cpu}%)
  Avg per Host : ${average_vcpu}

Instances:
  Total        : ${total_vms}
  Avg on Host  : ${average_vms}
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

function verify_prereqs () {
	which dc > /dev/null 2>&1
	[ $? -ne 0 ] && echo "DC Required.  apt-get install dc" && exit
}

verify_prereqs

ram_alloc_ratio=$(get_ratio ram)
cpu_alloc_ratio=$(get_ratio cpu)
disk_alloc_ratio=$(get_ratio disk)

initial_query
print_nodes
print_totals

exit 0
