# Marlowe

This repository contains a preliminary design of Marlowe, a DSL for describing smart-contracts that can be enforced by scripts deployed on a cryptocurrency's blockchain, and some tools for analysing and simulating the execution of contracts written in the DSL.

- `src/Semantics.hs` —  contains the small-step semantics of DSL (`stepBlock` function), together with a simple driver (`driver` function).
- `src/ContractFormatter.hs` — contains the implementation of a formatter for scdsl code.
- `src/SmartInputs.hs` — contains code that calculates possible inputs for a
 given input, state, contract, and observables value.
- `src/DepositIncentive.hs` —  contains an example contract for incentivising saving.
- `src/CrowdFunding.hs` —  contains an example contract for crowd-funding limited to 4 participants.
- `src/Escrow.hs` —  contains an example contract for an escrow payment.

## Meadow

Meadow is a browser-based demo prototype that supports graphical editing of smart-contracts (thanks to the Blockly library) and block by block simulation of their execution (translated from the semantics thanks to the Haste compiler).

Meadow is available at: https://input-output-hk.github.io/marlowe/

The sources for Meadow are available in the `meadow` folder.

## Build on MacOS

Requirements: Homebrew, Haskell Stack 1.6 or later.

Install Haskell Stack if you haven't already

    $ brew install haskell-stack

    $ brew install glpk
    $ stack setup
    $ stack build
