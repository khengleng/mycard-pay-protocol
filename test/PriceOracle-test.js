const Feed = artifacts.require("ManualFeed");
const MockDIAOracle = artifacts.require("MockDIAOracle");
const DIAPriceOracle = artifacts.require("DIAOracleAdapter");
const ChainlinkPriceOracle = artifacts.require("ChainlinkFeedAdapter");
const { expect } = require("./setup");
const { setupVersionManager } = require("./utils/helper");

contract("PriceOracle", async (accounts) => {
  let [owner, nonOwner] = accounts;

  describe("chainlink", () => {
    let daiFeed,
      ethFeed,
      chainlinkPrice,
      chainlinkPrice2,
      chainlinkSnapping,
      daiSnappingFeed,
      versionManager;

    before(async () => {
      versionManager = await setupVersionManager(owner);
      daiFeed = await Feed.new();
      await daiFeed.initialize(owner);
      await daiFeed.setup("DAI", 8, versionManager.address);
      await daiFeed.addRound(100000000, 1618433281, 1618433281);
      let token2Feed = await Feed.new();
      await token2Feed.initialize(owner);
      await token2Feed.setup("DAIx2", 8, versionManager.address);
      await token2Feed.addRound(200000000, 1618433281, 1618433281);
      daiSnappingFeed = await Feed.new();
      await daiSnappingFeed.initialize(owner);
      await daiSnappingFeed.setup("DAI", 8, versionManager.address);
      await daiSnappingFeed.addRound(100000000, 1618433281, 1618433281);
      ethFeed = await Feed.new();
      await ethFeed.initialize(owner);
      await ethFeed.setup("ETH", 8, versionManager.address);
      await ethFeed.addRound(300000000000, 1618433281, 1618433281);

      chainlinkPrice = await ChainlinkPriceOracle.new();
      await chainlinkPrice.initialize(owner);
      await chainlinkPrice.setup(
        daiFeed.address,
        ethFeed.address,
        daiFeed.address,
        false,
        0,
        versionManager.address
      );

      chainlinkPrice2 = await ChainlinkPriceOracle.new();
      await chainlinkPrice2.initialize(owner);
      await chainlinkPrice2.setup(
        token2Feed.address,
        ethFeed.address,
        daiFeed.address,
        false,
        0,
        versionManager.address
      );

      chainlinkSnapping = await ChainlinkPriceOracle.new();
      await chainlinkSnapping.initialize(owner);
      await chainlinkSnapping.setup(
        daiSnappingFeed.address,
        ethFeed.address,
        daiSnappingFeed.address,
        true,
        5000000, // 5% snapping threshold
        versionManager.address
      );
    });

    it("can get version of contract", async () => {
      expect(await chainlinkPrice.cardpayVersion()).to.equal("1.0.0");
    });

    it("can get oracle decimals", async () => {
      expect((await chainlinkPrice.decimals()).toString()).to.equal("8");
    });

    it("can get oracle description", async () => {
      expect(await chainlinkPrice.description()).to.equal("DAI");
    });

    it("can get USD token price", async () => {
      let { price, updatedAt } = await chainlinkPrice.usdPrice();
      expect(price.toString()).to.equal("100000000");
      expect(updatedAt.toString()).to.equal("1618433281");
    });

    it("can get ETH token price", async () => {
      let { price, updatedAt } = await chainlinkPrice.ethPrice();
      expect(price.toString()).to.equal("33333");
      expect(updatedAt.toString()).to.equal("1618433281");
    });

    it("can get DAI token price for DAI token", async () => {
      let { price, updatedAt } = await chainlinkPrice.daiPrice();
      expect(price.toString()).to.equal("100000000");
      expect(updatedAt.toString()).to.equal("1618433281");
    });

    it("can get DAI token price for non-DAI token", async () => {
      let { price, updatedAt } = await chainlinkPrice2.daiPrice();
      expect(price.toString()).to.equal("200000000");
      expect(updatedAt.toString()).to.equal("1618433281");
    });

    it("can reflect updated feed", async () => {
      await daiFeed.addRound(150000000, "1618453281", "1618453281");
      {
        let { price, updatedAt } = await chainlinkPrice.usdPrice();
        expect(price.toString()).to.equal("150000000");
        expect(updatedAt.toString()).to.equal("1618453281");
      }
      {
        let { price, updatedAt } = await chainlinkPrice.ethPrice();
        expect(price.toString()).to.equal("50000");
        expect(updatedAt.toString()).to.equal("1618453281");
      }
    });

    it("does not snap USD value to 1:1 when usdSnapping not enabled", async () => {
      await daiFeed.addRound(105000000, "1618453281", "1618453281");
      let { price: usdPrice } = await chainlinkPrice.usdPrice();
      let { price: ethPrice } = await chainlinkPrice.ethPrice();
      let { price: daiPrice } = await chainlinkPrice.daiPrice();

      expect(usdPrice.toString()).to.equal("105000000");
      expect(daiPrice.toString()).to.equal("100000000");
      expect(ethPrice.toString()).to.equal("35000");

      expect(await chainlinkPrice.isSnappedToUSD()).to.equal(false);
      expect((await chainlinkPrice.usdDelta()).toString()).to.equal("5000000");
    });

    it("snaps USD value to 1:1 when usdSnapping enabled and rate is within threshold by positive amount", async () => {
      await daiSnappingFeed.addRound(105000000, 1618433281, 1618433281); // rate is +5%
      let { price: usdPrice } = await chainlinkSnapping.usdPrice();
      let { price: ethPrice } = await chainlinkSnapping.ethPrice();
      let { price: daiPrice } = await chainlinkSnapping.daiPrice();

      expect(usdPrice.toString()).to.equal("100000000");
      expect(daiPrice.toString()).to.equal("100000000");
      expect(ethPrice.toString()).to.equal("33333");

      expect(await chainlinkSnapping.isSnappedToUSD()).to.equal(true);
      expect((await chainlinkSnapping.usdDelta()).toString()).to.equal(
        "5000000"
      );
    });

    it("snaps USD value to 1:1 when usdSnapping enabled and rate is within threshold by negative amount", async () => {
      await daiSnappingFeed.addRound(95000000, 1618433281, 1618433281); // rate is -5%
      let { price: usdPrice } = await chainlinkSnapping.usdPrice();
      let { price: ethPrice } = await chainlinkSnapping.ethPrice();
      let { price: daiPrice } = await chainlinkSnapping.daiPrice();

      expect(usdPrice.toString()).to.equal("100000000");
      expect(daiPrice.toString()).to.equal("100000000");
      expect(ethPrice.toString()).to.equal("33333");

      expect(await chainlinkSnapping.isSnappedToUSD()).to.equal(true);
      expect((await chainlinkSnapping.usdDelta()).toString()).to.equal(
        "5000000"
      );
    });

    it("does not snap USD value to 1:1 when usdSnapping enabled and rate is above threshold", async () => {
      await daiSnappingFeed.addRound(106000000, 1618433281, 1618433281); // rate is +6%
      let { price: usdPrice } = await chainlinkSnapping.usdPrice();
      let { price: ethPrice } = await chainlinkSnapping.ethPrice();
      let { price: daiPrice } = await chainlinkSnapping.daiPrice();

      expect(usdPrice.toString()).to.equal("106000000");
      expect(daiPrice.toString()).to.equal("100000000");
      expect(ethPrice.toString()).to.equal("35333");

      expect(await chainlinkSnapping.isSnappedToUSD()).to.equal(false);
      expect((await chainlinkSnapping.usdDelta()).toString()).to.equal(
        "6000000"
      );
    });

    it("does not snap USD value to 1:1 when usdSnapping enabled and rate is below threshold", async () => {
      await daiSnappingFeed.addRound(94000000, 1618433281, 1618433281); // rate is -6%
      let { price: usdPrice } = await chainlinkSnapping.usdPrice();
      let { price: ethPrice } = await chainlinkSnapping.ethPrice();
      let { price: daiPrice } = await chainlinkSnapping.daiPrice();

      expect(usdPrice.toString()).to.equal("94000000");
      expect(daiPrice.toString()).to.equal("100000000");
      expect(ethPrice.toString()).to.equal("31333");

      expect(await chainlinkSnapping.isSnappedToUSD()).to.equal(false);
      expect((await chainlinkSnapping.usdDelta()).toString()).to.equal(
        "6000000"
      );
    });

    it("rejects when non-owner calls setup()", async () => {
      await chainlinkPrice
        .setup(
          daiFeed.address,
          ethFeed.address,
          daiFeed.address,
          false,
          0,
          versionManager.address,
          {
            from: nonOwner,
          }
        )
        .should.be.rejectedWith(Error, "Ownable: caller is not the owner");
    });

    it("rejects when token feed is not set", async () => {
      let badOracle = await ChainlinkPriceOracle.new();
      await badOracle.initialize(owner);
      await badOracle
        .usdPrice()
        .should.be.rejectedWith(Error, "feed address is not specified");
      await badOracle
        .ethPrice()
        .should.be.rejectedWith(Error, "feed address is not specified");
    });

    it("rejects when there is decimal mismatch in the USD and ETH feed", async () => {
      let badFeed = await Feed.new();
      await badFeed.initialize(owner);
      await badFeed.setup("DAI", 0, versionManager.address);
      await badFeed.addRound(1, 1618433281, 1618433281);
      let badOracle = await ChainlinkPriceOracle.new();
      await badOracle.initialize(owner);
      await badOracle
        .setup(
          badFeed.address,
          ethFeed.address,
          daiFeed.address,
          false,
          0,
          versionManager.address
        )
        .should.be.rejectedWith(Error, "feed decimals mismatch");
    });
  });

  describe("DIA", () => {
    let mockDiaOracle, diaPrice, daiFeed, versionManager;
    before(async () => {
      versionManager = await setupVersionManager(owner);
      daiFeed = await Feed.new();
      await daiFeed.initialize(owner);
      await daiFeed.setup("DAI", 8, versionManager.address);
      await daiFeed.addRound(100000000, 1618433281, 1618433281);
      mockDiaOracle = await MockDIAOracle.new();
      await mockDiaOracle.initialize(owner);
      await mockDiaOracle.setup(versionManager.address);
      await mockDiaOracle.setValue("CARD/USD", 1500000, 1618433281);
      await mockDiaOracle.setValue("CARD/ETH", 500, 1618433281);
      diaPrice = await DIAPriceOracle.new();
      await diaPrice.initialize(owner);
      await diaPrice.setup(
        mockDiaOracle.address,
        "CARD",
        daiFeed.address,
        versionManager.address
      );
    });

    it("can get version of contract", async () => {
      expect(await diaPrice.cardpayVersion()).to.equal("1.0.0");
      expect(await mockDiaOracle.cardpayVersion()).to.equal("1.0.0");
    });

    it("can get oracle decimals", async () => {
      expect((await diaPrice.decimals()).toString()).to.equal("8");
    });

    it("can get oracle description", async () => {
      expect(await diaPrice.description()).to.equal("CARD");
    });

    it("can get USD token price", async () => {
      let { price, updatedAt } = await diaPrice.usdPrice();
      expect(price.toString()).to.equal("1500000");
      expect(updatedAt.toString()).to.equal("1618433281");
    });

    it("can get ETH token price", async () => {
      let { price, updatedAt } = await diaPrice.ethPrice();
      expect(price.toString()).to.equal("500");
      expect(updatedAt.toString()).to.equal("1618433281");
    });

    it("can get DAI token price", async () => {
      let { price, updatedAt } = await diaPrice.daiPrice();
      expect(price.toString()).to.equal("1500000");
      expect(updatedAt.toString()).to.equal("1618433281");
    });

    it("can reflect updated feed", async () => {
      await mockDiaOracle.setValue("CARD/USD", 2000000, 1618453281);
      await mockDiaOracle.setValue("CARD/ETH", 667, 1618453281);
      {
        let { price, updatedAt } = await diaPrice.usdPrice();
        expect(price.toString()).to.equal("2000000");
        expect(updatedAt.toString()).to.equal("1618453281");
      }
      {
        let { price, updatedAt } = await diaPrice.ethPrice();
        expect(price.toString()).to.equal("667");
        expect(updatedAt.toString()).to.equal("1618453281");
      }
    });

    it("rejects when non-owner calls setup()", async () => {
      await diaPrice
        .setup(
          mockDiaOracle.address,
          "CARD",
          daiFeed.address,
          versionManager.address,
          {
            from: nonOwner,
          }
        )
        .should.be.rejectedWith(Error, "Ownable: caller is not the owner");
    });

    it("rejects when oracle is not set", async () => {
      let badOracle = await DIAPriceOracle.new();
      await badOracle.initialize(owner);
      await badOracle
        .usdPrice()
        .should.be.rejectedWith(Error, "DIA oracle is not specified");
      await badOracle
        .ethPrice()
        .should.be.rejectedWith(Error, "DIA oracle is not specified");
    });
  });
});
