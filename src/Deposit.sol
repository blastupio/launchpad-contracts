// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract Deposit is Ownable, Pausable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using SafeERC20 for IERC20;

    struct SwapData {
        address router;
        IERC20 tokenIn;
        uint256 amountIn;
        bytes data;
    }

    /// @notice Address of the authorized signer
    address public signer;

    /// @notice Address of the receiver for deposited funds
    address public depositReceiver;

    /// @notice Mapping to track deposited amounts for each project and user
    mapping(uint256 => mapping(address => uint256)) public depositedAmount;

    mapping(uint256 => bool) nonces;

    /* ========== CONSTRUCTOR ========== */

    /// @notice Initializes the contract with admin, signer, and deposit receiver addresses
    /// @param admin The address of the contract administrator
    /// @param _signer The address of the authorized signer
    /// @param _depositReceiver The address of the receiver for deposited funds
    constructor(address admin, address _signer, address _depositReceiver) Ownable(admin) {
        signer = _signer;
        depositReceiver = _depositReceiver;

        emit DepositReceiverChanged(address(0), _depositReceiver);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @notice Verifies the deposit signature and updates the deposited amount
    /// @param signature The signature to verify
    /// @param projectId The ID of the project to deposit to
    /// @param depositToken The token being deposited
    /// @param amount The amount of tokens to deposit
    /// @param deadline The deadline for the deposit signature
    function _beforeDeposit(
        bytes calldata signature,
        uint256 projectId,
        IERC20 depositToken,
        uint256 amount,
        uint256 deadline,
        uint256 nonce,
        bytes calldata data
    ) internal {
        require(!nonces[nonce], "BlastUP: this nonce is already used");
        require(block.timestamp <= deadline, "BlastUP: the deadline for this signature has passed");

        address signer_ = keccak256(
            abi.encodePacked(msg.sender, projectId, depositToken, amount, deadline, depositReceiver, nonce, data)
        ).toEthSignedMessageHash().recover(signature);
        require(signer_ == signer, "BlastUP: signature verification failed");

        depositedAmount[projectId][msg.sender] += amount;
        nonces[nonce] = true;

        emit Deposited(msg.sender, projectId, depositToken, amount, depositReceiver, nonce, data);
    }

    /* ========== FUNCTIONS ========== */

    /// @notice Pauses the contract, disabling certain functions
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract, enabling certain functions
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Sets a new signer address
    /// @param _signer The new signer address
    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
    }

    /// @notice Sets a new deposit receiver address
    /// @param _depositReceiver The new deposit receiver address
    function setDepositReceiver(address _depositReceiver) external onlyOwner {
        emit DepositReceiverChanged(depositReceiver, _depositReceiver);
        depositReceiver = _depositReceiver;
    }

    /// @notice Deposits tokens to the specified project
    /// @param signature The signature to verify
    /// @param projectId The ID of the project to deposit to
    /// @param depositToken The token being deposited
    /// @param amount The amount of tokens to deposit
    /// @param deadline The deadline for the deposit signature
    function deposit(
        bytes calldata signature,
        uint256 projectId,
        IERC20 depositToken,
        uint256 amount,
        uint256 deadline,
        uint256 nonce,
        bytes calldata data
    ) external whenNotPaused {
        _beforeDeposit(signature, projectId, depositToken, amount, deadline, nonce, data);
        depositToken.safeTransferFrom(msg.sender, depositReceiver, amount);
    }

    /// @notice Deposits tokens to the specified project with an additional token swap
    /// @param signature The signature to verify
    /// @param projectId The ID of the project to deposit to
    /// @param depositToken The token being deposited
    /// @param amount The amount of tokens to deposit
    /// @param deadline The deadline for the deposit signature
    /// @param swapData The data for the token swap
    function depositWithSwap(
        bytes calldata signature,
        uint256 projectId,
        IERC20 depositToken,
        uint256 amount,
        uint256 deadline,
        SwapData calldata swapData,
        uint256 nonce,
        bytes calldata data
    ) external whenNotPaused {
        _beforeDeposit(signature, projectId, depositToken, amount, deadline, nonce, data);

        // Swap tokenIn to depositToken
        swapData.tokenIn.safeTransferFrom(msg.sender, address(this), swapData.amountIn);
        swapData.tokenIn.forceApprove(swapData.router, swapData.amountIn);
        (bool success,) = swapData.router.call(swapData.data);
        require(success, "BlastUP: swap failed");

        uint256 amountOut = depositToken.balanceOf(address(this));
        require(amountOut >= amount, "BlastUP: amount out lt amount");

        // Send tokens to the depositReceiver
        depositToken.safeTransfer(depositReceiver, amount);

        // Send the remaining amount back to the sender
        if (amountOut > amount) depositToken.safeTransfer(msg.sender, amountOut - amount);
    }

    /// @notice Withdraws funds accidentally sent to the contract
    /// @param token The address of the token to withdraw
    function withdrawFunds(address token) external onlyOwner {
        if (token == address(0)) {
            (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "BlastUP: failed to send ETH");
        } else {
            IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
        }
    }

    /// @notice Fallback function to prevent accidental ETH transfers
    receive() external payable {
        revert("BlastUP: you can not send eth to this contract");
    }

    /* ========== EVENTS ========== */

    /// @notice Emitted when tokens are deposited to a project
    /// @param buyer The address of the buyer
    /// @param indexedProjectId The ID of the project
    /// @param depositToken The token being deposited
    /// @param amount The amount of tokens deposited
    /// @param depositReceiver The address of the deposit receiver
    event Deposited(
        address indexed buyer,
        uint256 indexed indexedProjectId,
        IERC20 depositToken,
        uint256 amount,
        address depositReceiver,
        uint256 nonce,
        bytes indexed data
    );

    /// @notice Emitted when the deposit receiver address is changed
    /// @param oldDepositReceiver The old deposit receiver address
    /// @param newDepositReceiver The new deposit receiver address
    event DepositReceiverChanged(address oldDepositReceiver, address newDepositReceiver);
}
