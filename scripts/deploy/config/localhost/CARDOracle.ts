import { getAddress, AddressFile, ContractConfig } from "../../config-utils";

export default async function (
  proxyAddresses: AddressFile
): Promise<ContractConfig> {
  function address(name: string) {
    return getAddress(name, proxyAddresses);
  }
  return Promise.resolve({
    setup: [
      {
        name: "tokenUsdFeed",
        value: address("CARDUSDFeed"),
      },
      {
        name: "ethUsdFeed",
        value: address("ETHUSDFeed"),
      },
      {
        name: "daiUsdFeed",
        value: address("DAIUSDFeed"),
      },
      {
        name: "versionManager",
        value: address("VersionManager"),
      },
    ],
  });
}
