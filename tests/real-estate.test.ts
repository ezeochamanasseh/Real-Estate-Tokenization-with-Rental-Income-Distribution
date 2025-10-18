import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

describe("real-estate contract", () => {
    it("successfully adds a new property", () => {
        const addPropertyCall = simnet.callPublicFn(
            "real-estate",
            "add-property",
            [Cl.uint(1000000), Cl.uint(100)],
            deployer
        );
        expect(addPropertyCall.result).toBeOk(Cl.uint(0));
    });

    it("allows users to buy tokens", () => {
      // First ensure property exists by adding it
      simnet.callPublicFn(
          "real-estate",
          "add-property",
          [Cl.uint(1000000), Cl.uint(100)],
          deployer
      );
      
      // Now try to buy tokens
      const buyTokensCall = simnet.callPublicFn(
          "real-estate",
          "buy-tokens",
          [Cl.uint(0), Cl.uint(10)],
          wallet1
      );
      expect(buyTokensCall.result).toBeOk(Cl.bool(true));
  });

    it("distributes rental income", () => {

        simnet.callPublicFn(
            "real-estate",
            "add-property",
            [Cl.uint(1000000), Cl.uint(100)],
            deployer
        );
        const distributeIncomeCall = simnet.callPublicFn(
            "real-estate",
            "distribute-rental-income",
            [Cl.uint(0), Cl.uint(5000)],
            deployer
        );
        expect(distributeIncomeCall.result).toBeOk(Cl.bool(true));
    });

    it("retrieves property information", () => {
      // First add property
      simnet.callPublicFn(
          "real-estate",
          "add-property",
          [Cl.uint(1000000), Cl.uint(100)],
          deployer
      );

      const getPropertyCall = simnet.callReadOnlyFn(
          "real-estate",
          "get-property",
          [Cl.uint(0)],
          deployer
      );
      
      expect(getPropertyCall.result).toBeSome(Cl.tuple({
          owner: Cl.principal(deployer),
          price: Cl.uint(1000000),
          "rental-income": Cl.uint(0),
          "total-tokens": Cl.uint(100)
      }));
  });

  it("retrieves token balance for holder", () => {
    // First add property
    const addPropertyCall = simnet.callPublicFn(
        "real-estate",
        "add-property",
        [Cl.uint(1000000), Cl.uint(100)],
        deployer
    );
    expect(addPropertyCall.result).toBeOk(Cl.uint(0));

    // Buy tokens
    const buyTokensCall = simnet.callPublicFn(
        "real-estate",
        "buy-tokens",
        [Cl.uint(0), Cl.uint(10)],
        wallet1
    );
    expect(buyTokensCall.result).toBeOk(Cl.bool(true));

    // Check balance
    const getBalanceCall = simnet.callReadOnlyFn(
        "real-estate",
        "get-token-balance",
        [Cl.uint(0), Cl.principal(wallet1)],
        wallet1
    );
    expect(getBalanceCall.result).toBeUint(10);
});
});

