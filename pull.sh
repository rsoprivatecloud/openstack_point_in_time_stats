#!/bin/bash

arr_total_ram=($(mysql -BNne "select memory_mb from compute_nodes where deleted = 0" nova))
arr_free_ram=($(mysql -BNne "select free_ram_mb from compute_nodes where deleted = 0" nova))
arr_total_cpu=($(mysql -BNne "select vcpus from compute_nodes where deleted = 0" nova))
arr_used_vcpu=($(mysql -BNne "select vcpus_used from compute_nodes where deleted = 0" nova))
arr_total_disk=($(mysql -BNne "select local_gb from compute_nodes where deleted = 0" nova))
arr_used_disk=($(mysql -BNne "select local_gb_used from compute_nodes where deleted = 0" nova))
arr_allocated_disk=($(mysql -BNne "select free_disk_gb from compute_nodes where deleted = 0" nova))
arr_total_vms=($(mysql -BNne "select running_vms from compute_nodes where deleted = 0" nova))

compute_nodes=${#arr_total_ram[@]}

total_ram_gb=$(($(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_total_ram[@]}") / 1024))
used_ram_gb=$((total_ram_gb - $(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_free_ram[@]}") / 1024))
average_ram_gb=$((used_ram_gb / compute_nodes))
perc_ram=$((used_ram_gb * 100 / total_ram_gb))

total_cpu=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_total_cpu[@]}")
total_vcpu=$((total_cpu * $(awk -F= '/^cpu_allocation_ratio/ {print $2}' /etc/nova/nova.conf | cut -f1 -d.)))
used_vcpu=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_used_vcpu[@]}")
average_vcpu=$((used_vcpu / compute_nodes))
perc_cpu=$((used_vcpu * 100 / total_vcpu))

total_disk_tb=$(($(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_total_disk[@]}") / 1024))
used_disk_tb=$(($(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_used_disk[@]}") / 1024))
allocated_disk_tb=$(($(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_allocated_disk[@]}") / 1024))
average_used_disk_tb=$((used_disk_tb / compute_nodes))
perc_disk=$((used_disk_tb * 100 / total_disk_tb))
available_disk_tb=$((total_disk_tb - allocated_disk_tb / $(awk -F= '/^disk_allocation_ratio/ {print $2}' /etc/nova/nova.conf | cut -f1 -d.)))

total_vms=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${arr_total_vms[@]}")
average_vms=$((total_vms / compute_nodes))

cat << EOF
Total Compute Nodes: ${compute_nodes}

RAM:
  Total:       ${total_ram_gb}GB
  Used:        ${used_ram_gb}GB
  Used %:      ${perc_ram}%
  Avg on Host: ${average_ram_gb}GB

Disk:
  Total:       ${total_disk_tb}TB  
  Used:        ${used_disk_tb}TB
  Used %:      ${perc_disk}%
  Avg on Host: ${average_used_disk_tb}TB
  Allocated:   ${allocated_disk_tb}TB
  Available:   ${available_disk_tb}TB

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
