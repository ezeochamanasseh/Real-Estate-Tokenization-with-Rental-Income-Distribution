# Real Estate Tokenization with Rental Income Distribution

A smart contract system built on Stacks blockchain that enables real estate tokenization and automated rental income distribution.

## Features

- Property tokenization
- Token purchases by investors 
- Rental income distribution
- Token balance tracking
- Property information management

## Smart Contract Functions

### Public Functions

`add-property`
- Adds a new property with specified price and total tokens
- Only contract owner can add properties
- Returns property ID on success

`buy-tokens`
- Allows users to purchase tokens for a specific property
- Validates token amount against available supply
- Updates token holdings mapping

`distribute-rental-income`
- Distributes rental income for a property
- Only contract owner can trigger distribution
- Updates property rental income records

### Read-Only Functions

`get-property`
- Retrieves complete property details including:
  - Owner
  - Price
  - Rental income
  - Total tokens

`get-token-balance`
- Returns token balance for a specific holder and property

## Testing

Tests cover all core functionality:

## Project Structure

├── contracts/
│   └── real-estate.clar
├── tests/
│   └── real-estate.test.ts
└── .github/
    └── workflows/
        └── tests.yaml
