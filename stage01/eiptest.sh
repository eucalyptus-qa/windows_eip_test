#!/bin/bash

# test sequence
# Elastic IP test
source ../lib/winqa_util.sh
setup_euca2ools;

hostbit=$(host_bitness)
guestbit=$(guest_bitness)
if [ $guestbit -eq "64" ] && [ $hostbit -eq "32" ]; then
    echo "Running 64 bit guest on 32 bit host"
    sleep 10
    exit 0
fi

cp ../etc/id_rsa.proxy ./
chmod 400 ./id_rsa.proxy
winimgs=$(euca-describe-images | grep windows | grep -v deregistered)
if [ -z "$winimgs" ]; then
        echo "ERROR: No windows image is found in Walrus"
        exit 1
fi

if [ $(get_networkmode) = "SYSTEM"  ] || [ $(get_networkmode) = "STATIC" ]; then
      echo "NETWORK MODE is system or static"
      sleep 10
      exit 0
fi


hypervisor=$(describe_hypervisor)
echo "Hypervisor: $hypervisor"

exitCode=0
IFS=$'\n'
for img in $winimgs; do
	if [ -z "$img" ]; then
		continue;
	fi
	IFS=$'\n'
        emi=$(echo $img | cut -f2)
	echo "EMI: $emi"
	
	unset IFS
   	ret=$(euca-describe-instances | grep $emi | grep -E "running")
	if [ -z "$ret" ]; then
		echo "ERROR: Can't find the running instance of $emi"
		exitCode=1
		break;
	fi
        instance=$(echo -e ${ret/*INSTANCE/} | cut -f1 -d ' ')
	if [ -z $instance ]; then
                echo "ERROR: Instance from $emi is null"
		exitCode=1
                break;
        fi
	zone=$(echo -e ${ret/*INSTANCE/} | cut -f10 -d ' ')
        ipaddr=$(echo -e ${ret/*INSTANCE/} | cut -f3 -d ' ')
	keyname=$(echo -e ${ret/*INSTANCE/} | cut -f6 -d ' ')
	
	if [ -z "$zone" ] || [ -z "$ipaddr" ] || [ -z "$keyname" ]; then
		echo "ERROR: Parameter is missing: zone=$zone, ipaddr=$ipaddr, keyname=$keyname"
		exitCode=1
		break;
	fi	
	echo "Zone: $zone, ipaddr: $ipaddr, keyname: $keyname"
    
        keyfile_src=$(whereis_keyfile $keyname)
        if ! ls -la $keyfile_src; then
             echo "ERROR: cannot find the key file from $keyfile_src"
             exitCode=1
             break
        fi       
        keyfile="$keyname.priv"
        cp $keyfile_src $keyfile
        if [ ! -s $keyfile ]; then
                echo "ERROR: can't find the key file $keyfile";
                exitCode=1
                break;
        fi       
	
	ret=$(euca-allocate-address)
	if ! echo $ret | grep "ADDRESS"; then
		echo "ERROR: couldn't allocate an address"
		exitCode=1
		break;
	fi
	newaddr=$(echo $ret | cut -f2 -d ' ')		
	if [ -z "$newaddr" ]; then
		echo "ERROR: couldn't parse the new address"
		exitCode=1
		break;	
	fi
	echo "New elastic ip address: $newaddr"
	sleep 3	
	#if ! euca-describe-addresses | grep "$newaddr" | grep 'available'; then
        if ! euca-describe-addresses | grep "$newaddr"; then
		echo "ERROR: the new address is not in available state"
		exitCode=1
		break;
	fi
	
	ret=$(euca-associate-address -i $instance $newaddr)
	if ! echo $ret | grep $instance | grep $newaddr; then
		echo "ERROR: couldn't associate the address $newaddr with instance $instance"
		exitCode=1
		break;	
	fi
	sleep 3
	ret=$(euca-release-address $ipaddr)
	if ! echo $ret | grep "$ipaddr"; then
		echo "WARNING: previous address $ipaddr couldn't be released"
	fi
	sleep 10
	cmd="euca-get-password -k $keyfile $instance"
        echo $cmd
        passwd=$($cmd)
        if [ -z "$passwd" ]; then
                echo "ERROR: password is null";
		exitCode=1
		break;
	fi

        if ! should_test_guest; then
                echo "[WARNING] We don't perform guest test for this instance";
                sleep 10;
                continue;
        fi

	ret=$(./login.sh -h $newaddr -p $passwd)
	if ! echo $ret | tail -n 1 | grep "SUCCESS"; then
		echo "ERROR: couldn't login using new address $newaddr: ($ret)"
		exitCode=1
		break;
	fi

	ret=$(./rdp.sh)
	if ! echo $ret | tail -n 1 | grep "SUCCESS"; then
		echo "ERROR: rdp port scan failed ($ret)";
		ret=$(./eucalog.sh)
                echo "WINDOWS INSTANCE LOG: $ret"
		exitCode=1
		break;
	fi
	echo "Passed Elastic IP test"
done
exit "$exitCode"
