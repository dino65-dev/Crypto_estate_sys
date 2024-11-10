// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin contracts for ERC20 token standard, burnable and capped extensions, and access control
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

// Import Chainlink interfaces for oracle integration
import "@chainlink/AggregatorV3Interface.sol";

// Import OpenZeppelin's ReentrancyGuard for preventing reentrancy attacks
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Import Address library for safe address operations
import "@openzeppelin/contracts/utils/Address.sol";


/// @title EstateToken
/// @notice ERC20 Token with burnable feature and cap, using role-based access control
contract EstateToken is ERC20, ERC20Burnable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant MINTER_ADMIN_ROLE = keccak256("MINTER_ADMIN_ROLE");

    uint256 private _cap;

    /// @notice Constructor to initialize the token with a cap and assign the admin and minter roles
    /// @param cap_ Maximum cap for the total token supply
    /// @param admins Array of addresses to be granted the DEFAULT_ADMIN_ROLE
    /// @param minterAdmins Array of addresses to be granted the MINTER_ADMIN_ROLE
    /// @param minters Array of addresses to be granted the MINTER_ROLE
    constructor(
        uint256 cap_,
        address[] memory admins,
        address[] memory minterAdmins,
        address[] memory minters
    ) ERC20("EstateToken", "EST") {
        require(cap_ > 0, "EstateToken: cap is 0");
        _cap = cap_;

        // Set the admin role for MINTER_ROLE to be MINTER_ADMIN_ROLE
        _setRoleAdmin(MINTER_ROLE, MINTER_ADMIN_ROLE);

        // Grant DEFAULT_ADMIN_ROLE to the addresses in admins array
        for (uint256 i = 0; i < admins.length; i++) {
            require(admins[i] != address(0), "EstateToken: admin address cannot be zero");
            _grantRole(DEFAULT_ADMIN_ROLE, admins[i]);
        }

        // Grant MINTER_ADMIN_ROLE to the addresses in minterAdmins array
        for (uint256 i = 0; i < minterAdmins.length; i++) {
            require(minterAdmins[i] != address(0), "EstateToken: minter admin address cannot be zero");
            _grantRole(MINTER_ADMIN_ROLE, minterAdmins[i]);
        }

        // Grant MINTER_ROLE to the addresses in minters array
        for (uint256 i = 0; i < minters.length; i++) {
            require(minters[i] != address(0), "EstateToken: minter address cannot be zero");
            _grantRole(MINTER_ROLE, minters[i]);
        }
    }

    /// @notice Function to get the cap on the token's total supply
    /// @return The token cap
    function cap() public view returns (uint256) {
        return _cap;
    }

    /// @notice Override _mint to include cap logic
    function _mint(address to, uint256 amount) internal virtual override {
        require(totalSupply() + amount <= cap(), "EstateToken: cap exceeded");
        super._mint(to, amount);
    }

   
    }




