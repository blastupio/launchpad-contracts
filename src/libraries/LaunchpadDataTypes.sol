// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

library LaunchpadDataTypes {
    enum UserTiers {
        BRONZE,
        SILVER,
        GOLD,
        TITANIUM,
        PLATINUM,
        DIAMOND
    }

    struct User {
        // Amount of tokens user have already claimed.
        uint256 claimedAmount;
        // Total amount of tokens user have bought during sale.
        uint256 boughtAmount;
        // Total amount of tokens user bought during public sale.
        // Used when accounting for limits of low/high tier pool sizes and weights.
        uint256 boughtPublicSale;
        // User's tier claimed on registration.
        UserTiers tier;
        // Whether a user have registered for the given sale.
        bool registered;
    }

    enum SaleStatus {
        NOT_PLACED,
        BEFORE_REGISTARTION,
        REGISTRATION,
        POST_REGISTRATION,
        PUBLIC_SALE,
        FCFS_SALE,
        POST_SALE
    }

    struct PlacedToken {
        // Price of a single token being sold in USDB.
        uint256 price;
        // Left volume for users buying through YieldStaking.
        uint256 volumeForYieldStakers;
        // Total left volume.
        uint256 volume;
        // Total size of the public sale pool available to low tiers.
        uint256 initialVolumeForLowTiers;
        // Total size of the public sale pool available to high tiers.
        uint256 initialVolumeForHighTiers;
        // Total weight of all registered users with low tiers.
        uint256 lowTiersWeightsSum;
        // Total weight of all registered users with high tiers.
        uint256 highTiersWeightsSum;
        // Address receiving funds from the sale.
        address addressForCollected;
        // Registration start timestamp.
        uint256 registrationStart;
        // Registration end timestamp.
        uint256 registrationEnd;
        // Public sale start timestamp.
        uint256 publicSaleStart;
        // FCFS sale start timestamp.
        uint256 fcfsSaleStart;
        // Sale end timestamp.
        uint256 saleEnd;
        // Timestamp of the TGE unlock.
        uint256 tgeStart;
        // Timestamp when linear vesting of bought token starts.
        uint256 vestingStart;
        // Duration of the linear vesting.
        uint256 vestingDuration;
        // Decimals of the listed token.
        uint8 tokenDecimals;
        // Percent from bought tokens which unlocks after TGE.
        uint8 tgePercent;
        // Whether the project requires approving signature for registration/purchase.
        bool approved;
        // Address of the listed token.
        address token;
        // Opens the opportunity for all BLP token holders with the minimum required balance to participate in the fcfs round.
        bool fcfsOpened;
        // Minimum tier for participation in FCFS which corresponds to the required user's balance.
        UserTiers fcfsRequiredTier;
    }
}
