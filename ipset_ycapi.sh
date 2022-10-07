#!/bin/bash

#Your ipset name
ipset_name=ycapi
#Your pve fw name
pve_fw_name=PVEFW-926 
ip_set=$pve_fw_name-$ipset_name-v4
hosts_arr=(api.cloud.yandex.net tts.api.cloud.yandex.net)
declare -A hostsA_arr
me=$(basename "$0")

#check host ip
for host in "${hosts_arr[@]}"; do
    ip=$(dig +short $host)
    if [ -z "$ip" ]; then
        logger -t "$me" "IP for '$host' not found"
        continue
    else
        hostsA_arr+=([$host]=$ip)
    fi
done

# make sure the ipset or content of ipset exists
item_obj=`pvesh get /nodes/mgp/qemu/926/firewall/ipset --output-format=json | jq -r '.[] | select (.name=="'$ipset_name'")'`
item_content=`pvesh get /nodes/mgp/qemu/926/firewall/ipset/$ipset_name`

# if item is empty create new ipset
if [ -z "$item_obj" ] || [ -z "$item_content" ] ; then
    # echo "Empty! Create new ipset!"
    logger -t "$me" "Ipset: '$ipset_name' not found! Create new one!"
    pvesh delete /nodes/mgp/qemu/926/firewall/ipset/$ipset_name
    pvesh create /nodes/mgp/qemu/926/firewall/ipset --name $ipset_name
        for key in "${!hostsA_arr[@]}"; do
            ip="${hostsA_arr[$key]}"
            pvesh create /nodes/mgp/qemu/926/firewall/ipset/$ipset_name -cidr $ip -comment $key
        done
sleep 10
fi

# make variables for loop
pvesh_get="pvesh get /nodes/mgp/qemu/926/firewall/ipset/$ipset_name --output-format=json"
ipset_length=`$pvesh_get | jq length`

# check difference between fresh ip and ip in ipset
for key in "${!hostsA_arr[@]}"; do
    ip="${hostsA_arr[$key]}"
    for i in $(seq 0 $(($ipset_length - 1))); do
        comment=`$pvesh_get | jq -r '.['$i'].comment'`
        cidr=`$pvesh_get | jq -r '.['$i'].cidr'`
        if [ "$key" = "$comment" ] && [ "$ip" != "$cidr" ]; then
            # echo $key $comment $ip $cidr;
            logger -t "$me" "Change IP from old '$cidr' to new '$ip' in '$ip_set'!"
            pvesh delete /nodes/mgp/qemu/926/firewall/ipset/$ipset_name/$cidr
            pvesh create /nodes/mgp/qemu/926/firewall/ipset/$ipset_name -cidr $ip -comment $key
        elif [ "$key" = "$comment" ] && [ "$ip" = "$cidr" ]; then
            # echo "Without changes!";
            logger -t "$me" "IP '$ip' already in set '$ip_set'"
        fi
    done
done
