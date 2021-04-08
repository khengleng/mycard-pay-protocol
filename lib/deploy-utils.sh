# the current working dir is set to the project home dir from calling script
OZ="$(pwd)/node_modules/.bin/oz"
TRUFFLE="$(pwd)/node_modules/.bin/truffle"

if [ -z "$(which jq)" ]; then
  echo "The 'jq' library is not installed. Please use brew (or your favorite pkg manager) to install 'jq'"
  exit 1
fi

p() {
  echo "echo \"$@\""
}

defaultAccount() {
  NETWORK=$1
  output=$(TRUFFLE exec lib/default-account.js --network=$NETWORK)
  if [[ "$output" =~ .*("0x"[0-9a-fA-F]{40}).* ]]; then
    echo ${BASH_REMATCH[1]}
  fi
}

deploy() {
  NETWORK=$1
  CONTRACT_NAME=$2
  ARGS="$3"
  $OZ add $CONTRACT_NAME &>/dev/null
  $OZ push -n $NETWORK &>/dev/null
  output=$(OZ deploy --network $NETWORK --kind upgradeable --no-interactive $CONTRACT_NAME $ARGS)
  ## test for address of contract instance
  if [[ "$output" =~ .*("0x"[0-9a-fA-F]{40})$ ]]; then
    echo ${BASH_REMATCH[1]}
  fi
}

## $1 = Network
## $2 = Contract Name
## $3 = Instance address (proxy)
getImplementationAddress() {
  NETWORK=$1
  NAME=$2
  INSTANCE=$3
  conf=''
  if [ "$NETWORK" == "sokol" ]; then
    conf="$(cat ./.openzeppelin/*-77.json)"
  elif [ "$NETWORK" == "xdai"]; then
    conf="$(cat ./.openzeppelin/*-100.json)"
  else
    echo "Don't know how to handle network ${NETWORK}"
    exit 1
  fi
  echo "$conf" | jq -r ".proxies | with_entries(if (.key|test(\"$NAME\")) then ( {key: .key, value: .value } ) else empty end) | .[] | .[] | select(.address==\"$INSTANCE\").implementation"
}

verifyImplementation() {
  NETWORK=$1
  CONTRACT_NAME=$2
  ADDRESS=$3
  $TRUFFLE run blockscout "${CONTRACT_NAME}@${ADDRESS}" --network $NETWORK --license UNLICENSED
}

