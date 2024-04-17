# BlastUP.io Launchpad Contracts

This is the repository for BlastUP launchpad contracts. BlastUP is the first launchpad on Blast. More details available in official [Official BlastUP Documentation](https://docs.blastup.io/blastup-docs/general/blastup-launchpad).


### Features

- **Project Screening**. BlastUP carefully evaluates all potential projects to ensure that only the highest quality ones are presented to the public. Continuous screening will be conducted in the future.
- **Launchpad Accelerator**. We help projects prepare documentation and tokenomics to ensure they can raise the necessary funds for development.
- **Community Incentives Program**. We aim to engage new users in the Blast network and reward those who demonstrate the highest level of activity.
- **Fair Distribution**. BlastUP token holders are guaranteed a reserved allocation for upcoming IDO projects based on the number of staked BlastUP tokens they own.
- **Passive Income**. Grow your BlastUP token supply by staking and farming on our staking portal. As a token holder, you can also take advantage of our seed staking feature, which provides you with free tokens from our supported projects.

## Getting Started

This section guides you through getting started with our contracts, including prerequisites, installation, and basic usage.

### Prerequisites

- Foundry
- Forge from Foundry

### Installation

Clone the repository and install dependencies:

```bash
git clone https://github.com/blastupio/launchpad-contracts.git
cd launchpad-contracts
```
Install Foundry (from official [Foundry documentation](https://book.getfoundry.sh/getting-started/installation)):

```bash
curl -L https://foundry.paradigm.xyz | bash
```

### Build & Test
We use Forge from Foundry to build and test our contracts. Check [official Foundry documentation](https://book.getfoundry.sh/getting-started/installation) to install Foundry and Forge.

To build the contracts, run the following command:
```bash
forge build
```

To test the contracts, run the following commands:
```bash
forge test
```

### Deployment

To deploy contracts on Blast Sepolia testnet, run the following commands:
```bash
forge script DeployScript --sig 'deploySepolia()' --rpc-url https://sepolia.blast.io --broadcast --private-key <DEPLOYER_KEY>
```

## Contact

For any questions or suggestions, please contact [hello@blastup.io](mailto:hello@blastup.io), or open an issue in this repository.