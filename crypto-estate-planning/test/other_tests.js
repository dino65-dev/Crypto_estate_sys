const { expect } = require('chai');
const { BN, constants, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const AdvancedEstateToken = artifacts.require('AdvancedEstateToken');
const AdvancedDeathOracle = artifacts.require('AdvancedDeathOracle');
const Escrow = artifacts.require('Escrow');

contract('OtherContracts', function (accounts) {
  const [owner, minter, approver1, approver2, buyer, seller, nonOwner] = accounts;
  const tokenCap = new BN(10000);
  const mintAmount = new BN(1000);
  const escrowAmount = new BN(500);

  beforeEach(async function () {
    this.token = await AdvancedEstateToken.new(tokenCap, { from: owner });
    this.oracle = await AdvancedDeathOracle.new([approver1, approver2], 2, { from: owner });
    this.escrow = await Escrow.new(buyer, seller, { from: buyer });
  });

  describe('AdvancedEstateToken', function () {
    it('should allow minter to mint tokens', async function () {
      await this.token.grantRole(await this.token.MINTER_ROLE(), minter, { from: owner });
      await this.token.mint(minter, mintAmount, { from: minter });
      const balance = await this.token.balanceOf(minter);
      expect(balance).to.be.bignumber.equal(mintAmount);
    });

    it('should not allow non-minter to mint tokens', async function () {
      await expectRevert(
        this.token.mint(nonOwner, mintAmount, { from: nonOwner }),
        'AccessControl: account is missing role'
      );
    });

    it('should not exceed cap when minting', async function () {
      await this.token.grantRole(await this.token.MINTER_ROLE(), minter, { from: owner });
      await expectRevert(
        this.token.mint(minter, tokenCap.add(new BN(1)), { from: minter }),
        'ERC20Capped: cap exceeded'
      );
    });

    it('should burn tokens correctly', async function () {
      await this.token.grantRole(await this.token.MINTER_ROLE(), minter, { from: owner });
      await this.token.mint(minter, mintAmount, { from: minter });
      await this.token.burn(mintAmount.div(new BN(2)), { from: minter });
      const balance = await this.token.balanceOf(minter);
      expect(balance).to.be.bignumber.equal(mintAmount.div(new BN(2)));
    });

    it('should revert burning more tokens than balance', async function () {
      await expectRevert(
        this.token.burn(mintAmount, { from: minter }),
        'ERC20: burn amount exceeds balance'
      );
    });
  });

  describe('AdvancedDeathOracle', function () {
    it('should update deceased status with sufficient approvals', async function () {
      await this.oracle.updateDeceasedStatus(buyer, true, { from: owner });
      const status = await this.oracle.isDeceased(buyer);
      expect(status).to.be.true;
    });

    it('should not update deceased status without sufficient approvals', async function () {
      await expectRevert(
        this.oracle.updateDeceasedStatus(buyer, true, { from: nonOwner }),
        'Ownable: caller is not the owner'
      );
    });

    it('should handle multiple updates to deceased status', async function () {
      await this.oracle.updateDeceasedStatus(buyer, true, { from: owner });
      await this.oracle.updateDeceasedStatus(buyer, false, { from: owner });
      const status = await this.oracle.isDeceased(buyer);
      expect(status).to.be.false;
    });
  });

  describe('Escrow', function () {
    it('should allow buyer to confirm payment', async function () {
      await this.escrow.confirmPayment({ from: buyer, value: escrowAmount });
      const state = await this.escrow.currentState();
      expect(state).to.be.bignumber.equal(new BN(1)); // AWAITING_DELIVERY
    });

    it('should allow buyer to confirm delivery and release funds', async function () {
      await this.escrow.confirmPayment({ from: buyer, value: escrowAmount });
      const initialBalance = await web3.eth.getBalance(seller);
      await this.escrow.confirmDelivery({ from: buyer });
      const finalBalance = await web3.eth.getBalance(seller);
      expect(new BN(finalBalance)).to.be.bignumber.gt(new BN(initialBalance));
    });

    it('should not allow non-buyer to confirm payment or delivery', async function () {
      await expectRevert(
        this.escrow.confirmPayment({ from: nonOwner, value: escrowAmount }),
        'Only buyer can call this method'
      );

      await this.escrow.confirmPayment({ from: buyer, value: escrowAmount });

      await expectRevert(
        this.escrow.confirmDelivery({ from: nonOwner }),
        'Only buyer can call this method'
      );
    });

    it('should revert if delivery is confirmed without payment', async function () {
      await expectRevert(
        this.escrow.confirmDelivery({ from: buyer }),
        'Invalid state'
      );
    });

    it('should handle multiple escrow states correctly', async function () {
      await this.escrow.confirmPayment({ from: buyer, value: escrowAmount });
      await this.escrow.confirmDelivery({ from: buyer });
      const state = await this.escrow.currentState();
      expect(state).to.be.bignumber.equal(new BN(2)); // COMPLETE
    });
  });
});