/// @title EstateEscrow
/// @notice Escrow contract with conditional release and dispute resolution mechanisms
contract EstateEscrow is ReentrancyGuard, AccessControl {
    using Address for address payable;

    bytes32 public constant ARBITER_ROLE = keccak256("ARBITER_ROLE");
    bytes32 public constant ARBITER_ADMIN_ROLE = keccak256("ARBITER_ADMIN_ROLE");

    enum EscrowStatus { AWAITING_PAYMENT, AWAITING_RELEASE, COMPLETE, DISPUTED, REFUNDED }

    struct Escrow {
        address payable buyer;
        address payable seller;
        uint256 amount;
        EscrowStatus status;
        uint256 oracleData; // Data fetched from the oracle
    }

    mapping(uint256 => Escrow) public escrows;

    uint256 public escrowCount;

    // Chainlink oracle interface
    AggregatorV3Interface internal priceFeed;

    // Events for logging escrow actions
    event EscrowCreated(uint256 indexed escrowId, address buyer, address seller, uint256 amount);
    event PaymentMade(uint256 indexed escrowId);
    event ItemReceived(uint256 indexed escrowId);
    event DisputeRaised(uint256 indexed escrowId);
    event DisputeResolved(uint256 indexed escrowId, EscrowStatus outcome);
    event FundsWithdrawn(uint256 indexed escrowId, address recipient, uint256 amount);

    /// @notice Constructor to initialize the escrow contract and assign the admin and arbiter roles
    /// @param _priceFeed Address of the Chainlink price feed contract
    /// @param admins Array of addresses to be granted the DEFAULT_ADMIN_ROLE
    /// @param arbiterAdmins Array of addresses to be granted the ARBITER_ADMIN_ROLE
    /// @param arbiters Array of addresses to be granted the ARBITER_ROLE
    constructor(
        address _priceFeed,
        address[] memory admins,
        address[] memory arbiterAdmins,
        address[] memory arbiters
    ) {
        require(_priceFeed != address(0), "EstateEscrow: Price feed address cannot be zero");

        // Set the admin role for ARBITER_ROLE to be ARBITER_ADMIN_ROLE
        _setRoleAdmin(ARBITER_ROLE, ARBITER_ADMIN_ROLE);

        // Grant DEFAULT_ADMIN_ROLE to the addresses in admins array
        for (uint256 i = 0; i < admins.length; i++) {
            require(admins[i] != address(0), "EstateEscrow: admin address cannot be zero");
            _grantRole(DEFAULT_ADMIN_ROLE, admins[i]);
        }

        // Grant ARBITER_ADMIN_ROLE to the addresses in arbiterAdmins array
        for (uint256 i = 0; i < arbiterAdmins.length; i++) {
            require(arbiterAdmins[i] != address(0), "EstateEscrow: arbiter admin address cannot be zero");
            _grantRole(ARBITER_ADMIN_ROLE, arbiterAdmins[i]);
        }

        // Grant ARBITER_ROLE to the addresses in arbiters array
        for (uint256 i = 0; i < arbiters.length; i++) {
            require(arbiters[i] != address(0), "EstateEscrow: arbiter address cannot be zero");
            _grantRole(ARBITER_ROLE, arbiters[i]);
        }

        // Initialize the Chainlink oracle for price feeds
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /// @notice Creates a new escrow
    /// @param _seller Seller's address
    /// @param _amount Amount of Ether involved in the escrow
    /// @return escrowId The ID of the newly created escrow
    function createEscrow(address payable _seller, uint256 _amount) external payable nonReentrant returns (uint256 escrowId) {
        require(_seller != address(0), "EstateEscrow: Seller address cannot be zero");
        require(msg.value == _amount, "EstateEscrow: Incorrect payment amount sent");

        escrowCount++;
        escrowId = escrowCount;

        escrows[escrowId] = Escrow({
            buyer: payable(msg.sender),
            seller: _seller,
            amount: _amount,
            status: EscrowStatus.AWAITING_RELEASE,
            oracleData: 0
        });

        emit EscrowCreated(escrowId, msg.sender, _seller, _amount);
    }

    /// @notice Buyer confirms receipt and releases funds to the seller
    /// @param _escrowId ID of the escrow
    function confirmReceipt(uint256 _escrowId) external nonReentrant {
        Escrow storage escrow = escrows[_escrowId];

        require(msg.sender == escrow.buyer, "EstateEscrow: Only buyer can confirm receipt");
        require(escrow.status == EscrowStatus.AWAITING_RELEASE, "EstateEscrow: Escrow is not awaiting release");

        // Fetch oracle data if necessary
        escrow.oracleData = getOracleData();

        // Release funds to seller
        escrow.seller.sendValue(escrow.amount);

        escrow.status = EscrowStatus.COMPLETE;
        emit ItemReceived(_escrowId);
        emit FundsWithdrawn(_escrowId, escrow.seller, escrow.amount);
    }

    /// @notice Either party can raise a dispute
    /// @param _escrowId ID of the escrow
    function raiseDispute(uint256 _escrowId) external {
        Escrow storage escrow = escrows[_escrowId];

        require(msg.sender == escrow.buyer || msg.sender == escrow.seller, "EstateEscrow: Only buyer or seller can raise a dispute");
        require(escrow.status == EscrowStatus.AWAITING_RELEASE, "EstateEscrow: Escrow is not in a state to dispute");

        escrow.status = EscrowStatus.DISPUTED;

        emit DisputeRaised(_escrowId);
    }

    /// @notice Arbiter resolves the dispute
    /// @param _escrowId ID of the escrow
    /// @param _releaseToSeller If true, funds are released to the seller; else refunded to buyer
    function resolveDispute(uint256 _escrowId, bool _releaseToSeller) external nonReentrant {
        require(hasRole(ARBITER_ROLE, msg.sender), "EstateEscrow: Must have arbiter role to resolve disputes");
        Escrow storage escrow = escrows[_escrowId];

        require(escrow.status == EscrowStatus.DISPUTED, "EstateEscrow: Escrow is not disputed");

        // Fetch oracle data if necessary
        escrow.oracleData = getOracleData();

        if (_releaseToSeller) {
            escrow.seller.sendValue(escrow.amount);
            escrow.status = EscrowStatus.COMPLETE;
            emit DisputeResolved(_escrowId, EscrowStatus.COMPLETE);
            emit FundsWithdrawn(_escrowId, escrow.seller, escrow.amount);
        } else {
            escrow.buyer.sendValue(escrow.amount);
            escrow.status = EscrowStatus.REFUNDED;
            emit DisputeResolved(_escrowId, EscrowStatus.REFUNDED);
            emit FundsWithdrawn(_escrowId, escrow.buyer, escrow.amount);
        }
    }

    /// @notice Fetches the latest price from the Chainlink oracle
    /// @return price The latest price from the oracle
    function getOracleData() internal view returns (uint256 price) {
        (
            ,
            int256 answer,
            ,
            ,
        ) = priceFeed.latestRoundData();
        require(answer >= 0, "EstateEscrow: Invalid oracle data");
        price = uint256(answer);
    }

    /// @notice Allows accounts with the appropriate admin role to grant roles to other accounts
    /// @param role The role to grant
    /// @param account The account to grant the role to
    function grantRoleToAccount(bytes32 role, address account) external {
        grantRole(role, account);
    }

    /// @notice Allows accounts with the appropriate admin role to revoke roles from other accounts
    /// @param role The role to revoke
    /// @param account The account to revoke the role from
    function revokeRoleFromAccount(bytes32 role, address account) external {
        revokeRole(role, account);
    }
}