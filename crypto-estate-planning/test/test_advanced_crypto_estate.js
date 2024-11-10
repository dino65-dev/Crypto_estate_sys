const { expect } = require('chai');
const { BN, constants, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const AdvancedCryptoEstate = artifacts.require('AdvancedCryptoEstate');

contract('AdvancedCryptoEstate', function (accounts) {
  const [owner, beneficiary1, beneficiary2, nonOwner] = accounts;
  const initialAmount = new BN(1000);

  beforeEach(async function () {
    this.estate = await AdvancedCryptoEstate.new({ from: owner });
  });

  describe('Beneficiary Management', function () {
    it('should allow the owner to add a beneficiary', async function () {
      const receipt = await this.estate.addBeneficiary(beneficiary1, initialAmount, { from: owner });
      expectEvent(receipt, 'BeneficiaryAdded', { beneficiary: beneficiary1, amount: initialAmount });

      const amount = await this.estate.beneficiaries(beneficiary1);
      expect(amount).to.be.bignumber.equal(initialAmount);
    });

    it('should not allow non-owner to add a beneficiary', async function () {
      await expectRevert(
        this.estate.addBeneficiary(beneficiary1, initialAmount, { from: nonOwner }),
        'Ownable: caller is not the owner'
      );
    });

    it('should allow the owner to remove a beneficiary', async function () {
      await this.estate.addBeneficiary(beneficiary1, initialAmount, { from: owner });
      const receipt = await this.estate.removeBeneficiary(beneficiary1, { from: owner });
      expectEvent(receipt, 'BeneficiaryRemoved', { beneficiary: beneficiary1 });

      const amount = await this.estate.beneficiaries(beneficiary1);
      expect(amount).to.be.bignumber.equal(new BN(0));
    });

    it('should not allow non-owner to remove a beneficiary', async function () {
      await this.estate.addBeneficiary(beneficiary1, initialAmount, { from: owner });
      await expectRevert(
        this.estate.removeBeneficiary(beneficiary1, { from: nonOwner }),
        'Ownable: caller is not the owner'
      );
    });
  });

  describe('Deceased Declaration and Asset Transfer', function () {
    it('should allow the owner to declare deceased and set unlock time', async function () {
      const unlockTime = (await web3.eth.getBlock('latest')).timestamp + 1000;
      const receipt = await this.estate.declareDeceased(unlockTime, { from: owner });
      expectEvent(receipt, 'DeceasedDeclared', { unlockTime: new BN(unlockTime) });

      const isDeceased = await this.estate.isDeceased();
      expect(isDeceased).to.be.true;
    });

    it('should not allow non-owner to declare deceased', async function () {
      const unlockTime = (await web3.eth.getBlock('latest')).timestamp + 1000;
      await expectRevert(
        this.estate.declareDeceased(unlockTime, { from: nonOwner }),
        'Ownable: caller is not the owner'
      );
    });

    it('should transfer assets to beneficiaries after unlock time', async function () {
      await this.estate.addBeneficiary(beneficiary1, initialAmount, { from: owner });
      const unlockTime = (await web3.eth.getBlock('latest')).timestamp + 1;
      await this.estate.declareDeceased(unlockTime, { from: owner });

      await new Promise(resolve => setTimeout(resolve, 2000)); // Wait for unlock time

      const receipt = await this.estate.transferAssets({ from: beneficiary1 });
      expectEvent(receipt, 'AssetTransferred', { beneficiary: beneficiary1, amount: initialAmount });

      const amount = await this.estate.beneficiaries(beneficiary1);
      expect(amount).to.be.bignumber.equal(new BN(0));
    });

    it('should not transfer assets before unlock time', async function () {
      await this.estate.addBeneficiary(beneficiary1, initialAmount, { from: owner });
      const unlockTime = (await web3.eth.getBlock('latest')).timestamp + 1000;
      await this.estate.declareDeceased(unlockTime, { from: owner });

      await expectRevert(
        this.estate.transferAssets({ from: beneficiary1 }),
        'Assets are locked'
      );
    });
  });

  describe('Pausable Functionality', function () {
    it('should allow the owner to pause and unpause the contract', async function () {
      await this.estate.pause({ from: owner });
      expect(await this.estate.paused()).to.be.true;

      await this.estate.unpause({ from: owner });
      expect(await this.estate.paused()).to.be.false;
    });

    it('should not allow non-owner to pause or unpause the contract', async function () {
      await expectRevert(
        this.estate.pause({ from: nonOwner }),
        'Ownable: caller is not the owner'
      );

      await this.estate.pause({ from: owner });

      await expectRevert(
        this.estate.unpause({ from: nonOwner }),
        'Ownable: caller is not the owner'
      );
    });

    it('should not allow adding beneficiaries when paused', async function () {
      await this.estate.pause({ from: owner });
      await expectRevert(
        this.estate.addBeneficiary(beneficiary1, initialAmount, { from: owner }),
        'Pausable: paused'
      );
    });
  });
});