verifyProxy() {
  NETWORK=$1
  ADDRESS=$2
  if [ "$NETWORK" == "sokol" ]; then
    url="https://blockscout.com/poa/sokol/verify_smart_contract/contract_verifications"
  elif [ "$NETWORK" == "xdai"]; then
    url="https://blockscout.com/xdai/mainnet/verify_smart_contract/contract_verifications"
  else
    echo "Don't know how to handle network ${NETWORK}"
    exit 1
  fi

  # This is the magic AdminUpgradeabilityProxy code that is used by all OZ upgradeable contracts
  curl -X POST --data \
    "smart_contract%5Baddress_hash%5D=${ADDRESS}&smart_contract%5Bname%5D=AdminUpgradeabilityProxy&smart_contract%5Bnightly_builds%5D=false&smart_contract%5Bcompiler_version%5D=v0.5.3%2Bcommit.10d17f24&smart_contract%5Bevm_version%5D=constantinople&smart_contract%5Boptimization%5D=false&smart_contract%5Boptimization_runs%5D=200&smart_contract%5Bcontract_source_code%5D=%2F**%0D%0A+*Submitted+for+verification+at+Etherscan.io+on+2020-02-19%0D%0A*%2F%0D%0A%0D%0A%2F%2F+File%3A+%40openzeppelin%2Fupgrades%2Fcontracts%2Fupgradeability%2FProxy.sol%0D%0A%0D%0Apragma+solidity+%5E0.5.0%3B%0D%0A%0D%0A%2F**%0D%0A+*+%40title+Proxy%0D%0A+*+%40dev+Implements+delegation+of+calls+to+other+contracts%2C+with+proper%0D%0A+*+forwarding+of+return+values+and+bubbling+of+failures.%0D%0A+*+It+defines+a+fallback+function+that+delegates+all+calls+to+the+address%0D%0A+*+returned+by+the+abstract+_implementation%28%29+internal+function.%0D%0A+*%2F%0D%0Acontract+Proxy+%7B%0D%0A++%2F**%0D%0A+++*+%40dev+Fallback+function.%0D%0A+++*+Implemented+entirely+in+%60_fallback%60.%0D%0A+++*%2F%0D%0A++function+%28%29+payable+external+%7B%0D%0A++++_fallback%28%29%3B%0D%0A++%7D%0D%0A%0D%0A++%2F**%0D%0A+++*+%40return+The+Address+of+the+implementation.%0D%0A+++*%2F%0D%0A++function+_implementation%28%29+internal+view+returns+%28address%29%3B%0D%0A%0D%0A++%2F**%0D%0A+++*+%40dev+Delegates+execution+to+an+implementation+contract.%0D%0A+++*+This+is+a+low+level+function+that+doesn%27t+return+to+its+internal+call+site.%0D%0A+++*+It+will+return+to+the+external+caller+whatever+the+implementation+returns.%0D%0A+++*+%40param+implementation+Address+to+delegate.%0D%0A+++*%2F%0D%0A++function+_delegate%28address+implementation%29+internal+%7B%0D%0A++++assembly+%7B%0D%0A++++++%2F%2F+Copy+msg.data.+We+take+full+control+of+memory+in+this+inline+assembly%0D%0A++++++%2F%2F+block+because+it+will+not+return+to+Solidity+code.+We+overwrite+the%0D%0A++++++%2F%2F+Solidity+scratch+pad+at+memory+position+0.%0D%0A++++++calldatacopy%280%2C+0%2C+calldatasize%29%0D%0A%0D%0A++++++%2F%2F+Call+the+implementation.%0D%0A++++++%2F%2F+out+and+outsize+are+0+because+we+don%27t+know+the+size+yet.%0D%0A++++++let+result+%3A%3D+delegatecall%28gas%2C+implementation%2C+0%2C+calldatasize%2C+0%2C+0%29%0D%0A%0D%0A++++++%2F%2F+Copy+the+returned+data.%0D%0A++++++returndatacopy%280%2C+0%2C+returndatasize%29%0D%0A%0D%0A++++++switch+result%0D%0A++++++%2F%2F+delegatecall+returns+0+on+error.%0D%0A++++++case+0+%7B+revert%280%2C+returndatasize%29+%7D%0D%0A++++++default+%7B+return%280%2C+returndatasize%29+%7D%0D%0A++++%7D%0D%0A++%7D%0D%0A%0D%0A++%2F**%0D%0A+++*+%40dev+Function+that+is+run+as+the+first+thing+in+the+fallback+function.%0D%0A+++*+Can+be+redefined+in+derived+contracts+to+add+functionality.%0D%0A+++*+Redefinitions+must+call+super._willFallback%28%29.%0D%0A+++*%2F%0D%0A++function+_willFallback%28%29+internal+%7B%0D%0A++%7D%0D%0A%0D%0A++%2F**%0D%0A+++*+%40dev+fallback+implementation.%0D%0A+++*+Extracted+to+enable+manual+triggering.%0D%0A+++*%2F%0D%0A++function+_fallback%28%29+internal+%7B%0D%0A++++_willFallback%28%29%3B%0D%0A++++_delegate%28_implementation%28%29%29%3B%0D%0A++%7D%0D%0A%7D%0D%0A%0D%0A%2F%2F+File%3A+%40openzeppelin%2Fupgrades%2Fcontracts%2Futils%2FAddress.sol%0D%0A%0D%0Apragma+solidity+%5E0.5.0%3B%0D%0A%0D%0A%2F**%0D%0A+*+Utility+library+of+inline+functions+on+addresses%0D%0A+*%0D%0A+*+Source+https%3A%2F%2Fraw.githubusercontent.com%2FOpenZeppelin%2Fopenzeppelin-solidity%2Fv2.1.3%2Fcontracts%2Futils%2FAddress.sol%0D%0A+*+This+contract+is+copied+here+and+renamed+from+the+original+to+avoid+clashes+in+the+compiled+artifacts%0D%0A+*+when+the+user+imports+a+zos-lib+contract+%28that+transitively+causes+this+contract+to+be+compiled+and+added+to+the%0D%0A+*+build%2Fartifacts+folder%29+as+well+as+the+vanilla+Address+implementation+from+an+openzeppelin+version.%0D%0A+*%2F%0D%0Alibrary+OpenZeppelinUpgradesAddress+%7B%0D%0A++++%2F**%0D%0A+++++*+Returns+whether+the+target+address+is+a+contract%0D%0A+++++*+%40dev+This+function+will+return+false+if+invoked+during+the+constructor+of+a+contract%2C%0D%0A+++++*+as+the+code+is+not+actually+created+until+after+the+constructor+finishes.%0D%0A+++++*+%40param+account+address+of+the+account+to+check%0D%0A+++++*+%40return+whether+the+target+address+is+a+contract%0D%0A+++++*%2F%0D%0A++++function+isContract%28address+account%29+internal+view+returns+%28bool%29+%7B%0D%0A++++++++uint256+size%3B%0D%0A++++++++%2F%2F+XXX+Currently+there+is+no+better+way+to+check+if+there+is+a+contract+in+an+address%0D%0A++++++++%2F%2F+than+to+check+the+size+of+the+code+at+that+address.%0D%0A++++++++%2F%2F+See+https%3A%2F%2Fethereum.stackexchange.com%2Fa%2F14016%2F36603%0D%0A++++++++%2F%2F+for+more+details+about+how+this+works.%0D%0A++++++++%2F%2F+TODO+Check+this+again+before+the+Serenity+release%2C+because+all+addresses+will+be%0D%0A++++++++%2F%2F+contracts+then.%0D%0A++++++++%2F%2F+solhint-disable-next-line+no-inline-assembly%0D%0A++++++++assembly+%7B+size+%3A%3D+extcodesize%28account%29+%7D%0D%0A++++++++return+size+%3E+0%3B%0D%0A++++%7D%0D%0A%7D%0D%0A%0D%0A%2F%2F+File%3A+%40openzeppelin%2Fupgrades%2Fcontracts%2Fupgradeability%2FBaseUpgradeabilityProxy.sol%0D%0A%0D%0Apragma+solidity+%5E0.5.0%3B%0D%0A%0D%0A%0D%0A%0D%0A%2F**%0D%0A+*+%40title+BaseUpgradeabilityProxy%0D%0A+*+%40dev+This+contract+implements+a+proxy+that+allows+to+change+the%0D%0A+*+implementation+address+to+which+it+will+delegate.%0D%0A+*+Such+a+change+is+called+an+implementation+upgrade.%0D%0A+*%2F%0D%0Acontract+BaseUpgradeabilityProxy+is+Proxy+%7B%0D%0A++%2F**%0D%0A+++*+%40dev+Emitted+when+the+implementation+is+upgraded.%0D%0A+++*+%40param+implementation+Address+of+the+new+implementation.%0D%0A+++*%2F%0D%0A++event+Upgraded%28address+indexed+implementation%29%3B%0D%0A%0D%0A++%2F**%0D%0A+++*+%40dev+Storage+slot+with+the+address+of+the+current+implementation.%0D%0A+++*+This+is+the+keccak-256+hash+of+%22eip1967.proxy.implementation%22+subtracted+by+1%2C+and+is%0D%0A+++*+validated+in+the+constructor.%0D%0A+++*%2F%0D%0A++bytes32+internal+constant+IMPLEMENTATION_SLOT+%3D+0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc%3B%0D%0A%0D%0A++%2F**%0D%0A+++*+%40dev+Returns+the+current+implementation.%0D%0A+++*+%40return+Address+of+the+current+implementation%0D%0A+++*%2F%0D%0A++function+_implementation%28%29+internal+view+returns+%28address+impl%29+%7B%0D%0A++++bytes32+slot+%3D+IMPLEMENTATION_SLOT%3B%0D%0A++++assembly+%7B%0D%0A++++++impl+%3A%3D+sload%28slot%29%0D%0A++++%7D%0D%0A++%7D%0D%0A%0D%0A++%2F**%0D%0A+++*+%40dev+Upgrades+the+proxy+to+a+new+implementation.%0D%0A+++*+%40param+newImplementation+Address+of+the+new+implementation.%0D%0A+++*%2F%0D%0A++function+_upgradeTo%28address+newImplementation%29+internal+%7B%0D%0A++++_setImplementation%28newImplementation%29%3B%0D%0A++++emit+Upgraded%28newImplementation%29%3B%0D%0A++%7D%0D%0A%0D%0A++%2F**%0D%0A+++*+%40dev+Sets+the+implementation+address+of+the+proxy.%0D%0A+++*+%40param+newImplementation+Address+of+the+new+implementation.%0D%0A+++*%2F%0D%0A++function+_setImplementation%28address+newImplementation%29+internal+%7B%0D%0A++++require%28OpenZeppelinUpgradesAddress.isContract%28newImplementation%29%2C+%22Cannot+set+a+proxy+implementation+to+a+non-contract+address%22%29%3B%0D%0A%0D%0A++++bytes32+slot+%3D+IMPLEMENTATION_SLOT%3B%0D%0A%0D%0A++++assembly+%7B%0D%0A++++++sstore%28slot%2C+newImplementation%29%0D%0A++++%7D%0D%0A++%7D%0D%0A%7D%0D%0A%0D%0A%2F%2F+File%3A+%40openzeppelin%2Fupgrades%2Fcontracts%2Fupgradeability%2FUpgradeabilityProxy.sol%0D%0A%0D%0Apragma+solidity+%5E0.5.0%3B%0D%0A%0D%0A%0D%0A%2F**%0D%0A+*+%40title+UpgradeabilityProxy%0D%0A+*+%40dev+Extends+BaseUpgradeabilityProxy+with+a+constructor+for+initializing%0D%0A+*+implementation+and+init+data.%0D%0A+*%2F%0D%0Acontract+UpgradeabilityProxy+is+BaseUpgradeabilityProxy+%7B%0D%0A++%2F**%0D%0A+++*+%40dev+Contract+constructor.%0D%0A+++*+%40param+_logic+Address+of+the+initial+implementation.%0D%0A+++*+%40param+_data+Data+to+send+as+msg.data+to+the+implementation+to+initialize+the+proxied+contract.%0D%0A+++*+It+should+include+the+signature+and+the+parameters+of+the+function+to+be+called%2C+as+described+in%0D%0A+++*+https%3A%2F%2Fsolidity.readthedocs.io%2Fen%2Fv0.4.24%2Fabi-spec.html%23function-selector-and-argument-encoding.%0D%0A+++*+This+parameter+is+optional%2C+if+no+data+is+given+the+initialization+call+to+proxied+contract+will+be+skipped.%0D%0A+++*%2F%0D%0A++constructor%28address+_logic%2C+bytes+memory+_data%29+public+payable+%7B%0D%0A++++assert%28IMPLEMENTATION_SLOT+%3D%3D+bytes32%28uint256%28keccak256%28%27eip1967.proxy.implementation%27%29%29+-+1%29%29%3B%0D%0A++++_setImplementation%28_logic%29%3B%0D%0A++++if%28_data.length+%3E+0%29+%7B%0D%0A++++++%28bool+success%2C%29+%3D+_logic.delegatecall%28_data%29%3B%0D%0A++++++require%28success%29%3B%0D%0A++++%7D%0D%0A++%7D++%0D%0A%7D%0D%0A%0D%0A%2F%2F+File%3A+%40openzeppelin%2Fupgrades%2Fcontracts%2Fupgradeability%2FBaseAdminUpgradeabilityProxy.sol%0D%0A%0D%0Apragma+solidity+%5E0.5.0%3B%0D%0A%0D%0A%0D%0A%2F**%0D%0A+*+%40title+BaseAdminUpgradeabilityProxy%0D%0A+*+%40dev+This+contract+combines+an+upgradeability+proxy+with+an+authorization%0D%0A+*+mechanism+for+administrative+tasks.%0D%0A+*+All+external+functions+in+this+contract+must+be+guarded+by+the%0D%0A+*+%60ifAdmin%60+modifier.+See+ethereum%2Fsolidity%233864+for+a+Solidity%0D%0A+*+feature+proposal+that+would+enable+this+to+be+done+automatically.%0D%0A+*%2F%0D%0Acontract+BaseAdminUpgradeabilityProxy+is+BaseUpgradeabilityProxy+%7B%0D%0A++%2F**%0D%0A+++*+%40dev+Emitted+when+the+administration+has+been+transferred.%0D%0A+++*+%40param+previousAdmin+Address+of+the+previous+admin.%0D%0A+++*+%40param+newAdmin+Address+of+the+new+admin.%0D%0A+++*%2F%0D%0A++event+AdminChanged%28address+previousAdmin%2C+address+newAdmin%29%3B%0D%0A%0D%0A++%2F**%0D%0A+++*+%40dev+Storage+slot+with+the+admin+of+the+contract.%0D%0A+++*+This+is+the+keccak-256+hash+of+%22eip1967.proxy.admin%22+subtracted+by+1%2C+and+is%0D%0A+++*+validated+in+the+constructor.%0D%0A+++*%2F%0D%0A%0D%0A++bytes32+internal+constant+ADMIN_SLOT+%3D+0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103%3B%0D%0A%0D%0A++%2F**%0D%0A+++*+%40dev+Modifier+to+check+whether+the+%60msg.sender%60+is+the+admin.%0D%0A+++*+If+it+is%2C+it+will+run+the+function.+Otherwise%2C+it+will+delegate+the+call%0D%0A+++*+to+the+implementation.%0D%0A+++*%2F%0D%0A++modifier+ifAdmin%28%29+%7B%0D%0A++++if+%28msg.sender+%3D%3D+_admin%28%29%29+%7B%0D%0A++++++_%3B%0D%0A++++%7D+else+%7B%0D%0A++++++_fallback%28%29%3B%0D%0A++++%7D%0D%0A++%7D%0D%0A%0D%0A++%2F**%0D%0A+++*+%40return+The+address+of+the+proxy+admin.%0D%0A+++*%2F%0D%0A++function+admin%28%29+external+ifAdmin+returns+%28address%29+%7B%0D%0A++++return+_admin%28%29%3B%0D%0A++%7D%0D%0A%0D%0A++%2F**%0D%0A+++*+%40return+The+address+of+the+implementation.%0D%0A+++*%2F%0D%0A++function+implementation%28%29+external+ifAdmin+returns+%28address%29+%7B%0D%0A++++return+_implementation%28%29%3B%0D%0A++%7D%0D%0A%0D%0A++%2F**%0D%0A+++*+%40dev+Changes+the+admin+of+the+proxy.%0D%0A+++*+Only+the+current+admin+can+call+this+function.%0D%0A+++*+%40param+newAdmin+Address+to+transfer+proxy+administration+to.%0D%0A+++*%2F%0D%0A++function+changeAdmin%28address+newAdmin%29+external+ifAdmin+%7B%0D%0A++++require%28newAdmin+%21%3D+address%280%29%2C+%22Cannot+change+the+admin+of+a+proxy+to+the+zero+address%22%29%3B%0D%0A++++emit+AdminChanged%28_admin%28%29%2C+newAdmin%29%3B%0D%0A++++_setAdmin%28newAdmin%29%3B%0D%0A++%7D%0D%0A%0D%0A++%2F**%0D%0A+++*+%40dev+Upgrade+the+backing+implementation+of+the+proxy.%0D%0A+++*+Only+the+admin+can+call+this+function.%0D%0A+++*+%40param+newImplementation+Address+of+the+new+implementation.%0D%0A+++*%2F%0D%0A++function+upgradeTo%28address+newImplementation%29+external+ifAdmin+%7B%0D%0A++++_upgradeTo%28newImplementation%29%3B%0D%0A++%7D%0D%0A%0D%0A++%2F**%0D%0A+++*+%40dev+Upgrade+the+backing+implementation+of+the+proxy+and+call+a+function%0D%0A+++*+on+the+new+implementation.%0D%0A+++*+This+is+useful+to+initialize+the+proxied+contract.%0D%0A+++*+%40param+newImplementation+Address+of+the+new+implementation.%0D%0A+++*+%40param+data+Data+to+send+as+msg.data+in+the+low+level+call.%0D%0A+++*+It+should+include+the+signature+and+the+parameters+of+the+function+to+be+called%2C+as+described+in%0D%0A+++*+https%3A%2F%2Fsolidity.readthedocs.io%2Fen%2Fv0.4.24%2Fabi-spec.html%23function-selector-and-argument-encoding.%0D%0A+++*%2F%0D%0A++function+upgradeToAndCall%28address+newImplementation%2C+bytes+calldata+data%29+payable+external+ifAdmin+%7B%0D%0A++++_upgradeTo%28newImplementation%29%3B%0D%0A++++%28bool+success%2C%29+%3D+newImplementation.delegatecall%28data%29%3B%0D%0A++++require%28success%29%3B%0D%0A++%7D%0D%0A%0D%0A++%2F**%0D%0A+++*+%40return+The+admin+slot.%0D%0A+++*%2F%0D%0A++function+_admin%28%29+internal+view+returns+%28address+adm%29+%7B%0D%0A++++bytes32+slot+%3D+ADMIN_SLOT%3B%0D%0A++++assembly+%7B%0D%0A++++++adm+%3A%3D+sload%28slot%29%0D%0A++++%7D%0D%0A++%7D%0D%0A%0D%0A++%2F**%0D%0A+++*+%40dev+Sets+the+address+of+the+proxy+admin.%0D%0A+++*+%40param+newAdmin+Address+of+the+new+proxy+admin.%0D%0A+++*%2F%0D%0A++function+_setAdmin%28address+newAdmin%29+internal+%7B%0D%0A++++bytes32+slot+%3D+ADMIN_SLOT%3B%0D%0A%0D%0A++++assembly+%7B%0D%0A++++++sstore%28slot%2C+newAdmin%29%0D%0A++++%7D%0D%0A++%7D%0D%0A%0D%0A++%2F**%0D%0A+++*+%40dev+Only+fall+back+when+the+sender+is+not+the+admin.%0D%0A+++*%2F%0D%0A++function+_willFallback%28%29+internal+%7B%0D%0A++++require%28msg.sender+%21%3D+_admin%28%29%2C+%22Cannot+call+fallback+function+from+the+proxy+admin%22%29%3B%0D%0A++++super._willFallback%28%29%3B%0D%0A++%7D%0D%0A%7D%0D%0A%0D%0A%2F%2F+File%3A+%40openzeppelin%2Fupgrades%2Fcontracts%2Fupgradeability%2FAdminUpgradeabilityProxy.sol%0D%0A%0D%0Apragma+solidity+%5E0.5.0%3B%0D%0A%0D%0A%0D%0A%2F**%0D%0A+*+%40title+AdminUpgradeabilityProxy%0D%0A+*+%40dev+Extends+from+BaseAdminUpgradeabilityProxy+with+a+constructor+for+%0D%0A+*+initializing+the+implementation%2C+admin%2C+and+init+data.%0D%0A+*%2F%0D%0Acontract+AdminUpgradeabilityProxy+is+BaseAdminUpgradeabilityProxy%2C+UpgradeabilityProxy+%7B%0D%0A++%2F**%0D%0A+++*+Contract+constructor.%0D%0A+++*+%40param+_logic+address+of+the+initial+implementation.%0D%0A+++*+%40param+_admin+Address+of+the+proxy+administrator.%0D%0A+++*+%40param+_data+Data+to+send+as+msg.data+to+the+implementation+to+initialize+the+proxied+contract.%0D%0A+++*+It+should+include+the+signature+and+the+parameters+of+the+function+to+be+called%2C+as+described+in%0D%0A+++*+https%3A%2F%2Fsolidity.readthedocs.io%2Fen%2Fv0.4.24%2Fabi-spec.html%23function-selector-and-argument-encoding.%0D%0A+++*+This+parameter+is+optional%2C+if+no+data+is+given+the+initialization+call+to+proxied+contract+will+be+skipped.%0D%0A+++*%2F%0D%0A++constructor%28address+_logic%2C+address+_admin%2C+bytes+memory+_data%29+UpgradeabilityProxy%28_logic%2C+_data%29+public+payable+%7B%0D%0A++++assert%28ADMIN_SLOT+%3D%3D+bytes32%28uint256%28keccak256%28%27eip1967.proxy.admin%27%29%29+-+1%29%29%3B%0D%0A++++_setAdmin%28_admin%29%3B%0D%0A++%7D%0D%0A%7D&smart_contract%5Bautodetect_contructor_args%5D=true&smart_contract%5Bconstructor_arguments%5D=&external_libraries%5Blibrary1_name%5D=&external_libraries%5Blibrary1_address%5D=&external_libraries%5Blibrary2_name%5D=&external_libraries%5Blibrary2_address%5D=&external_libraries%5Blibrary3_name%5D=&external_libraries%5Blibrary3_address%5D=&external_libraries%5Blibrary4_name%5D=&external_libraries%5Blibrary4_address%5D=&external_libraries%5Blibrary5_name%5D=&external_libraries%5Blibrary5_address%5D=&external_libraries%5Blibrary6_name%5D=&external_libraries%5Blibrary6_address%5D=&external_libraries%5Blibrary7_name%5D=&external_libraries%5Blibrary7_address%5D=&external_libraries%5Blibrary8_name%5D=&external_libraries%5Blibrary8_address%5D=&external_libraries%5Blibrary9_name%5D=&external_libraries%5Blibrary9_address%5D=&external_libraries%5Blibrary10_name%5D=&smart_contract%5Blibrary10_address%5D=" \
    $url
}
