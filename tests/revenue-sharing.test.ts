import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Can initialize revenue pool",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('real-estate', 'add-property', [types.uint(1000), types.uint(100)], deployer.address),
            Tx.contractCall('revenue-sharing', 'initialize-revenue-pool', [types.uint(0)], deployer.address),
        ]);
        
        assertEquals(block.receipts.length, 2);
        block.receipts[1].result.expectOk().expectBool(true);
    },
});

Clarinet.test({
    name: "Can deposit and calculate rewards",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const wallet1 = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('real-estate', 'add-property', [types.uint(1000), types.uint(100)], deployer.address),
            Tx.contractCall('revenue-sharing', 'initialize-revenue-pool', [types.uint(0)], deployer.address),
            Tx.contractCall('real-estate', 'buy-tokens', [types.uint(0), types.uint(50)], wallet1.address),
            Tx.contractCall('revenue-sharing', 'deposit-revenue', [types.uint(0), types.uint(500)], deployer.address),
            Tx.contractCall('revenue-sharing', 'calculate-holder-reward', [types.uint(0), wallet1.address], deployer.address),
        ]);
        
        assertEquals(block.receipts.length, 5);
        block.receipts[4].result.expectOk();
    },
});

Clarinet.test({
    name: "Can claim rewards",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const wallet1 = accounts.get('wallet_1')!;
        
        let setupBlock = chain.mineBlock([
            Tx.contractCall('real-estate', 'add-property', [types.uint(1000), types.uint(100)], deployer.address),
            Tx.contractCall('revenue-sharing', 'initialize-revenue-pool', [types.uint(0)], deployer.address),
            Tx.contractCall('real-estate', 'buy-tokens', [types.uint(0), types.uint(50)], wallet1.address),
            Tx.contractCall('revenue-sharing', 'deposit-revenue', [types.uint(0), types.uint(500)], deployer.address),
            Tx.contractCall('revenue-sharing', 'calculate-holder-reward', [types.uint(0), wallet1.address], deployer.address),
        ]);
        
        let claimBlock = chain.mineBlock([
            Tx.contractCall('revenue-sharing', 'claim-rewards', [types.uint(0)], wallet1.address),
        ]);
        
        claimBlock.receipts[0].result.expectOk();
    },
});
