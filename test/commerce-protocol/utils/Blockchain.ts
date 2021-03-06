import { MockProvider } from "ethereum-waffle";

export class Blockchain {
  private _snapshotId: number;
  private _provider: MockProvider;

  constructor(provider: MockProvider) {
    this._provider = provider;
  }

  public async saveSnapshotAsync(): Promise<void> {
    const response = await this.sendJSONRpcRequestAsync("evm_snapshot", []);
    this._snapshotId = Number(response);
  }

  public async revertAsync(): Promise<void> {
    await this.sendJSONRpcRequestAsync("evm_revert", [this._snapshotId]);
  }

  public async resetAsync(): Promise<void> {
    await this.sendJSONRpcRequestAsync("evm_revert", ["0x1"]);
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  public async increaseTimeAsync(duration: number): Promise<any> {
    await this.sendJSONRpcRequestAsync("evm_increaseTime", [duration]);
  }

  public async waitBlocksAsync(count: number): Promise<void> {
    for (let i = 0; i < count; i++) {
      await this.sendJSONRpcRequestAsync("evm_mine", []);
    }
  }

  private async sendJSONRpcRequestAsync(
    method: string,
    params: any[] // eslint-disable-line @typescript-eslint/no-explicit-any
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  ): Promise<any> {
    return this._provider.send(method, params);
  }
}
