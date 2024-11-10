// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract AdvancedCryptoEstate is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;

    mapping(address => uint256) public beneficiaries;
    bool public isDeceased;
    uint256 public unlockTime;

    event AssetTransferred(address indexed beneficiary, uint256 amount);
    event BeneficiaryAdded(address indexed beneficiary, uint256 amount);
    event BeneficiaryRemoved(address indexed beneficiary);
    event DeceasedDeclared(uint256 unlockTime);

    modifier onlyIfDeceased() {
        require(isDeceased, "Owner is not deceased");
        require(block.timestamp >= unlockTime, "Assets are locked");
        _;
    }

    constructor() {
        isDeceased = false;
    }

    function addBeneficiary(address _beneficiary, uint256 _amount) public onlyOwner whenNotPaused {
        beneficiaries[_beneficiary] = _amount;
        emit BeneficiaryAdded(_beneficiary, _amount);
    }

    function removeBeneficiary(address _beneficiary) public onlyOwner whenNotPaused {
        require(beneficiaries[_beneficiary] > 0, "Beneficiary does not exist");
        delete beneficiaries[_beneficiary];
        emit BeneficiaryRemoved(_beneficiary);
    }

    function declareDeceased(uint256 _unlockTime) public onlyOwner whenNotPaused {
        isDeceased = true;
        unlockTime = _unlockTime;
        emit DeceasedDeclared(_unlockTime);
    }

   function transferAssets() public nonReentrant onlyIfDeceased whenNotPaused {
    address[] memory keys = new address[](beneficiaries.length);
    uint256 index = 0;
    
    // Assuming you have a way to populate the keys array with beneficiary addresses
    for (uint256 i = 0; i < keys.length; i++) {
        address beneficiary = keys[i];
        uint256 amount = beneficiaries[beneficiary];
        require(amount > 0, "No assets to transfer");
        beneficiaries[beneficiary] = 0; // Prevent reentrancy
        payable(beneficiary).transfer(amount);
        emit AssetTransferred(beneficiary, amount);
    }
}



    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    receive() external payable {}
}
